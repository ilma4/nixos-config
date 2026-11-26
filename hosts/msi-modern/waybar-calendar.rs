use std::ffi::c_int;
use std::fmt::Write as _;
use std::io;

const MONTH_NAMES: [&str; 12] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];
const COLUMN_WIDTH: usize = 20; // Seven two-character days, with spaces between them.

#[repr(C)]
struct GDateTime {
    _opaque: [u8; 0],
}

#[link(name = "glib-2.0")]
unsafe extern "C" {
    fn g_date_time_new_now_local() -> *mut GDateTime;
    fn g_date_time_get_ymd(
        date: *mut GDateTime,
        year: *mut c_int,
        month: *mut c_int,
        day: *mut c_int,
    );
    fn g_date_time_get_day_of_week(date: *mut GDateTime) -> c_int;
    fn g_date_time_unref(date: *mut GDateTime);
    fn g_date_get_days_in_month(month: c_int, year: u16) -> u8;
}

fn local_date() -> io::Result<(Month, i32, i32)> {
    // SAFETY: The constructor returns an owned reference or null. For a valid
    // reference, the output pointers address writable integers and we unref once.
    unsafe {
        let date = g_date_time_new_now_local();
        if date.is_null() {
            return Err(io::Error::other("GLib could not determine the local date"));
        }
        let (mut year, mut number, mut day) = (0, 0, 0);
        g_date_time_get_ymd(date, &mut year, &mut number, &mut day);
        let weekday = g_date_time_get_day_of_week(date);
        g_date_time_unref(date);
        Ok((Month { year, number }, day, weekday))
    }
}

#[derive(Clone, Copy)]
struct Month {
    year: i32,
    number: i32,
}

impl Month {
    fn shift(self, offset: i32) -> Self {
        let number = self.number - 1 + offset;
        Self {
            year: self.year + number.div_euclid(12),
            number: number.rem_euclid(12) + 1,
        }
    }

    fn days(self) -> i32 {
        // The Gregorian calendar repeats every 400 years. Keep GDateYear nonzero
        // even if the previous month of a boundary GDateTime falls in year zero.
        let year = (self.year - 1).rem_euclid(400) as u16 + 1;
        // SAFETY: `number` is a GLib month (1–12) and `year` is a valid GDateYear.
        i32::from(unsafe { g_date_get_days_in_month(self.number, year) })
    }

    fn column(self, first_weekday: i32, today: Option<i32>) -> [String; 8] {
        let heading = format!("{} {}", MONTH_NAMES[(self.number - 1) as usize], self.year);
        let days = self.days();
        std::array::from_fn(|row| match row {
            0 => format!("<b>{heading:^COLUMN_WIDTH$}</b>"),
            1 => "Mo Tu We Th Fr Sa Su".into(),
            _ => {
                let mut week = String::new();
                for weekday in 0..7 {
                    if weekday != 0 {
                        week.push(' ');
                    }
                    let day = 1 + (row as i32 - 2) * 7 + weekday - first_weekday;
                    if !(1..=days).contains(&day) {
                        week.push_str("  ");
                    } else if Some(day) == today {
                        write!(week, r##"<span background="#f6d32d" foreground="#241f31"><b>{day:2}</b></span>"##).unwrap();
                    } else {
                        write!(week, "{day:2}").unwrap();
                    }
                }
                week
            }
        })
    }
}

fn calendar_tooltip(current: Month, day: i32, weekday: i32) -> String {
    let first = (weekday - day).rem_euclid(7); // Monday = 0 for the columns.
    let previous = current.shift(-1);
    let columns = [
        previous.column((first - previous.days()).rem_euclid(7), None),
        current.column(first, Some(day)),
        current.shift(1).column((first + current.days()) % 7, None),
    ];
    let rows = (0..8)
        .map(|row| {
            format!(
                "{}   {}   {}",
                columns[0][row], columns[1][row], columns[2][row]
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    format!("<tt>{}</tt>", rows.trim_end())
}

fn main() -> io::Result<()> {
    let (current, day, weekday) = local_date()?;
    let Month { year, number } = current;
    let tooltip = calendar_tooltip(current, day, weekday);
    // The tooltip is built from fixed ASCII markup, spaces, digits, and newlines.
    let tooltip = tooltip.replace('"', "\\\"").replace('\n', "\\n");
    println!(r#"{{"text":"{year:04}-{number:02}-{day:02}","tooltip":"{tooltip}"}}"#);
    Ok(())
}
