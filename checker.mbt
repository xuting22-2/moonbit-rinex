///|
pub fn Checker::feed_line(
  self : Checker,
  line : String,
) -> Unit raise CheckError {
  ignore(self.consume_line(line, false))
}

///|
fn Checker::consume_line(
  self : Checker,
  line : String,
  capture : Bool,
) -> ParsedLine? raise CheckError {
  if self.closed {
    raise Rejected("state", self.line, "checker is failed or finished")
  }
  self.line += 1
  try {
    if line.length() > 8192 || self.bytes > 536870912 - line.length() - 1 {
      self.reject("capacity", "line/input byte limit exceeded")
    }
    if line.iter().any(c => c < ' ' || c > '~') {
      self.reject(
        "ascii", "feed_line expects printable ASCII without line terminators",
      )
    }
    self.bytes += line.length() + 1
    if !self.body {
      self.header_line(line)
      None
    } else if line.has_prefix(">") {
      self.epoch_line(line, capture).map(epoch => ParsedLine::Epoch(epoch))
    } else {
      self
      .observation_line(line, capture)
      .map(record => ParsedLine::Satellite(record))
    }
  } catch {
    Rejected(code, at, detail) => {
      self.closed = true
      raise Rejected(code, if at == 0 { self.line } else { at }, detail)
    }
  }
}

///|
fn Checker::epoch_line(
  self : Checker,
  s : String,
  capture : Bool,
) -> EpochStart? raise CheckError {
  if self.remaining != 0 {
    self.reject(
      "truncated-epoch", "new epoch before declared satellite records completed",
    )
  }
  if s.length() < 35 || s.length() > 56 {
    self.reject("epoch-width", "invalid epoch record width")
  }
  for index in [1, 6, 9, 12, 15, 29, 30] {
    if s[index] != ' ' {
      self.reject("epoch-layout", "reserved epoch separators must be spaces")
    }
  }
  if !trimmed(s, 35, 41).is_empty() {
    self.reject("epoch-layout", "reserved epoch columns must be blank")
  }
  let flag = digits(part(s, 31, 32))
  if flag > 1 {
    self.reject(
      "unsupported-event", "event flags 2..6 require state semantics outside this version",
    )
  }
  let t = timestamp(
    part(s, 2, 6),
    part(s, 7, 9),
    part(s, 10, 12),
    part(s, 13, 15),
    part(s, 16, 18),
    part(s, 18, 29),
  )
  let n = digits(part(s, 32, 35))
  if n > 693 {
    self.reject(
      "satellite-count", "epoch count exceeds finite satellite namespace",
    )
  }
  if n == 0 {
    self.note(
      "empty-epoch",
      "epoch contains no satellite observations",
      error=self.window is Some(_),
    )
  }
  if self.epochs >= 1000000 {
    self.reject("capacity", "more than one million epochs")
  }
  if self.last is Some(last) {
    if t <= last {
      self.note("epoch-order", "duplicate or decreasing epoch")
    } else if self.interval is Some(step) {
      let delta = t - last
      if delta != step {
        self.note(
          "epoch-interval", "adjacent epoch spacing differs from header INTERVAL",
        )
        if delta > step && delta % step == 0L {
          let slots = delta / step - 1L
          // Calendar range caps result; total skipped slots may exceed Int.
          if slots > 1000000000L ||
            self.missing.to_int64() + slots > 1000000000L {
            self.reject("capacity", "missing slot counter exceeds one billion")
          }
          self.missing += slots.to_int()
        }
      }
    }
  } else {
    self.first = Some(t)
  }
  if self.window is Some(w) {
    if t < w.start || t >= w.stop {
      self.note(
        "profile-window", "epoch outside selected half-open GPS delivery window",
      )
    }
    if (t - w.start) % 300000000L != 0L {
      self.note("profile-lattice", "epoch is not on the GPS :00/:30 lattice")
    }
  }
  if flag == 1 {
    self.power += 1
    self.note("power-failure", "receiver power interruption flag", error=false)
  }
  let clock = trimmed(s, 41, 56)
  let clock_value = if !clock.is_empty() {
    let value = decimal(clock)
    self.clocks += 1
    if self.clock_applied is None {
      self.note(
        "clock-header-missing", "clock offset present without RCV CLOCK OFFS APPL",
      )
    }
    Some(value)
  } else {
    None
  }
  self.last = Some(t)
  self.epochs += 1
  self.remaining = n
  self.epoch_satellites.clear()
  if capture {
    Some({
      gps_ticks: t,
      flag,
      line: self.line,
      raw_record: s,
      receiver_clock: clock_value,
      receiver_clock_raw: part(s, 41, 56),
    })
  } else {
    None
  }
}

