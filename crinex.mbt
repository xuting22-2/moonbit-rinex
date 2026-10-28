///|
priv struct DifferenceArc {
  target : Int
  level : Int
  history : Array[Int64]
}

///|
fn decode_arc(
  token : String,
  previous : DifferenceArc?,
) -> DifferenceArc raise CheckError {
  let reset = token.length() >= 2 && token[1] == '&'
  let (target, level, history, value) = if reset {
    let order = digits(part(token, 0, 1))
    if order > 5 {
      raise Rejected("crx-order", 0, "maximum differential order5")
    }
    (order, 0, [], signed_integer64(part(token, 2, token.length())))
  } else {
    guard previous is Some(old) else {
      raise Rejected("crx-uninitialized", 0, "numeric arc needs n&value")
    }
    (
      old.target,
      (old.level + 1).min(old.target),
      old.history,
      signed_integer64(token),
    )
  }
  let next = [ for _ in 0..<(level + 1) => 0L ]
  next[level] = value
  for k = level; k > 0; k = k - 1 {
    next[k - 1] = checked_add64(next[k], history[k - 1])
  }
  { target, level, history: next, }
}

///|
fn strip_right(s : String) -> String {
  let mut end = s.length()
  while end > 0 && s[end - 1] == ' ' {
    end -= 1
  }
  part(s, 0, end)
}

///|
fn text_difference(previous : String, delta : String) -> String {
  let b = StringBuilder()
  for i in 0..<previous.length().max(delta.length()) {
    let d = part(delta, i, i + 1)
    b.write_string(
      if d == "&" {
        " "
      } else if d == " " || d.is_empty() {
        let old = part(previous, i, i + 1)
        if old.is_empty() {
          " "
        } else {
          old
        }
      } else {
        d
      },
    )
  }
  b.to_string()
}

///|
pub struct CrinexReport {
  complete : Bool
  acceptable : Bool
  epochs : Int
  recovered_epochs : Int
  findings : Array[Finding]
} derive(@debug.Debug, ToJson)

///|
/// CRINEX1.0/3.0 native incremental restoration. Output is provisional until
/// finish. Default fail-fast; optional recovery only after an observation-line
/// error at known record boundaries, then a fully initialized epoch.
/// Recovery never scans through unknown header changes or reports acceptance.
pub struct CrinexDecoder {
  priv mut line : Int
  priv mut bytes : Int
  priv mut closed : Bool
  priv mut stage : Int
  priv mut v1 : Bool
  priv mut rnx2 : Bool
  priv mut legacy_system : String
  priv mut header_lines : Int
  priv counts : Map[String, Int]
  priv mut global_count : Int
  priv mut types_left : Int
  priv mut epoch_text : String
  priv mut flag : Int
  priv mut event_left : Int
  priv satellites : Array[String]
  priv mut satellite_index : Int
  priv mut clock : DifferenceArc?
  priv arcs : Map[String, DifferenceArc]
  priv flags : Map[String, String]
  priv next_arcs : Map[String, DifferenceArc]
  priv next_flags : Map[String, String]
  priv output : Array[String]
  priv recover : Bool
  priv mut recovering : Bool
  priv mut discard_left : Int
  priv mut epochs : Int
  priv mut recovered_epochs : Int
  priv findings : Array[Finding]
}

///|
pub fn CrinexDecoder::new(recover? : Bool = false) -> CrinexDecoder {
  {
    line: 0,
    bytes: 0,
    closed: false,
    stage: 0,
    v1: false,
    rnx2: false,
    legacy_system: "G",
    header_lines: 0,
    counts: {},
    global_count: 0,
    types_left: 0,
    epoch_text: "",
    flag: 0,
    event_left: 0,
    satellites: [],
    satellite_index: 0,
    clock: None,
    arcs: {},
    flags: {},
    next_arcs: {},
    next_flags: {},
    output: [],
    recover,
    recovering: false,
    discard_left: 0,
    epochs: 0,
    recovered_epochs: 0,
    findings: [],
  }
}

