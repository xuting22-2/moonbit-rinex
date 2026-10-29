///|
pub suberror NavError {
  InvalidNavigation(String)
  UnsupportedConstellation(String)
  EphemerisExpired
  UnhealthyEphemeris
  OrbitTypeRequired
  KeplerDivergence
} derive(@debug.Debug)

///|
/// Existing GPS calendar 100ns ticks since1980-01-01, not UTC or GPS-week zero.
pub struct NavTime {
  gps_ticks : Int64
} derive(@debug.Debug, ToJson)

///|
pub fn NavTime::offset_seconds(
  self : NavTime,
  seconds : Int,
) -> NavTime raise NavError {
  if seconds < -604800 || seconds > 604800 {
    raise InvalidNavigation("offset bounded to one week")
  }
  { gps_ticks: self.gps_ticks + seconds.to_int64() * 10000000L, }
}

///|
pub fn NavTime::calendar(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : String,
  bdt? : Bool = false,
) -> NavTime raise CheckError {
  let t = timestamp(
    year.to_string(),
    month.to_string(),
    day.to_string(),
    hour.to_string(),
    minute.to_string(),
    second,
  )
  { gps_ticks: t + (if bdt { 140000000L } else { 0L }), }
}

///|
/// Continuous week, not a broadcast truncated week. No wall-clock guesses.
pub fn NavTime::week(
  week : Int,
  sow : Double,
  bdt? : Bool = false,
) -> NavTime raise NavError {
  if week < 0 ||
    week > 7000 ||
    sow.is_nan() ||
    sow.is_inf() ||
    sow < 0.0 ||
    sow >= 604800.0 {
    raise InvalidNavigation("continuous week/sow out of range")
  }
  let origin = if bdt {
    (try! day_ticks(2006, 1, 1)) + 140000000L
  } else {
    4320000000000L
  }
  {
    gps_ticks: origin +
    week.to_int64() * 6048000000000L +
    @math.round(sow * 10000000.0).to_int64(),
  }
}

///|
pub(all) enum BdsOrbit {
  MEO_IGSO
  GEO
} derive(@debug.Debug, ToJson)

///|
pub struct SatPosition {
  x : Double
  y : Double
  z : Double
  clock_seconds : Double
  group_delay_seconds : Double
  frame : String
  iterations : Int
} derive(@debug.Debug, ToJson)

///|
/// Broadcast parameters, not RF message decoding. Data array follows the seven
/// RINEX3 broadcast orbit lines. Clock includes relativity, excludes TGD.
pub struct NavRecord {
  satellite : String
  message : String
  toc : NavTime
  toe : NavTime
  toe_sow : Double
  health : Int
  priv clock : Array[Double]
  priv data : Array[Double?]
}

///|
fn nav_required(data : Array[Double?], index : Int) -> Double raise NavError {
  match data.get(index) {
    Some(Some(x)) => x
    _ =>
      raise InvalidNavigation(
        "missing required broadcast field" + index.to_string(),
      )
  }
}

///|
fn nav_float(s : String) -> Double raise NavError {
  decimal(s) catch {
    _ => raise InvalidNavigation("invalid finite navigation number")
  }
}

///|
fn nav_int(x : Double) -> Int raise NavError {
  if x < 0.0 || x > 10000000.0 || @math.floor(x) != x {
    raise InvalidNavigation("expected bounded nonnegative integer field")
  }
  x.to_int()
}