///|
fn Checker::observation_line(
  self : Checker,
  s : String,
  capture : Bool,
) -> SatelliteObservation? raise CheckError {
  if self.remaining == 0 {
    self.reject(
      "unexpected-observation", "expected epoch header, not extra satellite record",
    )
  }
  let id = part(s, 0, 3)
  if !satellite_ok(id) {
    self.reject("satellite-id", "invalid satellite identifier")
  }
  if self.epoch_satellites.contains(id) {
    self.reject("duplicate-satellite", id + " repeated in current epoch")
  }
  let sys = part(id, 0, 1)
  guard self.counts.get(sys) is Some(counters) else {
    self.reject("undeclared-system", id)
    return None
  }
  if s.length() > 3 + counters.length() * 16 &&
    !trimmed(s, 3 + counters.length() * 16, s.length()).is_empty() {
    self.reject(
      "extra-observation-fields", "payload exceeds declared observation types",
    )
  }
  if self.records >= 2000000 {
    self.reject("capacity", "more than two million satellite records")
  }
  let fields : Array[ObservationValue] = []
  for i, counter in counters {
    let at = 3 + i * 16
    let number = trimmed(s, at, at + 14)
    let lli = trimmed(s, at + 14, at + 15)
    let ssi = trimmed(s, at + 15, at + 16)
    if !ssi.is_empty() && (ssi < "0" || ssi > "9") {
      self.reject("ssi", "SSI must be blank or digit 0..9")
    }
    let lock = if lli.is_empty() { 0 } else { digits(lli) }
    if lock > 7 {
      self.reject("lli", "LLI must be blank or three-bit value 0..7")
    }
    if lock > 0 && !counter.code.has_prefix("L") {
      self.note("lli-nonphase", "LLI set on non-phase observation", error=false)
    }
    let value = if number.is_empty() {
      counter.blank_fields += 1
      None
    } else {
      let numeric = decimal(number)
      if numeric == 0.0 {
        counter.zero_values += 1
      }
      counter.nonempty_fields += 1
      Some(numeric)
    }
    if capture {
      fields.push({
        code: counter.code,
        column: at + 1,
        raw_field: part(s, at, at + 16),
        value,
        lli: if lli.is_empty() {
          None
        } else {
          Some(lock)
        },
        ssi: if ssi.is_empty() {
          None
        } else {
          Some(digits(ssi))
        },
      })
    }
    if lock != 0 {
      counter.lli_nonzero += 1
    }
    if (lock & 1) != 0 {
      counter.lli_bit0 += 1
    }
    if (lock & 2) != 0 {
      counter.lli_bit1 += 1
    }
    if (lock & 4) != 0 {
      counter.lli_bit2 += 1
    }
  }
  self.system_records[sys] = self.system_records[sys] + 1
  self.satellites[id] = true
  self.epoch_satellites[id] = true
  self.remaining -= 1
  self.records += 1
  if capture {
    Some({
      satellite: id,
      line: self.line,
      raw_record: s,
      observations: fields,
    })
  } else {
    None
  }
}

///|
pub fn Checker::finish(self : Checker) -> Report raise CheckError {
  if self.closed {
    raise Rejected("state", self.line, "checker is failed or finished")
  }
  self.closed = true
  if !self.body {
    self.reject("truncated-header", "END OF HEADER not received")
  }
  if self.remaining != 0 {
    self.reject(
      "truncated-epoch", "EOF before declared satellite records completed",
    )
  }
  if self.epochs == 0 {
    self.reject("empty-body", "no observation epochs")
  }
  let first = self.first.unwrap()
  let last = self.last.unwrap()
  if first != self.header_first.unwrap() {
    self.note(
      "header-first",
      "first observed epoch differs from header",
      at=self.headers_seen["TIME OF FIRST OBS"],
    )
  }
  if self.header_last is Some(value) && value != last {
    self.note(
      "header-last",
      "last observed epoch differs from header",
      at=self.headers_seen["TIME OF LAST OBS"],
    )
  }
  if self.declared_satellites is Some(value) {
    if value != self.satellites.length() {
      self.note(
        "header-satellite-total",
        "declared " +
        value.to_string() +
        "; observed " +
        self.satellites.length().to_string(),
        at=self.headers_seen["# OF SATELLITES"],
      )
    }
    if self.prn_headers.length() != value {
      self.note(
        "header-prn-details",
        "PRN / # OF OBS satellite detail count differs from declared total",
        error=false,
      )
    }
  }
  if self.window is Some(w) {
    if first != w.start {
      self.note(
        "profile-first", "missing or extra leading portion of selected window",
      )
    }
    if last != w.stop - 300000000L {
      self.note(
        "profile-last", "missing or extra trailing portion of selected window",
      )
    }
    if self.epochs.to_int64() != (w.stop - w.start) / 300000000L {
      self.note(
        "profile-epoch-count", "epoch count differs from expected delivery lattice",
      )
    }
    if self.header_first != Some(w.start) ||
      self.header_last != Some(w.stop - 300000000L) {
      self.note(
        "profile-header-window", "declared first/last do not cover selected delivery window",
      )
    }
  }
  let systems = self.counts.keys().collect()
  systems.sort()
  let system_counts = systems.map(sys => {
    let satellites = self.satellites
      .keys()
      .filter(id => id.has_prefix(sys))
      .collect()
    satellites.sort()
    let signals : Array[SignalCounts] = self.counts[sys].map(c => {
      code: c.code,
      nonempty_fields: c.nonempty_fields,
      blank_fields: c.blank_fields,
      zero_values: c.zero_values,
      lli_nonzero: c.lli_nonzero,
      lli_bit0: c.lli_bit0,
      lli_bit1: c.lli_bit1,
      lli_bit2: c.lli_bit2,
    })
    { system: sys, records: self.system_records[sys], satellites, signals, }
  })
  {
    complete: true,
    acceptable: self.errors == 0,
    profile: match self.window {
      Some(w) => w.kind
      None => "bounded OBS structural/time checks"
    },
    time_unit: "100ns calendar ticks since 1980-01-01 00:00:00 GPS; not UTC",
    header: self.snapshot_header(),
    epochs: self.epochs,
    records: self.records,
    first,
    last,
    missing_epoch_slots: self.missing,
    power_failure_epochs: self.power,
    receiver_clock_epochs: self.clocks,
    systems: system_counts,
    findings: self.findings.copy(),
    finding_counts: self.finding_counts.copy(),
    omitted_findings: self.total_findings - self.findings.length(),
  }
}
