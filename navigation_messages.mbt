///|
/// A calendar coordinate in the named time scale. calendar_ticks uses the
/// existing 1980-01-01/100ns origin, NOT a UTC-to-GPST conversion. Leap seconds
/// retain their spelling and flag; consumers supply elapsed SI seconds.
pub struct NavigationEpoch {
  calendar : String
  scale : String
  calendar_ticks : Int64
  leap_second : Bool
} derive(@debug.Debug, ToJson)

///|
pub extend NavigationEpoch with @debug.Debug::{to_repr}

///|
pub extend NavigationEpoch with ToJson::{to_json}

///|
pub struct NavigationField {
  name : String
  unit : String
  row : Int
  column : Int
  raw : String
  value : Double?
  availability : String
} derive(@debug.Debug, ToJson)

///|
pub extend NavigationField with @debug.Debug::{to_repr}

///|
pub extend NavigationField with ToJson::{to_json}

///|
/// Complete record, including descriptor, spare/blank fields and source span.
/// known=false is an opaque preserved record, never an all-supported success.
pub struct NavigationMessage {
  version : String
  category : String
  system : String
  satellite : String
  family : String
  subtype : String
  model : String
  known : Bool
  epoch : NavigationEpoch?
  first_line : Int
  last_line : Int
  priv fields : Array[NavigationField]
  priv texts : Map[String, String]
  priv raw : Array[String]
}

///|
pub fn NavigationMessage::to_json(self : NavigationMessage) -> Json {
  {
    "version": self.version.to_json(),
    "category": self.category.to_json(),
    "system": self.system.to_json(),
    "satellite": self.satellite.to_json(),
    "family": self.family.to_json(),
    "subtype": self.subtype.to_json(),
    "model": self.model.to_json(),
    "known": self.known.to_json(),
    "diagnostic": if self.known {
      Json::null()
    } else {
      "Unrecognized navigation category/system/family/subtype; raw record retained, all-supported qualification denied".to_json()
    },
    "epoch": match self.epoch {
      Some(t) => t.to_json()
      None => Json::null()
    },
    "first_line": self.first_line.to_json(),
    "last_line": self.last_line.to_json(),
    "fields": self.fields.to_json(),
    "texts": self.texts.to_json(),
    "raw_lines": self.raw.to_json(),
  }
}

///|
pub fn NavigationMessage::parameters(
  self : NavigationMessage,
) -> Array[NavigationField] {
  [
    for f in self.fields => f
  ]
}

///|
pub fn NavigationMessage::raw_lines(self : NavigationMessage) -> Array[String] {
  [
    for s in self.raw => s
  ]
}

///|
pub fn NavigationMessage::text(
  self : NavigationMessage,
  name : String,
) -> String? {
  self.texts.get(name)
}

///|
pub fn NavigationMessage::value(
  self : NavigationMessage,
  name : String,
) -> Double? {
  for f in self.fields {
    if f.name == name {
      return f.value
    }
  }
  None
}

///|
fn NavigationMessage::required(
  self : NavigationMessage,
  name : String,
) -> Double raise NavError {
  match self.value(name) {
    Some(v) => v
    None => raise InvalidNavigation("missing navigation parameter: " + name)
  }
}

///|
fn navigation_scale(system : String) -> String {
  match system {
    "R" => "UTC"
    "E" => "GST"
    "C" => "BDT"
    "J" => "QZSST"
    "I" => "IRNSST"
    "G" | "S" => "GPST"
    _ => "unknown"
  }
}

///|
fn navigation_epoch(
  s : String,
  scale : String,
) -> NavigationEpoch raise NavError {
  let second = trimmed(s, 21, 23)
  let leap = second == "60"
  if leap && (scale != "UTC" || part(s, 15, 20) != "23 59") {
    raise InvalidNavigation("leap second requires UTC 23:59:60")
  }
  let ticks = timestamp(
    part(s, 4, 8),
    part(s, 9, 11),
    part(s, 12, 14),
    part(s, 15, 17),
    part(s, 18, 20),
    if leap {
      "59"
    } else {
      second
    },
  ) catch {
    _ => raise InvalidNavigation("invalid navigation epoch")
  }
  {
    calendar: part(s, 4, 23),
    scale,
    calendar_ticks: ticks + (if leap { 10000000L } else { 0L }),
    leap_second: leap,
  }
}