///|
/// Evaluate at transmission/orbit time. No light-time or Sagnac positioning.
/// Caller can tighten max_age_seconds, never extend the documented4h bound.
pub fn NavRecord::satellite_position(
  self : NavRecord,
  time : NavTime,
  bds_orbit? : BdsOrbit,
  max_age_seconds? : Double = 7200.0,
) -> SatPosition raise NavError {
  if max_age_seconds <= 0.0 ||
    max_age_seconds > 14400.0 ||
    max_age_seconds.is_nan() ||
    max_age_seconds.is_inf() {
    raise InvalidNavigation("max age must be finite in(0,14400]")
  }
  let tk = (time.gps_ticks - self.toe.gps_ticks).to_double() / 10000000.0
  let tc = (time.gps_ticks - self.toc.gps_ticks).to_double() / 10000000.0
  if tk.abs() > max_age_seconds || tc.abs() > max_age_seconds {
    raise EphemerisExpired
  }
  if self.health != 0 {
    raise UnhealthyEphemeris
  }
  let bds = self.satellite.has_prefix("C")
  if !bds && !self.satellite.has_prefix("G") {
    raise UnsupportedConstellation(self.satellite)
  }
  let fit_limit = if bds {
    7200.0
  } else {
    match self.data.get(25) {
      Some(Some(hours)) if hours > 0.0 => (hours * 1800.0).min(14400.0)
      _ => 7200.0
    }
  }
  if tk.abs() > fit_limit || tc.abs() > fit_limit {
    raise EphemerisExpired
  }
  let geo = if bds {
    match bds_orbit {
      Some(GEO) => true
      Some(MEO_IGSO) => false
      None => {
        let prn = nav_int(nav_float(part(self.satellite, 1, 3)))
        if prn <= 5 {
          true
        } else {
          raise OrbitTypeRequired
        }
      }
    }
  } else {
    false
  }
  let mu = if bds { 3.986004418e14 } else { 3.986005e14 }
  let omge = if bds { 7.292115e-5 } else { 7.2921151467e-5 }
  let sqrt_a = nav_required(self.data, 7)
  let a = sqrt_a * sqrt_a
  let e = nav_required(self.data, 5)
  if sqrt_a <= 0.0 || a < 1.0 || a.is_inf() || e < 0.0 || e >= 1.0 {
    raise InvalidNavigation("invalid semimajor axis/eccentricity")
  }
  let m_full = nav_required(self.data, 3) +
    ((mu / (a * a * a)).sqrt() + nav_required(self.data, 2)) * tk
  let m = m_full -
    @math.floor((m_full + @math.PI) / (2.0 * @math.PI)) * (2.0 * @math.PI)
  let mut eccentric = m
  let mut iterations = 0
  let mut converged = false
  for n in 0..<15 {
    let delta = (eccentric - e * @math.sin(eccentric) - m) /
      (1.0 - e * @math.cos(eccentric))
    eccentric -= delta
    iterations = n + 1
    if iterations >= 3 && delta.abs() <= 1.0e-12 {
      converged = true
      break
    }
  }
  if !converged || eccentric.is_nan() || eccentric.is_inf() {
    raise KeplerDivergence
  }
  let se = @math.sin(eccentric)
  let ce = @math.cos(eccentric)
  let phi = @math.atan2((1.0 - e * e).sqrt() * se, ce - e) +
    nav_required(self.data, 14)
  let sin2 = @math.sin(2.0 * phi)
  let cos2 = @math.cos(2.0 * phi)
  let u = phi +
    nav_required(self.data, 6) * sin2 +
    nav_required(self.data, 4) * cos2
  let radius = a * (1.0 - e * ce) +
    nav_required(self.data, 1) * sin2 +
    nav_required(self.data, 13) * cos2
  let incl = nav_required(self.data, 12) +
    nav_required(self.data, 16) * tk +
    nav_required(self.data, 11) * sin2 +
    nav_required(self.data, 9) * cos2
  let x = radius * @math.cos(u)
  let y = radius * @math.sin(u)
  let node = nav_required(self.data, 10) +
    (nav_required(self.data, 15) - (if geo { 0.0 } else { omge })) * tk -
    omge * self.toe_sow
  let xg = x * @math.cos(node) - y * @math.cos(incl) * @math.sin(node)
  let yg = x * @math.sin(node) + y * @math.cos(incl) * @math.cos(node)
  let zg = y * @math.sin(incl)
  let (ox, oy, oz) = if geo {
    let tilt = -5.0 * @math.PI / 180.0
    let s = @math.sin(omge * tk)
    let c = @math.cos(omge * tk)
    let st = @math.sin(tilt)
    let ct = @math.cos(tilt)
    (
      xg * c + yg * s * ct + zg * s * st,
      -xg * s + yg * c * ct + zg * c * st,
      -yg * st + zg * ct,
    )
  } else {
    (xg, yg, zg)
  }
  let rel = -2.0 * mu.sqrt() / (299792458.0 * 299792458.0) * e * sqrt_a * se
  let clk = self.clock[0] + self.clock[1] * tc + self.clock[2] * tc * tc + rel
  if ox.is_nan() ||
    ox.is_inf() ||
    oy.is_nan() ||
    oy.is_inf() ||
    oz.is_nan() ||
    oz.is_inf() ||
    clk.is_nan() ||
    clk.is_inf() {
    raise InvalidNavigation("nonfinite propagated state")
  }
  {
    x: ox,
    y: oy,
    z: oz,
    clock_seconds: clk,
    group_delay_seconds: nav_required(self.data, 22),
    frame: if bds {
      "CGCS2000"
    } else {
      "WGS84"
    },
    iterations,
  }
}

