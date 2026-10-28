///|
fn left_pad(s : String, width : Int) -> String {
  let b = StringBuilder()
  for _ in s.length()..<width {
    b.write_string(" ")
  }
  b.write_string(s)
  b.to_string()
}

///|
fn right_pad(s : String, width : Int) -> String {
  let b = StringBuilder()
  b.write_string(s)
  for _ in s.length()..<width {
    b.write_string(" ")
  }
  b.to_string()
}

///|
fn ascii_line(s : String) -> Unit raise CheckError {
  if s.length() > 8192 || s.iter().any(c => c < ' ' || c > '~') {
    raise Rejected(
      "ascii-capacity", 0, "expected at most 8192 printable ASCII characters",
    )
  }
}

///|
fn signed_integer64(s : String) -> Int64 raise CheckError {
  let s = s.trim().to_owned()
  if s.is_empty() {
    raise Rejected("integer64", 0, "empty integer")
  }
  let negative = s.has_prefix("-")
  let start = if negative || s.has_prefix("+") { 1 } else { 0 }
  if start == s.length() {
    raise Rejected("integer64", 0, "missing digits")
  }
  let mut n = 0L
  for i in start..<s.length() {
    let c = s[i].to_int()
    if c < 48 || c > 57 {
      raise Rejected("integer64", 0, "invalid integer")
    }
    let d = (c - 48).to_int64()
    if n > (9223372036854775807L - d) / 10L {
      raise Rejected("integer-overflow", 0, "64-bit numeric arc overflow")
    }
    n = n * 10L + d
  }
  if negative {
    -n
  } else {
    n
  }
}

///|
fn checked_add64(a : Int64, b : Int64) -> Int64 raise CheckError {
  if (b > 0L && a > 9223372036854775807L - b) ||
    (b < 0L && a < -9223372036854775807L - b) {
    raise Rejected("integer-overflow", 0, "64-bit differential overflow")
  }
  a + b
}

///|
fn fractional_text(
  n : Int64,
  scale : Int,
  width : Int,
) -> String raise CheckError {
  if n == -9223372036854775807L - 1L {
    raise Rejected("integer-overflow", 0, "minimum integer")
  }
  let a = if n < 0L { -n } else { n }
  let mut pow = 1L
  for _ in 0..<scale {
    pow *= 10L
  }
  let frac = a % pow
  let f = frac.to_string()
  let b = StringBuilder()
  for _ in f.length()..<scale {
    b.write_string("0")
  }
  b.write_string(f)
  let whole = a / pow
  // RNXCMP omits the leading zero for abs(values)<1, except exact zero.
  let sign = if n < 0L { "-" } else { "" }
  let text = sign +
    (if whole == 0L { "" } else { whole.to_string() }) +
    "." +
    b.to_string()
  if text.length() > width {
    raise Rejected("field-overflow", 0, "restored fixed field overflow")
  }
  left_pad(text, width)
}

///|
pub(all) enum CodeMapping {
  Unknown
  Ambiguous(Array[String])
  RuleMapped(String, String)
  ExplicitOverride(String)
} derive(@debug.Debug, ToJson)

///|
/// Conservative interpretation. Receiver model is deliberately not an input.
/// Overrides are keyed "G:C1", etc., and remain caller assertions.
pub fn map_legacy_code(
  system : String,
  raw_code : String,
  overrides? : Map[String, String] = {},
) -> CodeMapping raise CheckError {
  if raw_code.length() != 2 || !["G", "R", "E", "S"].contains(system) {
    raise Rejected(
      "legacy-code", 0, "expected RINEX2.11 system and two-character code",
    )
  }
  if overrides.get(system + ":" + raw_code) is Some(code) {
    if code.length() != 3 ||
      part(code, 0, 2) != raw_code.replace(old="P", new="C") ||
      !(code[2] >= 'A' && code[2] <= 'Z') {
      raise Rejected(
        "mapping-override", 0, "target must match observable kind/band and contain a tracking letter",
      )
    }
    // Tracking-letter sets differ by constellation/band.
    let tracking = match (system, part(code, 1, 2)) {
      ("G", "1") => "CSLXPWYMN"
      ("G", "2") => "CDSLXPWYM N".replace(old=" ", new="")
      ("G", "5") => "IQX"
      ("R", "1" | "2") => "CP"
      ("E", "1" | "6") => "ABCXZ"
      ("E", "5" | "7" | "8") => "IQX"
      ("S", "1") => "C"
      ("S", "5") => "IQX"
      _ => ""
    }
    if !tracking.contains(part(code, 2, 3)) {
      raise Rejected(
        "mapping-override", 0, "tracking attribute not valid for this system/band",
      )
    }
    if code.has_prefix("C") && part(code, 2, 3) == "N" {
      raise Rejected(
        "mapping-override", 0, "codeless tracking N has no pseudorange",
      )
    }
    return ExplicitOverride(code)
  }
  match (system, raw_code) {
    ("G" | "R" | "S", "C1") =>
      RuleMapped("C1C", "IGS2.11:C1-CA/3.04-tracking-C")
    ("G", "P1") => Ambiguous(["C1P", "C1W", "C1Y"])
    ("G", "P2") => Ambiguous(["C2P", "C2W", "C2Y"])
    ("G", "L1") =>
      Ambiguous(["L1C", "L1S", "L1L", "L1X", "L1P", "L1W", "L1Y", "L1M", "L1N"])
    ("E", "C1") => Ambiguous(["C1A", "C1B", "C1C", "C1X", "C1Z"])
    _ => Unknown
  }
}