///|
fn navigation_key(
  category : String,
  sys : String,
  family : String,
  subtype : String,
) -> String {
  match category {
    "EPH" =>
      match (sys, family) {
        ("G" | "J", "LNAV") => "gps_lnav"
        ("G" | "J", "CNAV") => "cnav"
        ("G" | "J", "CNV2") => "cnv2"
        ("E", "INAV" | "FNAV" | "IFNV") => "galileo"
        ("R", "FDMA") => "glo_fdma"
        ("R", "L1OC" | "L3OC") => "glo_cdma"
        ("C", "D1" | "D2" | "D1D2") => "bds_legacy"
        ("C", "CNV1") => "bds_cnv1"
        ("C", "CNV2") => "bds_cnv2"
        ("C", "CNV3") => "bds_cnv3"
        ("S", "SBAS") => "sbas"
        ("I", "LNAV") => "navic_lnav"
        ("I", "L1NV") => "navic_l1nv"
        _ => ""
      }
    "STO" =>
      match (sys, family) {
        ("G" | "J", "LNAV" | "CNVX")
        | ("R", "FDMA" | "LXOC")
        | ("E", "IFNV")
        | ("C", "D1D2" | "CNVX")
        | ("I", "LNAV" | "L1NV")
        | ("S", "SBAS") => "sto"
        _ => ""
      }
    "EOP" =>
      match (sys, family) {
        ("G" | "C" | "J", "CNVX") | ("I", "LNAV" | "L1NV") | ("R", "LXOC") =>
          "eop"
        _ => ""
      }
    "ION" =>
      match (sys, family, subtype) {
        ("E", "IFNV", "") => "nequick_g"
        ("C", "CNVX", "") => "bdgim"
        ("R", "LXOC", "") => "glo_ion"
        ("I", "L1NV", "KLOB") => "navic_klob"
        ("I", "L1NV", "NEQN") => "navic_neqn"
        ("J", "LNAV" | "CNVX", "WIDE" | "JAPN") => "klobuchar"
        ("J", "LNAV", "") => "klobuchar"
        ("G", "LNAV" | "CNVX", "") | ("I", "LNAV", "") => "klobuchar"
        ("C", "D1D2", "") => "klobuchar"
        _ => ""
      }
    _ => ""
  }
}

///|
/// RINEX3.00-3.05 and4.00-4.02 navigation, not observation parsing.
/// Native framing, field interpretation and limits. Retains unknown R4 records
/// through the next descriptor/EOF; caller MUST check unsupported_records().
pub struct NavigationReader {
  priv mut version : String
  priv mut header_system : String
  priv mut line : Int
  priv mut bytes : Int
  priv mut body : Bool
  priv mut closed : Bool
  priv mut first_line : Int
  priv mut category : String
  priv mut satellite : String
  priv mut family : String
  priv mut subtype : String
  priv mut key : String
  priv mut expected : Int
  priv mut records : Int
  priv mut unsupported : Int
  priv header : Array[String]
  priv pending : Array[String]
}

///|
pub fn NavigationReader::new() -> NavigationReader {
  {
    version: "",
    header_system: "",
    line: 0,
    bytes: 0,
    body: false,
    closed: false,
    first_line: 0,
    category: "",
    satellite: "",
    family: "",
    subtype: "",
    key: "",
    expected: 0,
    records: 0,
    unsupported: 0,
    header: [],
    pending: [],
  }
}

///|
pub fn NavigationReader::header_lines(self : NavigationReader) -> Array[String] {
  [
    for s in self.header => s
  ]
}