///|
/// Original text for the record emitted by the most recent feed_line call.
/// Line numbers are one-based physical input lines; separators are not stored.
pub struct NavRecordSource {
  first_line : Int
  last_line : Int
  raw_lines : Array[String]
} derive(@debug.Debug, ToJson)

///|
pub extend NavRecordSource with @debug.Debug::{to_repr}

///|
pub extend NavRecordSource with ToJson::{to_json}

///|
/// RINEX2.11 GPS or3.03/3.04/3.05 GPS/BDS NAV. By default rejects unsupported
/// constellations. Explicit skip_unsupported consumes known record sizes only.
pub struct NavReader {
  priv mut line : Int
  priv mut bytes : Int
  priv mut closed : Bool
  priv mut body : Bool
  priv mut version2 : Bool
  priv mut glo_lines : Int
  priv pending : Array[String]
  priv skip_unsupported : Bool
  priv mut skip_left : Int
  priv mut skipped : Int
  priv capture_source : Bool
  priv source_header : Array[String]
  priv mut last_source : NavRecordSource?
}

///|
pub fn NavReader::new(
  skip_unsupported? : Bool = false,
  capture_source? : Bool = false,
) -> NavReader {
  {
    line: 0,
    bytes: 0,
    closed: false,
    body: false,
    version2: false,
    glo_lines: 4,
    pending: [],
    skip_unsupported,
    skip_left: 0,
    skipped: 0,
    capture_source,
    source_header: [],
    last_source: None,
  }
}

///|
/// A copied header snapshot, empty unless capture_source=true. Provisional
/// until finish succeeds; includes END OF HEADER and every original header line.
pub fn NavReader::header_lines(self : NavReader) -> Array[String] {
  [
    for line in self.source_header => line
  ]
}

///|
/// A copied snapshot only when the most recent feed_line emitted a record and
/// capture_source=true. A later feed clears it; finish leaves it available.
/// This does not certify the rest of the input: finish is still required.
pub fn NavReader::last_record_source(self : NavReader) -> NavRecordSource? {
  self.last_source.map(source => {
    first_line: source.first_line,
    last_line: source.last_line,
    raw_lines: [
      for line in source.raw_lines => line
    ],
  })
}

///|
pub fn NavReader::skipped_records(self : NavReader) -> Int {
  self.skipped
}

