use std::{
    env,
    error::Error,
    ffi::{c_char, c_int, c_long, c_void, OsStr},
    mem::MaybeUninit,
    path::PathBuf,
    ptr::{self, NonNull},
};

use objc2_core_foundation::{
    kCFRunLoopDefaultMode, CFArray, CFDictionary, CFNumber, CFRetained, CFRunLoop,
    CFString, CFType,
};
use objc2_io_kit::{
    kIOHIDOptionsTypeNone, kIOReturnSuccess, IOHIDDevice, IOHIDEventSystemClient,
    IOHIDManager, IOHIDServiceClient, IOReturn,
};

type AnyError = Box<dyn Error>;

/// Prepend a local timestamp (in `/bin/date`'s default format) to every log
/// line, so the watcher's output in /tmp/keyboard-watcher.log is easy to follow.
macro_rules! log {
    ($($arg:tt)*) => {
        eprintln!("{}: {}", timestamp(), format_args!($($arg)*))
    };
}

// macOS `struct tm` / libc bindings, declared locally to avoid pulling in a
// crate just for a timestamp. This program is darwin-only and the layout is
// part of the stable macOS ABI.
type TimeT = c_long;

#[repr(C)]
struct Tm {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: *const c_char,
}

unsafe extern "C" {
    fn time(tloc: *mut TimeT) -> TimeT;
    fn localtime_r(clock: *const TimeT, result: *mut Tm) -> *mut Tm;
    fn strftime(
        buf: *mut c_char,
        maxsize: usize,
        format: *const c_char,
        timeptr: *const Tm,
    ) -> usize;
}

fn timestamp() -> String {
    let now = unsafe { time(ptr::null_mut()) };

    let mut tm = MaybeUninit::<Tm>::zeroed();
    let mut buf = [0u8; 64];

    // Safety: `localtime_r` populates `tm` from `now`, and `strftime` writes at
    // most `buf.len()` bytes into `buf`. Both are system libc calls.
    let len = unsafe {
        if localtime_r(&now, tm.as_mut_ptr()).is_null() {
            return String::new();
        }

        strftime(
            buf.as_mut_ptr().cast::<c_char>(),
            buf.len(),
            c"%a %b %e %H:%M:%S %Z %Y".as_ptr(),
            tm.as_ptr(),
        )
    };

    String::from_utf8_lossy(&buf[..len]).into_owned()
}

/// One `hidutil`-style key remapping: a source HID usage that is rewritten to a
/// destination HID usage. The values are the 64-bit codes hidutil uses, e.g.
/// `0x700000064` (Non-US `\|`) or `0xFF00000003` (Fn / Globe).
#[derive(Debug)]
struct KeyMapping {
    src: u64,
    dst: u64,
}

#[derive(Debug)]
struct Config {
    vendor_id: u32,
    product_id: u32,
    mappings: Vec<KeyMapping>,
}

impl Config {
    fn from_args() -> Result<Self, AnyError> {
        let mut args = env::args_os();

        let program = args
            .next()
            .and_then(|arg| {
                PathBuf::from(arg)
                    .file_name()
                    .map(OsStr::to_owned)
            })
            .unwrap_or_else(|| "keyboard-watcher".into());

        let vendor_id = args
            .next()
            .ok_or_else(|| usage(&program))?
            .into_string()
            .map_err(|_| "vendor ID is not valid UTF-8")?;

        let product_id = args
            .next()
            .ok_or_else(|| usage(&program))?
            .into_string()
            .map_err(|_| "product ID is not valid UTF-8")?;

        let mut mappings = Vec::new();
        for arg in args {
            let arg = arg
                .into_string()
                .map_err(|_| "key mapping is not valid UTF-8")?;
            mappings.push(parse_mapping(&arg)?);
        }

        if mappings.is_empty() {
            return Err(usage(&program).into());
        }

        Ok(Self {
            vendor_id: parse_u32(&vendor_id)?,
            product_id: parse_u32(&product_id)?,
            mappings,
        })
    }
}

fn usage(program: &OsStr) -> String {
    format!(
        "usage: {} <vendor-id> <product-id> <src:dst>...",
        program.to_string_lossy()
    )
}

fn parse_u32(value: &str) -> Result<u32, AnyError> {
    u32::try_from(parse_u64(value)?)
        .map_err(|_| format!("value {value} does not fit in 32 bits").into())
}