///|
pub struct LegacyValue {
  raw_code : String
  mapping : CodeMapping
  observation : ObservationValue
} derive(@debug.Debug, ToJson)

///|
pub struct LegacySatellite {
  satellite : String
  line : Int
  values : Array[LegacyValue]
} derive(@debug.Debug, ToJson)

///|
pub struct LegacyEpoch {
  gps_ticks : Int64
  flag : Int
  line : Int
  end_line : Int
  receiver_clock : Double?
  satellites : Array[LegacySatellite]
} derive(@debug.Debug, ToJson)

///|
pub struct LegacyEvent {
  flag : Int
  line : Int
  raw_record : String
  records : Array[String]
} derive(@debug.Debug, ToJson)

///|
pub(all) enum LegacyItem {
  Epoch(LegacyEpoch)
  Event(LegacyEvent)
  CycleSlip(LegacyEpoch)
} derive(@debug.Debug, ToJson)

///|
/// RINEX2.11, GPS time, including events2..5 and raw flag6 cycle-slip records.
/// One epoch is buffered; no numeric observation corrections are applied.
pub struct LegacyReader {
  priv mut closed : Bool
  priv mut line : Int
  priv mut bytes : Int
  priv mut body : Bool
  priv mut system : String
  priv mut time_system : String
  priv codes : Array[String]
  priv mut expected : Int
  priv raw_header : Array[String]
  priv overrides : Map[String, String]
  priv mut start : Int64
  priv mut flag : Int
  priv mut start_line : Int
  priv mut clock : Double?
  priv sats : Array[String]
  priv records : Array[LegacySatellite]
  priv values : Array[LegacyValue]
  priv mut sat_line : Int
  priv mut count : Int
  priv mut need_sats : Bool
  priv mut event_left : Int
  priv mut event_raw : String
  priv events : Array[String]
}

///|
pub fn LegacyReader::new(overrides? : Map[String, String] = {}) -> LegacyReader {
  {
    closed: false,
    line: 0,
    bytes: 0,
    body: false,
    system: "",
    time_system: "",
    codes: [],
    expected: 0,
    raw_header: [],
    overrides: overrides.copy(),
    start: 0L,
    flag: 0,
    start_line: 0,
    clock: None,
    sats: [],
    records: [],
    values: [],
    sat_line: 0,
    count: 0,
    need_sats: false,
    event_left: 0,
    event_raw: "",
    events: [],
  }
}

///|
pub fn LegacyReader::header(self : LegacyReader) -> Array[String] {
  self.raw_header.copy()
}

