use std::{
    env,
    error::Error,
    ffi::{c_char, c_int, c_long, c_void, OsStr},
    mem::MaybeUninit,
    path::PathBuf,
    ptr, thread,
    time::Duration,
};

use objc2_core_foundation::{
    kCFRunLoopDefaultMode, CFArray, CFDictionary, CFNumber, CFRetained, CFRunLoop,
    CFString, CFType,
};
use objc2_io_kit::{
    kIOFirstMatchNotification, kIOMainPortDefault, io_iterator_t, IOHIDEventSystemClient,
    IOHIDServiceClient, IONotificationPort, IOIteratorNext, IOObjectRelease,
    IOServiceAddMatchingNotification,
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

/// Outcome of one attempt to set `UserKeyMapping` on the matching services.
enum ApplyResult {
    /// Applied to at least one matching event service.
    Applied,
    /// No event service matched (yet) — on a fresh reconnect the service is
    /// usually just not published yet, so the caller may retry.
    NoServiceYet,
    /// Matching service(s) were found but the property could not be set; the
    /// specific error has already been logged, and retrying will not help.
    Failed,
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

    /// Attempt to re-apply the remapping once. macOS discards `UserKeyMapping`
    /// whenever the keyboard disconnects, and the remap is consumed at the HID
    /// event-system level (the `IOHIDServiceClient`), not on the raw
    /// `IOHIDDevice` — so this sets the property on every event service matching
    /// the watched vendor/product, exactly like `hidutil property --matching
    /// ... --set`.
    fn try_apply(&self) -> ApplyResult {
        // A fresh simple client mirrors hidutil's per-invocation behaviour and
        // always reflects the services present right now. Creating it (and
        // setting service properties) needs no Input Monitoring permission.
        let client = IOHIDEventSystemClient::new_simple_client(None);

        let Some(services) = client.services() else {
            log!("error: could not copy HID event services");
            return ApplyResult::Failed;
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

        if applied > 0 {
            ApplyResult::Applied
        } else if matched == 0 {
            ApplyResult::NoServiceYet
        } else {
            ApplyResult::Failed
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

fn service_property(
    service: &IOHIDServiceClient,
    key: &'static str,
) -> Option<CFRetained<CFType>> {
    service.property(&CFString::from_static_str(key))
}

/// Matching dictionary equivalent to `IOServiceMatching("IOHIDDevice")` plus a
/// VendorID/ProductID filter: `{IOProviderClass, VendorID, ProductID}`. The
/// returned dictionary is owned and ready to be consumed by
/// `IOServiceAddMatchingNotification`.
fn matching_dictionary(vendor_id: u32, product_id: u32) -> CFRetained<CFDictionary> {
    let provider_key = CFString::from_static_str("IOProviderClass");
    let provider_value = CFString::from_static_str("IOHIDDevice");
    let vendor_key = CFString::from_static_str("VendorID");
    let product_key = CFString::from_static_str("ProductID");
    let vendor_value = CFNumber::new_i64(i64::from(vendor_id));
    let product_value = CFNumber::new_i64(i64::from(product_id));

    let provider_value: &CFType = &provider_value;
    let vendor_value: &CFType = &vendor_value;
    let product_value: &CFType = &product_value;

    let dict = CFDictionary::<CFString, CFType>::from_slices(
        &[&provider_key, &vendor_key, &product_key],
        &[provider_value, vendor_value, product_value],
    );

    // Erase the generic parameters to the untyped `CFDictionary` that
    // `IOServiceAddMatchingNotification` expects. Ownership transfers intact.
    unsafe { CFRetained::from_raw(CFRetained::into_raw(dict).cast::<CFDictionary>()) }
}

// When a keyboard (re)connects, its IOHIDDevice IORegistry node — which triggers
// our notification — is published slightly before its IOHIDEventSystem service,
// so the first apply can find no matching service. Retry until it shows up.
// 25 * 200ms ≈ 5s, comfortably longer than the observed publish delay.
const RETRY_ATTEMPTS: u32 = 25;
const RETRY_INTERVAL: Duration = Duration::from_millis(200);

/// Drain a matching iterator — required to re-arm the notification — and, if it
/// produced any matching IORegistry nodes, (re)apply the remapping.
fn process_matches(state: &'static State, iterator: io_iterator_t) {
    let mut count = 0usize;
    loop {
        let object = IOIteratorNext(iterator);
        if object == 0 {
            break;
        }
        count += 1;
        IOObjectRelease(object);
    }

    if count == 0 {
        return;
    }

    log!("matching HID device connected ({count} IORegistry node(s)); applying remap");

    if let ApplyResult::NoServiceYet = state.try_apply() {
        // The event service is not published yet. Retry on a background thread
        // so the run loop stays free to receive further connect notifications.
        let budget_s = (u128::from(RETRY_ATTEMPTS) * RETRY_INTERVAL.as_millis()) / 1000;
        log!("event service not published yet; retrying for up to ~{budget_s}s");

        thread::spawn(move || {
            for _ in 0..RETRY_ATTEMPTS {
                thread::sleep(RETRY_INTERVAL);
                if !matches!(state.try_apply(), ApplyResult::NoServiceYet) {
                    return;
                }
            }
            log!(
                "error: no HID event service matched {:04x}:{:04x} after ~{budget_s}s; remap not applied",
                state.vendor_id,
                state.product_id,
            );
        });
    }
}

unsafe extern "C-unwind" fn device_appeared(ref_con: *mut c_void, iterator: io_iterator_t) {
    // Safety: `ref_con` is the leaked State from run(); it lives for the whole
    // program, so treating it as `'static` is sound.
    let state: &'static State = unsafe { &*ref_con.cast::<State>() };
    process_matches(state, iterator);
}

fn run() -> Result<(), AnyError> {
    let config = Config::from_args()?;

    // Leak the State: it must outlive every notification (the run loop never
    // returns, and retry threads may still be running), and a long-lived daemon
    // never frees it anyway. This lets the callback treat it as `'static`.
    let state: &'static State = Box::leak(Box::new(State {
        vendor_id: config.vendor_id,
        product_id: config.product_id,
        mappings: config.mappings,
    }));

    let run_loop =
        CFRunLoop::current().ok_or("failed to get current run loop")?;

    // Safety: this is a process-wide Core Foundation constant.
    let run_loop_mode = unsafe { kCFRunLoopDefaultMode }
        .ok_or("default run-loop mode is unavailable")?;

    // Watch the IORegistry for the keyboard appearing, rather than opening it
    // through IOHIDManager: registry matching needs no Input Monitoring
    // permission, so this works as a background launchd job.
    let notify_port = IONotificationPort::create(unsafe { kIOMainPortDefault });
    if notify_port.is_null() {
        return Err("failed to create IONotificationPort".into());
    }

    // Safety: `notify_port` was just created and is non-null.
    let source = unsafe { IONotificationPort::run_loop_source(notify_port) }
        .ok_or("notification port has no run-loop source")?;
    run_loop.add_source(Some(&source), Some(run_loop_mode));

    let context = ptr::from_ref(state)
        .cast_mut()
        .cast::<c_void>();

    let mut iterator: io_iterator_t = 0;

    // Safety:
    //
    // - `notify_port` is valid and scheduled on this run loop.
    // - The matching dictionary is well-formed and consumed by the call.
    // - `context` stays valid while the notification is registered.
    // - `iterator` is a valid out-pointer.
    let result = unsafe {
        IOServiceAddMatchingNotification(
            notify_port,
            kIOFirstMatchNotification.as_ptr().cast::<[c_char; 128]>().cast_mut(),
            Some(matching_dictionary(config.vendor_id, config.product_id)),
            Some(device_appeared),
            context,
            &mut iterator,
        )
    };

    if result != 0 {
        return Err(
            format!("IOServiceAddMatchingNotification failed: {result:#x}").into(),
        );
    }

    log!(
        "watching for HID device {:04x}:{:04x}",
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

    // Drain the initial iterator: this both arms the notification and applies
    // the remapping to a keyboard that is already connected at startup.
    process_matches(state, iterator);

    CFRunLoop::run();

    // Normally unreachable unless the run loop is explicitly stopped.
    run_loop.remove_source(Some(&source), Some(run_loop_mode));

    // Safety: `notify_port` is still valid; this also releases `source`.
    unsafe { IONotificationPort::destroy(notify_port) };

    Ok(())
}

fn main() {
    if let Err(error) = run() {
        log!("error: {error}");
        std::process::exit(1);
    }
}