fn parse_u64(value: &str) -> Result<u64, AnyError> {
    let (digits, radix) = value
        .strip_prefix("0x")
        .or_else(|| value.strip_prefix("0X"))
        .map_or((value, 10), |digits| (digits, 16));

    Ok(u64::from_str_radix(digits, radix)?)
}

fn parse_mapping(arg: &str) -> Result<KeyMapping, AnyError> {
    let (src, dst) = arg
        .split_once(':')
        .ok_or_else(|| format!("key mapping {arg:?} must be in <src>:<dst> form"))?;

    Ok(KeyMapping {
        src: parse_u64(src)?,
        dst: parse_u64(dst)?,
    })
}

#[derive(Debug)]
struct State {
    vendor_id: u32,
    product_id: u32,
    mappings: Vec<KeyMapping>,
}

impl State {
    /// Build the `UserKeyMapping` property value that `hidutil property --set`
    /// would take: an array of `{src, dst}` dictionaries holding the 64-bit HID
    /// usage codes.
    fn user_key_mapping(&self) -> CFRetained<CFArray<CFType>> {
        let src_key = CFString::from_static_str("HIDKeyboardModifierMappingSrc");
        let dst_key = CFString::from_static_str("HIDKeyboardModifierMappingDst");

        // One dictionary per remapping. Keep them alive until the array has
        // retained them (`CFArrayCreate` retains every element).
        let entries: Vec<CFRetained<CFDictionary<CFString, CFNumber>>> = self
            .mappings
            .iter()
            .map(|mapping| {
                let src = CFNumber::new_i64(mapping.src as i64);
                let dst = CFNumber::new_i64(mapping.dst as i64);

                CFDictionary::<CFString, CFNumber>::from_slices(
                    &[&src_key, &dst_key],
                    &[&src, &dst],
                )
            })
            .collect();

        let entry_refs: Vec<&CFType> =
            entries.iter().map(|entry| -> &CFType { entry }).collect();

        CFArray::from_objects(&entry_refs)
    }

    /// Re-apply the remapping on every (re)connect.
    ///
    /// macOS resets `UserKeyMapping` whenever the keyboard disconnects, and the
    /// remap is consumed at the HID event-system level (the IOHIDServiceClient),
    /// not on the raw IOHIDDevice — so this sets the property on every event
    /// service that matches the watched vendor/product, exactly like
    /// `hidutil property --matching ... --set` does, but in-process.
    fn apply(&self, device_desc: &str) {
        // A fresh simple client mirrors hidutil's per-invocation behaviour and
        // always reflects the services present right now.
        let client = IOHIDEventSystemClient::new_simple_client(None);

        let Some(services) = client.services() else {
            log!("error: could not copy HID event services; {device_desc} not remapped");
            return;
        };

        // `IOHIDEventSystemClientCopyServices` yields an array of
        // IOHIDServiceClientRef, so retyping the opaque array is sound.
        let services: &CFArray<IOHIDServiceClient> =
            unsafe { services.cast_unchecked() };

        let key = CFString::from_static_str("UserKeyMapping");
        let mapping = self.user_key_mapping();
        let mapping: &CFType = &mapping;

        let mut matched = 0usize;
        let mut applied = 0usize;

        for service in services.iter() {
            let vendor = number_value(service_property(&service, "VendorID"));
            let product = number_value(service_property(&service, "ProductID"));

            if vendor != Some(i64::from(self.vendor_id))
                || product != Some(i64::from(self.product_id))
            {
                continue;
            }

            matched += 1;

            let service_desc = string_value(service_property(&service, "Product"))
                .unwrap_or_else(|| "unknown service".to_owned());

            // Safety: `key` and `mapping` are valid CF objects of the type the
            // "UserKeyMapping" property expects; the call only reads them.
            if unsafe { service.set_property(&key, mapping) } {
                applied += 1;
                log!(
                    "applied {} key remapping(s) to service \"{service_desc}\"",
                    self.mappings.len(),
                );
            } else {
                log!(
                    "error: IOHIDServiceClientSetProperty(\"UserKeyMapping\") \
                     returned false for service \"{service_desc}\"",
                );
                for mapping in &self.mappings {
                    log!("  not applied: {:#x} -> {:#x}", mapping.src, mapping.dst);
                }
            }
        }

        if matched == 0 {
            log!(
                "error: no HID event service matched {:04x}:{:04x}; {device_desc} not remapped",
                self.vendor_id,
                self.product_id,
            );
        } else if applied == 0 {
            log!("error: matched {matched} service(s) for {device_desc} but applied none");
        }
    }
}