///|
fn LegacyReader::header_record(
  self : LegacyReader,
  s : String,
) -> Unit raise CheckError {
  if s.length() < 60 || s.length() > 80 {
    raise Rejected("legacy-header", 0, "invalid header width")
  }
  match trimmed(s, 60, 80) {
    "RINEX VERSION / TYPE" => {
      if trimmed(s, 0, 9) != "2.11" || part(s, 20, 21) != "O" {
        raise Rejected("legacy-version", 0, "expected RINEX2.11 OBS")
      }
      let system = trimmed(s, 40, 41)
      let system = if system.is_empty() { "G" } else { system }
      if !["G", "R", "E", "S", "M"].contains(system) {
        raise Rejected("legacy-system", 0, "unsupported system")
      }
      // The same metadata can be replaced by a flag3/4 header update.
      // Subsequent blank GPS IDs and default GPS time use the current header.
      self.system = system
    }
    "# / TYPES OF OBSERV" => {
      if !trimmed(s, 0, 6).is_empty() {
        let n = digits(part(s, 0, 6))
        if n < 1 || n > 96 {
          raise Rejected("legacy-types", 0, "type count1..96")
        }
        if self.expected > 0 && self.codes.length() != self.expected {
          raise Rejected("legacy-types", 0, "unfinished type continuation")
        }
        self.codes.clear()
        self.expected = n
      }
      if self.expected == 0 {
        raise Rejected("legacy-types", 0, "orphan continuation")
      }
      for i in 0..<9 {
        let code = trimmed(s, 6 + 6 * i, 12 + 6 * i)
        if !code.is_empty() {
          if code.length() != 2 ||
            self.codes.contains(code) ||
            self.codes.length() >= self.expected {
            raise Rejected("legacy-types", 0, "invalid/duplicate/excess type")
          }
          if !["C", "P", "L", "D", "S"].contains(part(code, 0, 1)) ||
            !["1", "2", "5", "6", "7", "8"].contains(part(code, 1, 2)) {
            raise Rejected(
              "legacy-types", 0, "unknown RINEX2.11 observation type",
            )
          }
          self.codes.push(code)
        }
      }
    }
    "TIME OF FIRST OBS" => {
      self.time_system = trimmed(s, 48, 51)
      if self.time_system.is_empty() && self.system == "G" {
        self.time_system = "GPS"
      }
      if self.time_system != "GPS" {
        raise Rejected(
          "unsupported-time-system", 0, "legacy reader requires GPS time",
        )
      }
    }
    _ => ()
  }
}

///|
fn LegacyReader::append_satellites(
  self : LegacyReader,
  s : String,
) -> Unit raise CheckError {
  for i in 0..<12 {
    let raw = part(s, 32 + i * 3, 35 + i * 3)
    if !raw.trim().is_empty() {
      if self.sats.length() >= self.count {
        raise Rejected("legacy-satellites", 0, "excess satellite ID")
      }
      let sys = if raw.has_prefix(" ") {
        if self.system != "G" {
          raise Rejected(
            "legacy-satellite", 0, "blank satellite system requires a pure GPS file",
          )
        }
        "G"
      } else {
        part(raw, 0, 1)
      }
      let prn = digits(part(raw, 1, 3))
      if !["G", "R", "E", "S"].contains(sys) || prn < 1 || prn > 99 {
        raise Rejected("legacy-satellite", 0, "invalid/ambiguous system or PRN")
      }
      let id = sys + (if prn < 10 { "0" } else { "" }) + prn.to_string()
      if self.sats.contains(id) {
        raise Rejected("legacy-satellite", 0, "duplicate satellite")
      }
      self.sats.push(id)
    }
  }
  self.need_sats = self.sats.length() < self.count
}

///|
fn LegacyReader::finished_epoch(self : LegacyReader) -> LegacyItem {
  let epoch = {
    gps_ticks: self.start,
    flag: self.flag,
    line: self.start_line,
    end_line: self.line,
    receiver_clock: self.clock,
    satellites: self.records.copy(),
  }
  self.count = 0
  if self.flag == 6 {
    CycleSlip(epoch)
  } else {
    Epoch(epoch)
  }
}

