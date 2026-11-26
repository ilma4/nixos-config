use std::fmt::Write as _;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Seek, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;
use std::{env, thread};

const MODES: [&str; 3] = ["network", "cpu", "ram"];
const CONTROLS: &str = "Click / scroll up: next · Scroll down: previous";
type Stats = (String, String, &'static str);

fn selected_mode(step: i32) -> io::Result<&'static str> {
    let runtime_dir = env::var_os("XDG_RUNTIME_DIR")
        .ok_or_else(|| io::Error::other("XDG_RUNTIME_DIR is not set"))?;
    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(PathBuf::from(runtime_dir).join("waybar-system-stats"))?;

    if step == 0 {
        file.lock_shared()?;
    } else {
        file.lock()?;
    }
    let mut previous = Vec::new();
    file.read_to_end(&mut previous)?;
    let index = MODES
        .iter()
        .position(|mode| mode.as_bytes() == previous)
        .unwrap_or(0);
    let mode = MODES[(index as i32 + step).rem_euclid(MODES.len() as i32) as usize];
    if step != 0 {
        file.rewind()?;
        file.set_len(0)?;
        file.write_all(mode.as_bytes())?;
    }
    Ok(mode)
}

fn nmcli(args: &[&str]) -> io::Result<String> {
    let output = Command::new(env!("WAYBAR_STATS_TIMEOUT"))
        .args(["1s", env!("NMCLI"), "--terse", "--escape", "no"])
        .args(args)
        .env("LC_ALL", "C")
        .stderr(Stdio::null())
        .output()?;
    if !output.status.success() {
        return Err(io::Error::other(format!("nmcli: {}", output.status)));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn network() -> io::Result<Stats> {
    let devices = nmcli(&["-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"])?;
    for line in devices.lines() {
        let mut fields = line.splitn(4, ':');
        let (Some(device), Some(kind), Some("connected"), Some(name)) =
            (fields.next(), fields.next(), fields.next(), fields.next())
        else {
            continue;
        };
        match kind {
            "wifi" => {
                let access_points = nmcli(&[
                    "-f",
                    "IN-USE,SIGNAL,SSID",
                    "device",
                    "wifi",
                    "list",
                    "ifname",
                    device,
                    "--rescan",
                    "no",
                ])?;
                let active = access_points
                    .lines()
                    .find_map(|line| line.strip_prefix("*:"));
                let text = match active.and_then(|line| line.split_once(':')) {
                    Some((strength, ssid)) => {
                        let ssid = if ssid.is_empty() { name } else { ssid };
                        format!("{ssid} ({strength}%) ")
                    }
                    None => format!("{name} "),
                };
                return Ok((text, format!("Wi-Fi: {device}"), "network"));
            }
            "ethernet" => {
                let addresses =
                    nmcli(&["-g", "IP4.ADDRESS,IP6.ADDRESS", "device", "show", device])?;
                let address = addresses
                    .lines()
                    .find(|line| !line.is_empty())
                    .unwrap_or(name);
                return Ok((
                    format!("{address} "),
                    format!("Ethernet: {device} ({name})"),
                    "network",
                ));
            }
            _ => continue,
        }
    }
    Ok((
        "Disconnected ⚠".into(),
        "No connected Wi-Fi or Ethernet device".into(),
        "disconnected",
    ))
}

fn cpu_sample() -> io::Result<(u64, u64)> {
    let mut line = String::new();
    BufReader::new(File::open("/proc/stat")?).read_line(&mut line)?;
    let mut fields = line.split_whitespace().skip(1);
    let mut ticks = [0_u64; 8];
    for tick in &mut ticks {
        *tick = fields
            .next()
            .and_then(|field| field.parse().ok())
            .ok_or_else(|| io::Error::other("invalid CPU counters in /proc/stat"))?;
    }
    Ok((ticks.iter().sum(), ticks[3] + ticks[4]))
}

fn cpu() -> io::Result<Stats> {
    let (before, idle_before) = cpu_sample()?;
    thread::sleep(Duration::from_millis(150));
    let (after, idle_after) = cpu_sample()?;
    let total = after.saturating_sub(before);
    let busy = total.saturating_sub(idle_after.saturating_sub(idle_before));
    let usage = 100.0 * busy as f64 / total.max(1) as f64;
    Ok((format!("{usage:.0}% "), "CPU usage".into(), "cpu"))
}

fn ram() -> io::Result<Stats> {
    let memory = fs::read_to_string("/proc/meminfo")?;
    let value = |key| {
        memory
            .lines()
            .find_map(|line| line.strip_prefix(key))
            .and_then(|value| value.split_whitespace().next())
            .and_then(|value| value.parse::<u64>().ok())
            .ok_or_else(|| io::Error::other(format!("missing {key} in /proc/meminfo")))
    };
    let total = value("MemTotal:")? as f64;
    let used = total - value("MemAvailable:")? as f64;
    let gib = f64::from(1 << 20);
    Ok((
        format!("{:.0}% ", 100.0 * used / total),
        format!("RAM: {:.1} / {:.1} GiB", used / gib, total / gib),
        "ram",
    ))
}

fn json_string(value: &str) -> String {
    let mut result = String::with_capacity(value.len() + 2);
    result.push('"');
    for ch in value.chars() {
        match ch {
            '"' => result.push_str("\\\""),
            '\\' => result.push_str("\\\\"),
            '\n' => result.push_str("\\n"),
            '\0'..='\x1f' => write!(result, "\\u{:04x}", u32::from(ch)).unwrap(),
            _ => result.push(ch),
        }
    }
    result.push('"');
    result
}

fn main() -> io::Result<()> {
    let step = match env::args_os().nth(1) {
        None => 0,
        Some(arg) if arg == "next" => 1,
        Some(arg) if arg == "previous" => -1,
        _ => {
            return Err(io::Error::other(
                "usage: waybar-system-stats [next|previous]",
            ))
        }
    };
    let mode = selected_mode(step)?;
    if step != 0 {
        return Ok(());
    }
    let (text, tooltip, class) = match mode {
        "cpu" => cpu()?,
        "ram" => ram()?,
        _ => network().unwrap_or_else(|_| {
            (
                "Network unavailable ⚠".into(),
                "Could not read NetworkManager status".into(),
                "disconnected",
            )
        }),
    };
    println!(
        "{{\"text\":{},\"tooltip\":{},\"class\":{}}}",
        json_string(&text),
        json_string(&format!("{tooltip}\n{CONTROLS}")),
        json_string(class)
    );
    Ok(())
}