///|
fn CrinexDecoder::header_record(
  self : CrinexDecoder,
  s : String,
) -> Unit raise CheckError {
  if s.length() < 60 || s.length() > 80 {
    raise Rejected("crx-header-width", 0, "header width60..80")
  }
  let label = trimmed(s, 60, 80)
  let type_label = if self.rnx2 {
    "# / TYPES OF OBSERV"
  } else {
    "SYS / # / OBS TYPES"
  }
  if self.types_left > 0 && label != type_label {
    raise Rejected("crx-types", 0, "unfinished observation-type continuation")
  }
  if self.rnx2 && label == "RINEX VERSION / TYPE" {
    let system = trimmed(s, 40, 41)
    self.legacy_system = if system.is_empty() { "G" } else { system }
  }
  let (begin, step, slots, code_width) = match label {
    "# / TYPES OF OBSERV" => {
      if !self.rnx2 {
        raise Rejected("crx-types", 0, "legacy type declaration in modern OBS")
      }
      if !trimmed(s, 0, 6).is_empty() {
        if self.types_left > 0 {
          raise Rejected(
            "crx-types", 0, "unfinished observation-type continuation",
          )
        }
        self.global_count = digits(part(s, 0, 6))
        if self.global_count < 1 || self.global_count > 96 {
          raise Rejected("crx-types", 0, "count1..96")
        }
        self.types_left = self.global_count
      } else if self.types_left == 0 {
        raise Rejected("crx-types", 0, "orphan observation-type continuation")
      }
      (10, 6, 9, 2)
    }
    "SYS / # / OBS TYPES" => {
      if self.rnx2 {
        raise Rejected("crx-types", 0, "modern type declaration in legacy OBS")
      }
      if !trimmed(s, 0, 1).is_empty() {
        if self.types_left > 0 {
          raise Rejected(
            "crx-types", 0, "unfinished observation-type continuation",
          )
        }
        let n = digits(part(s, 3, 6))
        if n < 1 || n > 96 || !system_ok(part(s, 0, 1)) {
          raise Rejected("crx-types", 0, "system/count invalid")
        }
        self.counts[part(s, 0, 1)] = n
        self.types_left = n
      } else if self.types_left == 0 || !trimmed(s, 0, 7).is_empty() {
        raise Rejected(
          "crx-types", 0, "orphan/invalid observation-type continuation",
        )
      }
      (7, 4, 13, 3)
    }
    _ => return
  }
  // Count the actual declared slots, not only the numeric total. A truncated
  // header/update must never certify a restored file with unknown slot names.
  for i in 0..<slots {
    let code = trimmed(s, begin + i * step, begin + i * step + code_width)
    if !code.is_empty() {
      if code.length() != code_width || self.types_left == 0 {
        raise Rejected("crx-types", 0, "invalid/excess observation-type slot")
      }
      self.types_left -= 1
    }
  }
}

///|
fn CrinexDecoder::count_for(
  self : CrinexDecoder,
  satellite : String,
) -> Int raise CheckError {
  if self.rnx2 {
    if self.global_count == 0 {
      raise Rejected("crx-types", 0, "missing legacy types")
    }
    self.global_count
  } else {
    match self.counts.get(part(satellite, 0, 1)) {
      Some(n) => n
      None =>
        raise Rejected(
          "crx-types", 0, "satellite system lacks type declaration",
        )
    }
  }
}