///|
fn NavReader::parse_record(self : NavReader) -> NavRecord raise NavError {
  let first = self.pending[0]
  let sat = if self.version2 {
    let prn = nav_int(nav_float(part(first, 0, 2)))
    if prn < 1 || prn > 32 {
      raise InvalidNavigation("GPS PRN1..32")
    }
    "G" + (if prn < 10 { "0" } else { "" }) + prn.to_string()
  } else {
    part(first, 0, 3)
  }
  let bds = sat.has_prefix("C")
  let t = if self.version2 {
    let yy = nav_int(nav_float(part(first, 3, 5)))
    let year = if yy < 80 { yy + 2000 } else { yy + 1900 }
    timestamp(
      year.to_string(),
      part(first, 6, 8),
      part(first, 9, 11),
      part(first, 12, 14),
      part(first, 15, 17),
      part(first, 18, 22),
    ) catch {
      _ => raise InvalidNavigation("invalid NAV2 calendar")
    }
  } else {
    if !satellite_ok(sat) {
      raise InvalidNavigation("invalid satellite")
    }
    timestamp(
      part(first, 4, 8),
      part(first, 9, 11),
      part(first, 12, 14),
      part(first, 15, 17),
      part(first, 18, 20),
      part(first, 21, 23),
    ) catch {
      _ => raise InvalidNavigation("invalid NAV3 calendar")
    }
  }
  let offset = if self.version2 { 22 } else { 23 }
  let clock = [
    for i in 0..<3 => {
      nav_float(part(first, offset + 19 * i, offset + 19 * (i + 1)))
    }
  ]
  let data : Array[Double?] = []
  for row in 1..<8 {
    let s = self.pending[row]
    let begin = if self.version2 { 3 } else { 4 }
    if !trimmed(s, 0, begin).is_empty() {
      raise InvalidNavigation("continuation prefix must be blank")
    }
    for i in 0..<4 {
      let raw = trimmed(s, begin + 19 * i, begin + 19 * (i + 1))
      data.push(if raw.is_empty() { None } else { Some(nav_float(raw)) })
    }
    if !trimmed(s, begin + 76, s.length()).is_empty() {
      raise InvalidNavigation("extra continuation columns")
    }
  }
  for
    i in [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 21, 22,
    ] {
    ignore(nav_required(data, i))
  }
  let week = nav_int(nav_required(data, 18))
  let toe_sow = nav_required(data, 8)
  let toe = NavTime::week(week, toe_sow, bdt=bds)
  let toc : NavTime = { gps_ticks: t + (if bds { 140000000L } else { 0L }), }
  // Continuous RINEX week must identify the same nearby ephemeris as toc.
  if ((toc.gps_ticks - toe.gps_ticks).to_double() / 10000000.0).abs() > 604800.0 {
    raise InvalidNavigation("inconsistent continuous week and toc")
  }
  {
    satellite: sat,
    message: if bds {
      "B1I-D1/D2"
    } else {
      "LNAV"
    },
    toc,
    toe,
    toe_sow,
    health: nav_int(nav_required(data, 21)),
    clock,
    data,
  }
}

///|
pub fn NavReader::feed_line(
  self : NavReader,
  s : String,
) -> NavRecord? raise NavError {
  if self.closed {
    raise InvalidNavigation("reader failed or finished")
  }
  self.last_source = None
  self.line += 1
  errdefer {
    self.closed = true
  }
  ascii_line(s) catch {
    _ => raise InvalidNavigation("invalid ASCII/line capacity")
  }
  if self.bytes > 536870912 - s.length() - 1 {
    raise InvalidNavigation("input512MiB limit")
  }
  self.bytes += s.length() + 1
  if !self.body {
    if self.line > 4096 || s.length() < 60 || s.length() > 80 {
      raise InvalidNavigation("header limit/width")
    }
    if self.line == 1 {
      let version = trimmed(s, 0, 9)
      self.glo_lines = if version == "3.05" { 5 } else { 4 }
      self.version2 = version == "2.11"
      if (!self.version2 && !["3.03", "3.04", "3.05"].contains(version)) ||
        part(s, 20, 21) != "N" ||
        trimmed(s, 60, 80) != "RINEX VERSION / TYPE" {
        raise InvalidNavigation(
          "supported NAV2.11GPS or3.03/3.04/3.05GPS/BDS only",
        )
      }
    }
    if trimmed(s, 60, 80) == "END OF HEADER" {
      self.body = true
    }
    if self.capture_source {
      self.source_header.push(s)
    }
    return None
  }
  if self.skip_left > 0 {
    self.skip_left -= 1
    return None
  }
  if s.length() > 80 {
    raise InvalidNavigation("NAV record wider than80")
  }
  if self.pending.is_empty() && !self.version2 {
    let sys = part(s, 0, 1)
    if !["G", "C"].contains(sys) {
      if !self.skip_unsupported || !["R", "S", "E", "J", "I"].contains(sys) {
        raise UnsupportedConstellation(sys)
      }
      self.skip_left = match sys {
        "R" => self.glo_lines - 1
        "S" => 3
        _ => 7
      }
      self.skipped += 1
      return None
    }
  }
  self.pending.push(s)
  if self.pending.length() == 8 {
    let record = self.parse_record()
    if self.capture_source {
      self.last_source = Some({
        first_line: self.line - 7,
        last_line: self.line,
        raw_lines: [
          for line in self.pending => line
        ],
      })
    }
    self.pending.clear()
    return Some(record)
  }
  None
}

///|
pub fn NavReader::finish(self : NavReader) -> Unit raise NavError {
  if self.closed {
    raise InvalidNavigation("reader failed or finished")
  }
  self.closed = true
  if !self.body || !self.pending.is_empty() || self.skip_left != 0 {
    raise InvalidNavigation("truncated navigation header/record")
  }
}
