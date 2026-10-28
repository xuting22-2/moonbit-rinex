///|
fn digits(text : String) -> Int raise CheckError {
  let s = text.trim().to_owned()
  if s.is_empty() || s.length() > 9 || s.iter().any(c => c < '0' || c > '9') {
    raise Rejected("integer", 0, "expected bounded unsigned decimal: " + s)
  }
  @strconv.parse_int(s) catch {
    _ => raise Rejected("integer", 0, "overflow")
  }
}

///|
fn leap(y : Int) -> Bool {
  y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
}

///|
fn day_ticks(y : Int, m : Int, d : Int) -> Int64 raise CheckError {
  if y < 1980 || y > 2100 || m < 1 || m > 12 {
    raise Rejected("date", 0, "supported calendar years 1980..2100")
  }
  let months = [
    31,
    if leap(y) {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  if d < 1 || d > months[m - 1] {
    raise Rejected("date", 0, "invalid calendar day")
  }
  let mut days = d - 1
  for year in 1980..<y {
    days += if leap(year) { 366 } else { 365 }
  }
  for month in 0..<(m - 1) {
    days += months[month]
  }
  days.to_int64() * 864000000000L
}

///|
// Exact fixed-point 100ns. No float rounding and no GNSS/UTC conversion.
fn seconds_ticks(text : String) -> Int64 raise CheckError {
  let s = text.trim().to_owned()
  let parts = s.split(".").map(v => v.to_owned()).collect()
  if parts.length() < 1 || parts.length() > 2 {
    raise Rejected("seconds", 0, "invalid decimal seconds")
  }
  let whole = digits(parts[0])
  let mut fraction = 0
  if parts.length() == 2 {
    let f = parts[1]
    if f.length() > 7 || f.is_empty() {
      raise Rejected("seconds", 0, "at most 7 fractional decimal digits")
    }
    fraction = digits(f)
    for _ in f.length()..<7 {
      fraction *= 10
    }
  }
  whole.to_int64() * 10000000L + fraction.to_int64()
}

///|
fn timestamp(
  y : String,
  m : String,
  d : String,
  h : String,
  minute : String,
  second : String,
) -> Int64 raise CheckError {
  let hour = digits(h)
  let min = digits(minute)
  let sec = seconds_ticks(second)
  if hour > 23 || min > 59 || sec >= 600000000L {
    raise Rejected("time", 0, "invalid time or unsupported leap second")
  }
  day_ticks(digits(y), digits(m), digits(d)) +
  (hour * 3600 + min * 60).to_int64() * 10000000L +
  sec
}

///|
pub fn Window::epn_daily(
  year : Int,
  month : Int,
  day : Int,
) -> Window raise CheckError {
  let start = day_ticks(year, month, day)
  { start, stop: start + 864000000000L, kind: "EPN daily GPS 30s subset", }
}

///|
pub fn Window::epn_hourly(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
) -> Window raise CheckError {
  if hour < 0 || hour > 23 {
    raise Rejected("profile", 0, "hour must be 0..23")
  }
  let start = day_ticks(year, month, day) + hour.to_int64() * 36000000000L
  { start, stop: start + 36000000000L, kind: "EPN hourly GPS 30s subset", }
}

///|
fn part(s : String, start : Int, end : Int) -> String {
  if start >= s.length() {
    ""
  } else {
    s[start:s.length().min(end)].to_owned()
  }
}

///|
fn trimmed(s : String, start : Int, end : Int) -> String {
  part(s, start, end).trim().to_owned()
}

///|
fn decimal(text : String) -> Double raise CheckError {
  let s = text.trim().to_owned()
  if s.is_empty() ||
    s
    .iter()
    .any(c => {
      !(c >= '0' && c <= '9') &&
      c != '+' &&
      c != '-' &&
      c != '.' &&
      c != 'E' &&
      c != 'e' &&
      c != 'D' &&
      c != 'd'
    }) {
    raise Rejected("observation-number", 0, "invalid numeric field")
  }
  let normalized = s.replace(old="D", new="E").replace(old="d", new="e")
  let n = @strconv.parse_double(normalized) catch {
    _ => raise Rejected("observation-number", 0, "invalid decimal")
  }
  if n.is_nan() || n.is_inf() {
    raise Rejected("observation-number", 0, "nonfinite observation")
  }
  n
}
