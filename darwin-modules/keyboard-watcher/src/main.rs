use std::{
    env,
    error::Error,
    ffi::{c_char, c_int, c_long, c_void, OsStr},
    mem::MaybeUninit,
    path::PathBuf,
    process::Command,
    ptr::{self, NonNull},
    sync::Mutex,
    thread,
    time::{Duration, Instant},
};

use objc2_core_foundation::{
    kCFRunLoopDefaultMode, CFDictionary, CFNumber, CFRunLoop, CFString,
};
use objc2_io_kit::{
    kIOHIDOptionsTypeNone, kIOReturnSuccess, IOHIDDevice, IOHIDManager,
    IOReturn,
};

type AnyError = Box<dyn Error>;

const CALLBACK_DEBOUNCE: Duration = Duration::from_secs(1);

/// Prepend a local timestamp (in `/bin/date`'s default format) to every log
/// line, so the watcher's output in /tmp/keyboard-watcher.log lines up with the
/// remap script's own `$(date)` lines.
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

#[derive(Debug)]
struct Config {
    vendor_id: u32,
    product_id: u32,
    script: PathBuf,
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

        let script = args
            .next()
            .map(PathBuf::from)
            .ok_or_else(|| usage(&program))?;

        if args.next().is_some() {
            return Err(usage(&program).into());
        }

        if !script.is_absolute() {
            return Err("script path must be absolute".into());
        }

        Ok(Self {
            vendor_id: parse_id(&vendor_id)?,
            product_id: parse_id(&product_id)?,
            script,
        })
    }
}

fn usage(program: &OsStr) -> String {
    format!(
        "usage: {} <vendor-id> <product-id> <absolute-script-path>",
        program.to_string_lossy()
    )
}

fn parse_id(value: &str) -> Result<u32, AnyError> {
    let (digits, radix) = value
        .strip_prefix("0x")
        .or_else(|| value.strip_prefix("0X"))
        .map_or((value, 10), |digits| (digits, 16));

    Ok(u32::from_str_radix(digits, radix)?)
}

#[derive(Debug)]
struct State {
    script: PathBuf,

    // A composite keyboard may expose multiple HID interfaces, producing
    // several matching callbacks for one physical connection.
    last_run: Mutex<Option<Instant>>,
}

impl State {
    fn should_run(&self) -> bool {
        let mut last_run = self
            .last_run
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        if last_run.is_some_and(|last| last.elapsed() < CALLBACK_DEBOUNCE) {
            return false;
        }

        *last_run = Some(Instant::now());
        true
    }

    fn run_script(&self) {
        let script = self.script.clone();

        // Do not block the Core Foundation run loop. Waiting in this thread
        // also ensures that the child process is reaped.
        thread::spawn(move || {
            match Command::new(&script).status() {
                Ok(status) if status.success() => {
                    log!("mapping script completed successfully");
                }

                Ok(status) => {
                    log!("mapping script exited with {status}");
                }

                Err(error) => {
                    log!("failed to execute {}: {error}", script.display());
                }
            }
        });
    }
}

unsafe extern "C-unwind" fn device_connected(
    context: *mut c_void,
    result: IOReturn,
    _sender: *mut c_void,
    device: NonNull<IOHIDDevice>,
) {
    if result != kIOReturnSuccess {
        log!("HID matching callback failed: {result:#x}");
        return;
    }

    // Safety:
    //
    // `context` points to the boxed State in main(). The box remains alive
    // while the manager is registered and the run loop is running.
    let state = unsafe { &*context.cast::<State>() };

    if !state.should_run() {
        return;
    }

    // Safety:
    //
    // IOKit guarantees that the callback's device reference is valid for
    // the duration of the callback.
    let device = unsafe { device.as_ref() };

    let product_key = CFString::from_static_str("Product");

    let product_name = device
        .property(&product_key)
        .and_then(|value| value.downcast::<CFString>().ok())
        .map(|value| value.to_string())
        .unwrap_or_else(|| "unknown keyboard".to_owned());

    log!("keyboard connected: {product_name}");

    state.run_script();
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
        script: config.script,
        last_run: Mutex::new(None),
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
