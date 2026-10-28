///|
fn system_ok(s : String) -> Bool {
  ["G", "R", "E", "C", "J", "I", "S"].contains(s)
}

///|
fn satellite_ok(s : String) -> Bool {
  s.length() == 3 &&
  system_ok(part(s, 0, 1)) &&
  s[1] >= '0' &&
  s[1] <= '9' &&
  s[2] >= '0' &&
  s[2] <= '9' &&
  part(s, 1, 3) != "00"
}

///|
fn Checker::check_continuation(self : Checker) -> Unit raise CheckError {
  if self.continuation is Some(sys) {
    if self.types[sys].length() != self.expected_types[sys] {
      self.reject(
        "observation-types-count", "unfinished SYS / # / OBS TYPES continuation",
      )
    }
    self.continuation = None
  }
}

///|
fn Checker::header_line(self : Checker, s : String) -> Unit raise CheckError {
  if self.line > 4096 {
    self.reject("capacity", "more than 4096 header lines")
  }
  if s.length() < 60 || s.length() > 80 {
    self.reject(
      "header-width", "header must retain columns 1..60 with label in 61..80",
    )
  }
  let label = trimmed(s, 60, 80)
  if self.line == 1 && label != "RINEX VERSION / TYPE" {
    self.reject(
      "version", "first line must be ordinary RINEX, not compressed data",
    )
  }
  if label != "SYS / # / OBS TYPES" {
    self.check_continuation()
  }
  if [
      "RINEX VERSION / TYPE", "MARKER NAME", "TIME OF FIRST OBS", "TIME OF LAST OBS",
      "INTERVAL", "# OF SATELLITES", "RCV CLOCK OFFS APPL", "DOI", "LICENSE OF USE",
      "STATION INFORMATION",
    ].contains(label) {
    if self.headers_seen.contains(label) {
      self.reject("duplicate-header", label)
    }
    self.headers_seen[label] = self.line
  }
  match label {
    "RINEX VERSION / TYPE" => {
      self.version = trimmed(s, 0, 9)
      if !["3.03", "3.04", "3.05", "4.00", "4.01"].contains(self.version) ||
        part(s, 20, 21) != "O" {
        self.reject("unsupported-version", "only listed RINEX 3/4 OBS versions")
      }
      self.file_system = trimmed(s, 40, 41)
      if self.file_system != "M" && !system_ok(self.file_system) {
        self.reject("system", "invalid file satellite system")
      }
    }
    "MARKER NAME" => self.marker = trimmed(s, 0, 60)
    "DOI" => self.doi = trimmed(s, 0, 60)
    "LICENSE OF USE" => self.license = trimmed(s, 0, 60)
    "STATION INFORMATION" => self.station = trimmed(s, 0, 60)
    "TIME OF FIRST OBS" | "TIME OF LAST OBS" => {
      let t = timestamp(
        part(s, 0, 6),
        part(s, 6, 12),
        part(s, 12, 18),
        part(s, 18, 24),
        part(s, 24, 30),
        part(s, 30, 43),
      )
      let scale = trimmed(s, 48, 51)
      if label == "TIME OF FIRST OBS" {
        self.header_first = Some(t)
        self.time_system = scale
      } else {
        self.header_last = Some(t)
        self.last_time_system = scale
      }
    }
    "INTERVAL" => {
      let t = seconds_ticks(part(s, 0, 10))
      if t <= 0L || t > 864000000000L {
        self.reject("interval", "interval must be positive and <=1 day")
      }
      self.interval = Some(t)
    }
    "RCV CLOCK OFFS APPL" => {
      let n = digits(part(s, 0, 6))
      if n > 1 {
        self.reject("clock-applied", "expected 0 or 1")
      }
      self.clock_applied = Some(n)
    }
    "# OF SATELLITES" => {
      let n = digits(part(s, 0, 6))
      if n > 693 {
        self.reject(
          "satellite-count", "at most 7 systems of 99 satellite identifiers",
        )
      }
      self.declared_satellites = Some(n)
    }
    "PRN / # OF OBS" => {
      let id = trimmed(s, 3, 6)
      if !id.is_empty() {
        if !satellite_ok(id) || self.prn_headers.contains(id) {
          self.reject("prn-header", "invalid or repeated satellite header")
        }
        self.prn_headers[id] = true
      }
      self.other_labels[label] = true // observation-total values not interpreted in this version
    }
    "SYS / # / OBS TYPES" => {
      for
        index in [
          1, 2, 6, 10, 14, 18, 22, 26, 30, 34, 38, 42, 46, 50, 54, 58, 59,
        ] {
        if s[index] != ' ' {
          self.reject(
            "observation-types-layout", "reserved type-list columns must be blank",
          )
        }
      }
      let first = trimmed(s, 0, 1)
      let sys = if first.is_empty() {
        match self.continuation {
          Some(v) => v
          None => {
            self.reject("observation-types", "orphan continuation")
            ""
          }
        }
      } else {
        self.check_continuation()
        if !system_ok(first) || self.types.contains(first) {
          self.reject(
            "observation-types", "invalid or repeated system declaration",
          )
        }
        let n = digits(part(s, 3, 6))
        if n < 1 || n > 96 {
          self.reject("capacity", "1..96 observation types per system")
        }
        self.types[first] = []
        self.expected_types[first] = n
        self.continuation = Some(first)
        first
      }
      if first.is_empty() && !trimmed(s, 1, 6).is_empty() {
        self.reject("observation-types", "continuation prefix must be blank")
      }
      let codes = self.types[sys]
      let mut ended = false
      for i in 0..<13 {
        let code = trimmed(s, 7 + i * 4, 10 + i * 4)
        if !code.is_empty() {
          if ended {
            self.reject("observation-code", "gap inside observation type list")
          }
          if code.length() != 3 ||
            !["C", "L", "D", "S"].contains(part(code, 0, 1)) ||
            code[1] < '1' ||
            code[1] > '9' ||
            code[2] < 'A' ||
            code[2] > 'Z' ||
            codes.contains(code) ||
            codes.length() >= self.expected_types[sys] {
            self.reject(
              "observation-code",
              "invalid/duplicate/extra observation type " + code,
            )
          }
          codes.push(code)
        } else {
          ended = true
        }
      }
    }
    "END OF HEADER" => {
      if self.header_first is None ||
        self.types.is_empty() ||
        self.marker.is_empty() {
        self.reject(
          "required-header", "marker, first observation and system type declarations required",
        )
      }
      if self.time_system.is_empty() && self.file_system == "G" {
        self.time_system = "GPS"
      }
      if !self.last_time_system.is_empty() &&
        self.last_time_system != self.time_system {
        self.reject("time-system", "first/last time systems disagree")
      }
      if self.time_system != "GPS" {
        self.reject(
          "unsupported-time-system", "only explicit GPS time (or pure-G default) is currently inspected",
        )
      }
      if self.file_system != "M" &&
        (self.types.length() != 1 || !self.types.contains(self.file_system)) {
        self.reject(
          "system", "single-system header and type declarations disagree",
        )
      }
      for sys, codes in self.types {
        self.counts[sys] = codes.map(code => {
          code,
          nonempty_fields: 0,
          blank_fields: 0,
          zero_values: 0,
          lli_nonzero: 0,
          lli_bit0: 0,
          lli_bit1: 0,
          lli_bit2: 0,
        })
        self.system_records[sys] = 0
      }
      if self.window is Some(_) {
        if self.interval != Some(300000000L) {
          self.note(
            "profile-interval", "EPN daily/hourly subset requires INTERVAL=30",
          )
        }
        if self.license.is_empty() {
          self.note("profile-license", "no LICENSE OF USE header", error=false)
        }
        if self.doi.is_empty() {
          self.note("profile-doi", "no DOI header", error=false)
        }
        if self.station.is_empty() {
          self.note(
            "profile-station-link",
            "no STATION INFORMATION header",
            error=false,
          )
        }
      }
      self.body = true
    }
    "" => self.reject("header-label", "missing header label")
    _ => self.other_labels[label] = true
  }
}