///|
pub fn NavigationReader::record_count(self : NavigationReader) -> Int {
  self.records
}

///|
pub fn NavigationReader::unsupported_records(self : NavigationReader) -> Int {
  self.unsupported
}

///|
fn NavigationReader::layout(self : NavigationReader) -> Array[String] {
  let fields = navigation_layout(self.key)
  if self.key == "glo_cdma" {
    fields[14] = if self.family == "L1OC" {
      "tgd_l2ocp|s"
    } else {
      "isc_l3ocp|s"
    }
  }
  if self.version == "4.00" || self.version == "4.01" {
    if self.key == "cnav" {
      fields[33] = "spare|"
    }
    if self.key == "cnv2" {
      fields[37] = "spare|"
    }
  }
  if self.key == "glo_fdma" &&
    !self.version.has_prefix("4") &&
    self.version != "3.05" {
    fields[:15].to_owned()
  } else {
    fields
  }
}

///|
fn NavigationReader::descriptor(
  self : NavigationReader,
  s : String,
) -> Unit raise NavError {
  if part(s, 0, 2) != "> " ||
    part(s, 5, 6) != " " ||
    part(s, 9, 10) != " " ||
    (s.length() > 14 && part(s, 14, 15) != " ") ||
    !trimmed(s, 19, s.length()).is_empty() {
    raise InvalidNavigation("malformed RINEX4 descriptor")
  }
  self.category = trimmed(s, 2, 5)
  self.satellite = trimmed(s, 6, 9)
  self.family = trimmed(s, 10, 14)
  self.subtype = trimmed(s, 15, 19)
  if self.category.length() != 3 ||
    self.family.is_empty() ||
    (
      !satellite_ok(self.satellite) &&
      !(self.satellite.length() == 1 && system_ok(self.satellite))
    ) ||
    (self.category == "EPH" && !satellite_ok(self.satellite)) {
    raise InvalidNavigation("invalid descriptor category/source/family")
  }
  let sys = part(self.satellite, 0, 1)
  if self.header_system != "M" && self.header_system != sys {
    raise InvalidNavigation("header/record constellation mismatch")
  }
  self.key = navigation_key(self.category, sys, self.family, self.subtype)
  if self.category == "EPH" && ["IFNV", "D1D2"].contains(self.family) {
    self.key = ""
  }
  if self.version != "4.02" &&
    (
      self.family == "L1NV" ||
      self.family == "LXOC" ||
      self.key == "glo_cdma" ||
      !self.subtype.is_empty()
    ) {
    self.key = ""
  }
  if self.version != "4.02" &&
    self.category == "ION" &&
    sys == "J" &&
    self.subtype.is_empty() &&
    ["LNAV", "CNVX"].contains(self.family) {
    self.key = "klobuchar"
  }
  // Unknown subtypes remain opaque, rather than silently losing their meaning.
  if self.category != "ION" && !self.subtype.is_empty() {
    self.key = ""
  }
  self.expected = if self.key == "" {
    -1
  } else if self.key == "sto" {
    2
  } else {
    1 + (self.layout().length() - 3) / 4
  }
  self.first_line = self.line
  self.pending.push(s)
}

