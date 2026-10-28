///|
pub struct Reader {
  priv checker : Checker
  priv gps_range : (Int64, Int64)?
  priv raw_header : Array[String]
  priv mut pending : PendingEpoch?
}

///|
/// Optional half-open GPS calendar range, in the same exact 100ns unit as
/// Checker. Validate the entire input even when only a range is returned.
pub fn Reader::new(gps_range? : (Int64, Int64)) -> Reader raise CheckError {
  if gps_range is Some((start, stop)) {
    if start < 0L ||
      stop <= start ||
      stop > day_ticks(2100, 12, 31) + 864000000000L {
      raise Rejected(
        "range", 0, "expected increasing GPS ticks within years 1980..2100",
      )
    }
  }
  { checker: Checker::new(), gps_range, raw_header: [], pending: None, }
}

///|
fn Checker::snapshot_header(self : Checker) -> Header {
  let labels = self.other_labels.keys().collect()
  labels.sort()
  let types : Map[String, Array[String]] = Map([])
  for sys, codes in self.types {
    types[sys] = codes.copy()
  }
  {
    version: self.version,
    marker: self.marker,
    time_system: self.time_system,
    first: self.header_first.unwrap(),
    last: self.header_last,
    interval: self.interval,
    declared_satellites: self.declared_satellites,
    license: self.license,
    doi: self.doi,
    observation_types: types,
    uninterpreted_labels: labels,
  }
}

///|
/// Snapshot the validated header. Raw lines retain scale/phase/clock/unit and
/// unknown metadata; they are not evidence those corrections were interpreted.
pub fn Reader::header(self : Reader) -> ObservationHeader? {
  if self.checker.body {
    Some({
      parsed: self.checker.snapshot_header(),
      raw_lines: self.raw_header.copy(),
    })
  } else {
    None
  }
}

///|
/// Return an epoch only after every declared satellite record has validated.
/// Previously returned epochs remain provisional until finish() succeeds.
pub fn Reader::feed_line(
  self : Reader,
  line : String,
) -> ObservationEpoch? raise CheckError {
  try {
    let in_header = !self.checker.body
    let capture = if line.has_prefix(">") {
      true
    } else {
      match self.pending {
        Some(p) => p.selected
        None => false
      }
    }
    let parsed = self.checker.consume_line(line, capture)
    if in_header {
      self.raw_header.push(line)
    }
    match parsed {
      Some(Epoch(start)) => {
        let selected = match self.gps_range {
          Some((first, stop)) =>
            start.gps_ticks >= first && start.gps_ticks < stop
          None => true
        }
        self.pending = Some({ start, selected, satellites: [], })
      }
      Some(Satellite(record)) => {
        guard self.pending is Some(pending) else {
          self.checker.reject("state", "missing epoch buffer")
          return None
        }
        pending.satellites.push(record)
      }
      None => ()
    }
    if self.checker.remaining == 0 && self.pending is Some(pending) {
      self.pending = None
      if pending.selected {
        let s = pending.start
        return Some({
          gps_ticks: s.gps_ticks,
          flag: s.flag,
          line: s.line,
          end_line: self.checker.line,
          raw_record: s.raw_record,
          receiver_clock: s.receiver_clock,
          receiver_clock_raw: s.receiver_clock_raw,
          satellites: pending.satellites,
        })
      }
    }
    None
  } catch {
    Rejected(code, at, detail) => {
      self.checker.closed = true
      self.pending = None
      raise Rejected(code, at, detail)
    }
  }
}

///|
/// Report the entire input, not just the selected output range. A completed
/// report may be unacceptable; consumers must inspect its findings separately.
pub fn Reader::finish(self : Reader) -> Report raise CheckError {
  self.checker.finish() catch {
    Rejected(code, at, detail) => {
      self.pending = None
      raise Rejected(code, at, detail)
    }
  }
}