///|
fn CrinexDecoder::epoch_satellites(
  self : CrinexDecoder,
  text : String,
  n : Int,
) -> Array[String] raise CheckError {
  let offset = if self.rnx2 { 29 } else { 32 }
  let start = if self.rnx2 { 32 } else { 41 }
  // Trailing unused columns may be absent in a zero-satellite descriptor.
  let minimum = if n == 0 { offset + 3 } else { start + n * 3 }
  if text.length() < minimum ||
    !trimmed(text, start + n * 3, text.length()).is_empty() {
    raise Rejected(
      "crx-satellite-list", 0, "descriptor list length differs from count",
    )
  }
  let satellites : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for i in 0..<n {
    let id = part(text, start + i * 3, start + (i + 1) * 3)
    let identity = if self.rnx2 {
      let system = if id[0] == ' ' {
        if self.legacy_system != "G" {
          raise Rejected(
            "crx-satellite", 0, "blank satellite system requires a pure GPS file",
          )
        }
        "G"
      } else {
        part(id, 0, 1)
      }
      if !["G", "R", "E", "S"].contains(system) {
        raise Rejected("crx-satellite", 0, "invalid legacy satellite system")
      }
      let prn = digits(part(id, 1, 3)) catch {
        _ =>
          raise Rejected("crx-satellite", 0, "invalid legacy satellite number")
      }
      if prn < 1 || prn > 99 {
        raise Rejected("crx-satellite", 0, "satellite number must be1..99")
      }
      system + (if prn < 10 { "0" } else { "" }) + prn.to_string()
    } else {
      if !satellite_ok(id) {
        raise Rejected(
          "crx-satellite", 0, "invalid modern satellite identifier",
        )
      }
      id
    }
    if seen.contains(identity) {
      raise Rejected("crx-satellite", 0, "duplicate satellite identity")
    }
    seen[identity] = true
    ignore(self.count_for(id))
    // Keep the exact descriptor spelling for output and CRINEX arc matching.
    // Canonical identity is used only to validate uniqueness within an epoch.
    satellites.push(id)
  }
  satellites
}

///|
fn CrinexDecoder::start_epoch(
  self : CrinexDecoder,
  s : String,
) -> Unit raise CheckError {
  let initialized = if self.v1 { s.has_prefix("&") } else { s.has_prefix(">") }
  if !self.v1 && s.has_prefix("&") {
    return
  } // CRINEX3 escape, never a reset.
  if self.recovering && !initialized {
    // Epoch is still syntactically known; skip by its current satellite count.
    // A partial epoch while recovering must still retain a valid descriptor.
    let text = text_difference(self.epoch_text, s)
    let offset = if self.rnx2 { 29 } else { 32 }
    let n = digits(part(text, offset, offset + 3))
    if n > 693 {
      raise Rejected("crx-satellite-count", 0, "count<=693")
    }
    let f = digits(part(text, offset - 1, offset))
    if f > 1 {
      raise Rejected(
        "crx-recovery-header", 0, "event while unsynchronized cannot be skipped",
      )
    }
    ignore(self.epoch_satellites(text, n))
    self.epoch_text = text
    self.discard_left = n + 1
    return
  }
  if initialized {
    self.arcs.clear()
    self.flags.clear()
    self.clock = None
    self.epoch_text = if self.v1 { " " + part(s, 1, s.length()) } else { s }
  } else {
    if self.epoch_text.is_empty() {
      raise Rejected("crx-epoch", 0, "first epoch must initialize text")
    }
    self.epoch_text = text_difference(self.epoch_text, s)
  }
  let offset = if self.rnx2 { 29 } else { 32 }
  self.flag = digits(part(self.epoch_text, offset - 1, offset))
  let n = digits(part(self.epoch_text, offset, offset + 3))
  if self.flag > 6 || ((self.flag <= 1 || self.flag == 6) && n > 693) {
    raise Rejected("crx-epoch", 0, "invalid flag/count")
  }
  self.output.clear()
  if self.flag > 1 && self.flag < 6 {
    if !initialized {
      raise Rejected("crx-event", 0, "event descriptor must initialize")
    }
    self.event_left = n
    self.output.push(strip_right(self.epoch_text))
    self.stage = if n > 0 { 4 } else { 3 }
    return
  }
  if self.flag == 6 {
    // RINEX2.11 Table A2: flag6 uses the observation layout, so n is the
    // satellite count, not the number of physical continuation records.
    // Event records themselves are preserved, not numerically differenced.
    if !initialized {
      raise Rejected("crx-event", 0, "flag6 requires initialized event")
    }
    self.event_left = if self.rnx2 {
      if self.global_count == 0 {
        raise Rejected(
          "crx-types", 0, "cycle-slip records need observation types",
        )
      }
      ((n + 11) / 12 - 1).max(0) + n * ((self.global_count + 4) / 5)
    } else {
      n
    }
    self.output.push(strip_right(self.epoch_text))
    self.stage = if self.event_left > 0 { 4 } else { 3 }
    return
  }
  self.satellites.clear()
  for id in self.epoch_satellites(self.epoch_text, n) {
    self.satellites.push(id)
  }
  self.satellite_index = 0
  self.next_arcs.clear()
  self.next_flags.clear()
  self.stage = 5 // clock line precedes observation lines
}