///|
fn NavigationReader::emit(
  self : NavigationReader,
) -> NavigationMessage raise NavError {
  let r4 = self.version.has_prefix("4")
  let offset = if r4 { 1 } else { 0 }
  let known = self.key != ""
  let sys = part(self.satellite, 0, 1)
  let fields : Array[NavigationField] = []
  let texts : Map[String, String] = Map([])
  let mut epoch = None
  if known {
    let first = self.pending[offset]
    if self.category == "EPH" {
      if part(first, 0, 3) != self.satellite || part(first, 3, 4) != " " {
        raise InvalidNavigation("EPH descriptor/payload satellite mismatch")
      }
    } else if !trimmed(first, 0, 4).is_empty() {
      raise InvalidNavigation("non-EPH epoch prefix must be blank")
    }
    let mut scale = navigation_scale(sys)
    if self.key == "sto" {
      let codes = trimmed(first, 23, 42)
      if codes.length() != 4 ||
        !["GP", "GL", "GA", "BD", "QZ", "IR", "SB", "UT"].contains(
          part(codes, 0, 2),
        ) ||
        !["GP", "GL", "GA", "BD", "QZ", "IR", "SB", "UT"].contains(
          part(codes, 2, 4),
        ) {
        raise InvalidNavigation("invalid STO time-system pair")
      }
      texts["correction_type"] = codes
      texts["sbas_id"] = trimmed(first, 42, 61)
      texts["utc_id"] = trimmed(first, 61, 80)
      // t_ot belongs to the source time scale of the correction, not necessarily
      // the constellation broadcasting it (e.g. Galileo may broadcast GAGP).
      scale = match part(codes, 0, 2) {
        "GP" | "SB" => "GPST"
        "GL" | "UT" => "UTC"
        "GA" => "GST"
        "BD" => "BDT"
        "QZ" => "QZSST"
        _ => "IRNSST"
      }
    }
    epoch = Some(navigation_epoch(first, scale))
    let layout = self.layout()
    let mut index = 0
    for row in 0..<(self.pending.length() - offset) {
      let s = self.pending[offset + row]
      if row == 0 && self.key == "sto" {
        continue
      }
      let begin = if row == 0 { 23 } else { 4 }
      if row > 0 && !trimmed(s, 0, 4).is_empty() {
        raise InvalidNavigation("nonblank continuation prefix")
      }
      let width = if row == 0 { 3 } else { 4 }
      for column in 0..<width {
        let spec = layout[index].split("|").map(s => s.to_owned()).collect()
        let name = if spec[0] == "spare" {
          "spare_" + index.to_string()
        } else {
          spec[0]
        }
        let raw = part(s, begin + column * 19, begin + (column + 1) * 19)
        let v = trimmed(raw, 0, raw.length())
        let value = if v.is_empty() || spec[0] == "spare" {
          None
        } else {
          Some(nav_float(v))
        }
        if ["integer", "bits", "week"].contains(spec[1]) && value is Some(n) {
          if n.abs() > 1000000000.0 ||
            @math.floor(n) != n ||
            (spec[1] != "integer" && n < 0.0) {
            raise InvalidNavigation("invalid integer navigation field: " + name)
          }
        }
        let availability = if spec[0] == "spare" {
          "spare"
        } else if v.is_empty() {
          "blank"
        } else {
          match value {
            Some(n) if (
                (
                  name == "transmission_time" ||
                  name == "frame_time" ||
                  name == "delta_tau"
                ) &&
                (n == 999999999.999 || n == 1000000000.0)
              ) ||
              (name == "sisa" && n == -1.0) ||
              (self.key == "glo_fdma" && name == "urai" && n == 15.0) =>
              "unknown"
            _ => "present"
          }
        }
        fields.push({
          name,
          unit: spec[1],
          row,
          column,
          raw,
          value,
          availability,
        })
        index += 1
      }
    }
    if self.key == "galileo" && !r4 {
      let sources = nav_int(
        match fields[20].value {
          Some(x) => x
          None => raise InvalidNavigation("Galileo data sources required")
        },
      )
      self.family = if (sources & 2) != 0 && (sources & 5) == 0 {
        "FNAV"
      } else if (sources & 5) != 0 && (sources & 2) == 0 {
        "INAV"
      } else {
        "IFNV"
      }
    }
  } else {
    self.unsupported += 1
  }
  let message = {
    version: self.version,
    category: self.category,
    system: sys,
    satellite: self.satellite,
    family: self.family,
    subtype: self.subtype,
    model: self.key,
    known,
    epoch,
    first_line: self.first_line,
    last_line: self.first_line + self.pending.length() - 1,
    fields,
    texts,
    raw: [
      for s in self.pending => s
    ],
  }
  self.pending.clear()
  self.records += 1
  message
}