fn string_value(value: Option<CFRetained<CFType>>) -> Option<String> {
    value
        .and_then(|value| value.downcast::<CFString>().ok())
        .map(|value| value.to_string())
}

fn number_value(value: Option<CFRetained<CFType>>) -> Option<i64> {
    value
        .and_then(|value| value.downcast::<CFNumber>().ok())
        .and_then(|value| value.as_i64())
}

fn device_property(
    device: &IOHIDDevice,
    key: &'static str,
) -> Option<CFRetained<CFType>> {
    device.property(&CFString::from_static_str(key))
}

fn service_property(
    service: &IOHIDServiceClient,
    key: &'static str,
) -> Option<CFRetained<CFType>> {
    service.property(&CFString::from_static_str(key))
}

unsafe extern "C-unwind" fn device_connected(
    context: *mut c_void,
    result: IOReturn,
    _sender: *mut c_void,
    device: NonNull<IOHIDDevice>,
) {
    if result != kIOReturnSuccess {
        log!("error: HID matching callback failed: {result:#x}");
        return;
    }

    // Safety:
    //
    // `context` points to the boxed State in main(). The box remains alive
    // while the manager is registered and the run loop is running.
    let state = unsafe { &*context.cast::<State>() };

    // Safety:
    //
    // IOKit guarantees that the callback's device reference is valid for
    // the duration of the callback.
    let device = unsafe { device.as_ref() };

    let product = string_value(device_property(device, "Product"))
        .unwrap_or_else(|| "unknown keyboard".to_owned());

    // The primary usage identifies which interface of a composite keyboard this
    // is (0x1:0x6 is GenericDesktop/Keyboard), keeping the logs unambiguous.
    let usage_page = number_value(device_property(device, "PrimaryUsagePage"));
    let usage = number_value(device_property(device, "PrimaryUsage"));

    let device_desc = match (usage_page, usage) {
        (Some(page), Some(usage)) => {
            format!("{product} [usage {page:#x}:{usage:#x}]")
        }
        _ => product,
    };

    log!("keyboard connected: {device_desc}");

    state.apply(&device_desc);
}

fn run() -> Result<(), AnyError> {
    let config = Config::from_args()?;

    let vendor_key = CFString::from_static_str("VendorID");
    let product_key = CFString::from_static_str("ProductID");

    let vendor_id = CFNumber::new_i64(i64::from(config.vendor_id));
    let product_id = CFNumber::new_i64(i64::from(config.product_id));

    let matching = CFDictionary::<CFString, CFNumber>::from_slices(
        &[&vendor_key, &product_key],
        &[&vendor_id, &product_id],
    );

    let state = Box::new(State {
        vendor_id: config.vendor_id,
        product_id: config.product_id,
        mappings: config.mappings,
    });

    let context = std::ptr::from_ref(state.as_ref())
        .cast_mut()
        .cast::<c_void>();

    let manager = IOHIDManager::new(None, kIOHIDOptionsTypeNone);

    let run_loop =
        CFRunLoop::current().ok_or("failed to get current run loop")?;

    // Safety: this is a process-wide Core Foundation constant.
    let run_loop_mode = unsafe { kCFRunLoopDefaultMode }
        .ok_or("default run-loop mode is unavailable")?;

    // Safety:
    //
    // - The matching dictionary contains valid IOHID matching key/value types.
    // - `context` remains valid while the manager is registered.
    // - The manager and run loop are used on this thread.
    unsafe {
        manager.set_device_matching(Some(matching.as_opaque()));

        manager.register_device_matching_callback(
            Some(device_connected),
            context,
        );

        manager.schedule_with_run_loop(
            &run_loop,
            run_loop_mode,
        );
    }

    let result = manager.open(kIOHIDOptionsTypeNone);

    if result != kIOReturnSuccess {
        return Err(
            format!("failed to open IOHIDManager: {result:#x}").into()
        );
    }

    log!(
        "watching HID device {:04x}:{:04x}",
        config.vendor_id,
        config.product_id,
    );
    for mapping in &state.mappings {
        log!(
            "will remap on connect: {:#x} -> {:#x}",
            mapping.src,
            mapping.dst,
        );
    }

    CFRunLoop::run();

    // Normally unreachable unless the run loop is explicitly stopped.
    unsafe {
        manager.unschedule_from_run_loop(
            &run_loop,
            run_loop_mode,
        );
    }

    manager.close(kIOHIDOptionsTypeNone);

    Ok(())
}

fn main() {
    if let Err(error) = run() {
        log!("error: {error}");
        std::process::exit(1);
    }
}