///|
fn CrinexDecoder::clock_line(
  self : CrinexDecoder,
  s : String,
) -> Unit raise CheckError {
  if s.is_empty() {
    self.clock = None
  } else {
    self.clock = Some(decode_arc(s, self.clock))
  }
  if self.rnx2 {
    let base = part(self.epoch_text, 0, 68)
    self.output.push(
      match self.clock {
        Some(arc) =>
          right_pad(base, 68) + fractional_text(arc.history[0], 9, 12)
        None => strip_right(base)
      },
    )
    let n = self.satellites.length()
    for at = 12; at < n; at = at + 12 {
      self.output.push(
        right_pad("", 32) +
        strip_right(
          part(self.epoch_text, 32 + at * 3, 32 + (at + 12).min(n) * 3),
        ),
      )
    }
  } else {
    let base = part(self.epoch_text, 0, 41)
    self.output.push(
      match self.clock {
        Some(arc) =>
          right_pad(base, 41) + fractional_text(arc.history[0], 12, 15)
        None => strip_right(base)
      },
    )
  }
  self.stage = if self.satellites.is_empty() { 3 } else { 6 }
  if self.satellites.is_empty() {
    self.arcs.clear()
    self.flags.clear()
  }
}

///|
fn CrinexDecoder::observation(
  self : CrinexDecoder,
  s : String,
) -> Unit raise CheckError {
  let sat = self.satellites[self.satellite_index]
  let n = self.count_for(sat)
  let tokens : Array[String] = []
  let mut start = 0
  for _ in 0..<n {
    let mut end = start
    while end < s.length() && s[end] != ' ' {
      end += 1
    }
    tokens.push(part(s, start, end))
    start = end + 1
  }
  let flag_delta = part(s, start, s.length())
  if flag_delta.length() > n * 2 {
    raise Rejected("crx-flags", 0, "too many flag characters")
  }
  let previous_flags = self.flags.get(sat).unwrap_or("")
  let restored_flags = right_pad(
    text_difference(previous_flags, flag_delta),
    n * 2,
  )
  let fields : Array[String] = []
  let f = StringBuilder()
  for i in 0..<n {
    let key = sat + ":" + i.to_string()
    let token = tokens[i]
    let pair = part(restored_flags, i * 2, i * 2 + 2)
    if !pair.trim().is_empty() {
      let lli = part(pair, 0, 1)
      let ssi = part(pair, 1, 2)
      if (!lli.trim().is_empty() && digits(lli) > 7) ||
        (!ssi.trim().is_empty() && digits(ssi) > 9) {
        raise Rejected("crx-flags", 0, "LLI/SSI range")
      }
    }
    let out_pair = if token.is_empty() && self.v1 { "  " } else { pair }
    f.write_string(out_pair)
    if token.is_empty() {
      fields.push(right_pad("", 14) + out_pair)
    } else {
      let arc = decode_arc(token, self.arcs.get(key))
      self.next_arcs[key] = arc
      fields.push(fractional_text(arc.history[0], 3, 14) + out_pair)
    }
  }
  self.next_flags[sat] = f.to_string()
  if self.rnx2 {
    for at = 0; at < n; at = at + 5 {
      let row = StringBuilder()
      for i in at..<(at + 5).min(n) {
        row.write_string(fields[i])
      }
      self.output.push(strip_right(row.to_string()))
    }
  } else {
    self.output.push(strip_right(sat + fields.join("")))
  }
  self.satellite_index += 1
  if self.satellite_index == self.satellites.length() {
    self.arcs.clear()
    for key, value in self.next_arcs {
      self.arcs[key] = value
    }
    self.flags.clear()
    for key, value in self.next_flags {
      self.flags[key] = value
    }
    if self.recovering {
      self.recovered_epochs += 1
      self.recovering = false
    }
    self.epochs += 1
    self.stage = 3
  }
}