///|
pub fn NavigationReader::feed_line(
  self : NavigationReader,
  s : String,
) -> NavigationMessage? raise NavError {
  if self.closed {
    raise InvalidNavigation("navigation reader failed or finished")
  }
  errdefer {
    self.closed = true
  }
  self.line += 1
  ascii_line(s) catch {
    _ => raise InvalidNavigation("invalid ASCII/line capacity")
  }
  if s.length() > 80 || self.bytes > 536870912 - s.length() - 1 {
    raise InvalidNavigation("navigation width/input limit")
  }
  self.bytes += s.length() + 1
  if !self.body {
    if self.line > 4096 || s.length() < 60 {
      raise InvalidNavigation("navigation header limit/width")
    }
    if self.line == 1 {
      self.version = trimmed(s, 0, 9)
      self.header_system = trimmed(s, 40, 41)
      if ![
          "3.00", "3.01", "3.02", "3.03", "3.04", "3.05", "4.00", "4.01", "4.02",
        ].contains(self.version) ||
        part(s, 20, 21) != "N" ||
        trimmed(s, 60, 80) != "RINEX VERSION / TYPE" ||
        (self.header_system != "M" && !system_ok(self.header_system)) {
        raise InvalidNavigation("expected RINEX3.00-3.05/4.00-4.02 NAV header")
      }
    }
    self.header.push(s)
    if trimmed(s, 60, 80) == "END OF HEADER" {
      self.body = true
    }
    return None
  }
  let r4 = self.version.has_prefix("4")
  if r4 && s.has_prefix(">") {
    let prior = if self.pending.is_empty() {
      None
    } else if self.expected == -1 && self.pending.length() > 1 {
      Some(self.emit())
    } else {
      raise InvalidNavigation("truncated navigation record")
    }
    self.descriptor(s)
    return prior
  }
  if self.pending.is_empty() {
    if r4 {
      raise InvalidNavigation("RINEX4 descriptor required")
    }
    self.satellite = part(s, 0, 3)
    let sys = part(s, 0, 1)
    if (["C", "J"].contains(sys) && ["3.00", "3.01"].contains(self.version)) ||
      (sys == "I" && ["3.00", "3.01", "3.02"].contains(self.version)) {
      raise InvalidNavigation(
        "constellation not defined in declared NAV3 version",
      )
    }
    if !satellite_ok(self.satellite) ||
      (self.header_system != "M" && self.header_system != sys) {
      raise InvalidNavigation("invalid NAV3 satellite/system")
    }
    self.category = "EPH"
    self.family = match sys {
      "R" => "FDMA"
      "E" => "IFNV"
      "C" => "D1D2"
      "S" => "SBAS"
      _ => "LNAV"
    }
    self.subtype = ""
    self.key = navigation_key(self.category, sys, self.family, "")
    if self.key.is_empty() {
      raise UnsupportedConstellation(sys)
    }
    self.expected = 1 + (self.layout().length() - 3) / 4
    self.first_line = self.line
  }
  if self.pending.length() >= 65 {
    raise InvalidNavigation("navigation record 64-payload-line limit")
  }
  self.pending.push(s)
  if self.expected > 0 &&
    self.pending.length() == self.expected + (if r4 { 1 } else { 0 }) {
    Some(self.emit())
  } else {
    None
  }
}

///|
/// Returns the final opaque R4 record, if any. Required even after emitted data.
pub fn NavigationReader::finish(
  self : NavigationReader,
) -> NavigationMessage? raise NavError {
  if self.closed {
    raise InvalidNavigation("navigation reader failed or finished")
  }
  self.closed = true
  if !self.body {
    raise InvalidNavigation("missing END OF HEADER")
  }
  if self.pending.is_empty() {
    None
  } else if self.expected == -1 && self.pending.length() > 1 {
    Some(self.emit())
  } else {
    raise InvalidNavigation("truncated final navigation record")
  }
}