///|
fn LegacyReader::consume(
  self : LegacyReader,
  s : String,
) -> LegacyItem? raise CheckError {
  if self.closed {
    raise Rejected("state", 0, "legacy reader failed or finished")
  }
  self.line += 1
  ascii_line(s)
  if self.bytes > 536870912 - s.length() - 1 {
    raise Rejected("capacity", 0, "input512MiB limit")
  }
  self.bytes += s.length() + 1
  if !self.body {
    if self.line > 4096 {
      raise Rejected("capacity", 0, "header4096line limit")
    }
    if self.line == 1 && trimmed(s, 60, 80) != "RINEX VERSION / TYPE" {
      raise Rejected("legacy-version", 0, "expected RINEX2.11 OBS")
    }
    self.raw_header.push(s)
    self.header_record(s)
    if trimmed(s, 60, 80) == "END OF HEADER" {
      if self.expected == 0 ||
        self.codes.length() != self.expected ||
        self.time_system != "GPS" {
        raise Rejected(
          "legacy-header", 0, "missing/incomplete types or GPS time",
        )
      }
      self.body = true
    }
    return None
  }
  if self.event_left > 0 {
    self.events.push(s)
    if self.flag == 3 || self.flag == 4 {
      self.header_record(s)
    }
    self.event_left -= 1
    if self.event_left == 0 {
      if self.codes.length() != self.expected {
        raise Rejected("legacy-types", 0, "incomplete updated types")
      }
      return Some(
        Event({
          flag: self.flag,
          line: self.start_line,
          raw_record: self.event_raw,
          records: self.events.copy(),
        }),
      )
    }
    return None
  }
  if self.need_sats {
    if !trimmed(s, 0, 32).is_empty() {
      raise Rejected(
        "legacy-continuation", 0, "SV continuation prefix must be blank",
      )
    }
    self.append_satellites(s)
    return None
  }
  if self.count > 0 {
    if s.length() > 80 {
      raise Rejected("legacy-observation-width", 0, "at most5fields/line")
    }
    if self.values.is_empty() {
      self.sat_line = self.line
    }
    let slots = (self.expected - self.values.length()).min(5)
    for i in 0..<slots {
      let index = self.values.length()
      let raw = part(s, i * 16, i * 16 + 16)
      let number = trimmed(raw, 0, 14)
      let lli_text = part(raw, 14, 15)
      let ssi_text = part(raw, 15, 16)
      let lli = if lli_text.trim().is_empty() {
        None
      } else {
        Some(digits(lli_text))
      }
      let ssi = if ssi_text.trim().is_empty() {
        None
      } else {
        Some(digits(ssi_text))
      }
      if lli is Some(x) && x > 7 {
        raise Rejected("lli", 0, "LLI0..7")
      }
      if ssi is Some(x) && x > 9 {
        raise Rejected("ssi", 0, "SSI0..9")
      }
      let raw_code = self.codes[index]
      let sys = part(self.sats[self.records.length()], 0, 1)
      self.values.push({
        raw_code,
        mapping: map_legacy_code(sys, raw_code, overrides=self.overrides),
        observation: {
          code: raw_code,
          column: i * 16 + 1,
          raw_field: raw,
          value: if number.is_empty() {
            None
          } else {
            Some(decimal(number))
          },
          lli,
          ssi,
        },
      })
    }
    if !trimmed(s, slots * 16, 80).is_empty() {
      raise Rejected(
        "legacy-extra-fields", 0, "extra fields beyond declaration",
      )
    }
    if self.values.length() == self.expected {
      self.records.push({
        satellite: self.sats[self.records.length()],
        line: self.sat_line,
        values: self.values.copy(),
      })
      self.values.clear()
      if self.records.length() == self.count {
        return Some(self.finished_epoch())
      }
    }
    return None
  }
  if s.length() < 32 || s.length() > 80 {
    raise Rejected("legacy-epoch", 0, "invalid epoch width")
  }
  self.start_line = self.line
  self.flag = digits(part(s, 28, 29))
  self.count = digits(part(s, 29, 32))
  if self.flag > 6 || ((self.flag <= 1 || self.flag == 6) && self.count > 693) {
    raise Rejected("legacy-epoch", 0, "flag/count out of range")
  }
  self.events.clear()
  if self.flag >= 2 && self.flag <= 5 {
    if self.count > 4096 {
      raise Rejected("capacity", 0, "event records limit")
    }
    self.event_left = self.count
    self.count = 0
    self.event_raw = s
    if self.event_left == 0 {
      return Some(
        Event({
          flag: self.flag,
          line: self.start_line,
          raw_record: s,
          records: [],
        }),
      )
    }
    return None
  }
  let yy = digits(part(s, 1, 3))
  let year = if yy < 80 { 2000 + yy } else { 1900 + yy }
  self.start = timestamp(
    year.to_string(),
    part(s, 4, 6),
    part(s, 7, 9),
    part(s, 10, 12),
    part(s, 13, 15),
    part(s, 15, 26),
  )
  self.clock = if trimmed(s, 68, 80).is_empty() {
    None
  } else {
    Some(decimal(part(s, 68, 80)))
  }
  self.sats.clear()
  self.records.clear()
  self.values.clear()
  self.append_satellites(s)
  if self.count == 0 {
    return Some(self.finished_epoch())
  }
  None
}

///|
pub fn LegacyReader::feed_line(
  self : LegacyReader,
  s : String,
) -> LegacyItem? raise CheckError {
  self.consume(s) catch {
    Rejected(code, at, detail) => {
      self.closed = true
      raise Rejected(code, if at == 0 { self.line } else { at }, detail)
    }
  }
}

///|
pub fn LegacyReader::finish(self : LegacyReader) -> Unit raise CheckError {
  if self.closed {
    raise Rejected("state", self.line, "legacy reader failed or finished")
  }
  self.closed = true
  if !self.body || self.count != 0 || self.need_sats || self.event_left != 0 {
    raise Rejected(
      "truncated",
      self.line,
      "incomplete legacy header/epoch/event",
    )
  }
}