///|
fn CrinexDecoder::consume(
  self : CrinexDecoder,
  s : String,
) -> Array[String] raise CheckError {
  if self.closed {
    raise Rejected("state", 0, "decoder failed or finished")
  }
  self.line += 1
  ascii_line(s)
  if self.bytes > 536870912 - s.length() - 1 {
    raise Rejected("capacity", 0, "input512MiB limit")
  }
  self.bytes += s.length() + 1
  if self.discard_left > 0 {
    self.discard_left -= 1
    return []
  }
  match self.stage {
    0 => {
      let v = trimmed(s, 0, 9)
      if !["1.0", "3.0"].contains(v) ||
        trimmed(s, 60, 80) != "CRINEX VERS   / TYPE" {
        raise Rejected("crx-version", 0, "only CRINEX1.0/3.0")
      }
      self.v1 = v == "1.0"
      self.stage = 1
      []
    }
    1 => {
      if trimmed(s, 60, 80) != "CRINEX PROG / DATE" {
        raise Rejected("crx-header", 0, "missing program/date")
      }
      self.stage = 2
      []
    }
    2 => {
      self.header_lines += 1
      if self.header_lines > 4096 {
        raise Rejected("capacity", 0, "header4096line limit")
      }
      if self.header_lines == 1 {
        let version = trimmed(s, 0, 9)
        self.rnx2 = version == "2.11"
        if self.v1 != self.rnx2 ||
          (
            !self.rnx2 &&
            !["3.03", "3.04", "3.05", "4.00", "4.01"].contains(version)
          ) ||
          part(s, 20, 21) != "O" {
          raise Rejected(
            "crx-rinex-version", 0, "unsupported source OBS version/type",
          )
        }
      }
      self.header_record(s)
      if trimmed(s, 60, 80) == "END OF HEADER" {
        self.stage = 3
      }
      [s]
    }
    3 => {
      self.start_epoch(s)
      if self.stage == 3 && !self.output.is_empty() {
        let out = self.output.copy()
        self.output.clear()
        out
      } else {
        []
      }
    }
    4 => {
      if self.flag == 3 || self.flag == 4 {
        self.header_record(s)
      }
      self.output.push(strip_right(s))
      self.event_left -= 1
      if self.event_left == 0 {
        if self.types_left != 0 {
          raise Rejected("crx-types", 0, "incomplete updated observation types")
        }
        self.stage = 3
        self.epoch_text = ""
        let out = self.output.copy()
        self.output.clear()
        out
      } else {
        []
      }
    }
    5 => {
      self.clock_line(s)
      if self.stage == 3 {
        self.epochs += 1
        let out = self.output.copy()
        self.output.clear()
        out
      } else {
        []
      }
    }
    _ => {
      self.observation(s) catch {
        Rejected(code, _, detail) => {
          if !self.recover {
            raise Rejected(code, self.line, detail)
          }
          if self.findings.length() < 128 {
            self.findings.push({
              code: "crx-unsynchronized",
              line: self.line,
              error: true,
              detail: code + ":" + detail,
            })
          }
          self.discard_left = self.satellites.length() -
            self.satellite_index -
            1
          self.output.clear()
          self.arcs.clear()
          self.flags.clear()
          self.clock = None
          self.recovering = true
          self.stage = 3
        }
      }
      if self.stage == 3 && !self.recovering {
        let out = self.output.copy()
        self.output.clear()
        out
      } else {
        []
      }
    }
  }
}

///|
pub fn CrinexDecoder::feed_line(
  self : CrinexDecoder,
  s : String,
) -> Array[String] raise CheckError {
  self.consume(s) catch {
    Rejected(code, at, detail) => {
      self.closed = true
      raise Rejected(code, if at == 0 { self.line } else { at }, detail)
    }
  }
}

///|
pub fn CrinexDecoder::finish(
  self : CrinexDecoder,
) -> CrinexReport raise CheckError {
  if self.closed {
    raise Rejected("state", self.line, "decoder failed or finished")
  }
  self.closed = true
  if self.stage != 3 || self.discard_left > 0 {
    raise Rejected(
      "crx-truncated",
      self.line,
      "incomplete header/epoch/clock/event",
    )
  }
  {
    complete: !self.recovering && self.findings.is_empty(),
    acceptable: self.findings.is_empty(),
    epochs: self.epochs,
    recovered_epochs: self.recovered_epochs,
    findings: self.findings.copy(),
  }
}
