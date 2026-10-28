///|
pub suberror CatalogError {
  InvalidCatalogInput(String)
  CatalogCapacityExceeded
} derive(@debug.Debug)

///|
pub(all) enum NavRejectionReason {
  Expired
  Unhealthy
  OrbitChoiceRequired
  InvalidModel(String)
  NonConvergence
  Unsupported(String)
} derive(@debug.Debug, ToJson)

///|
pub struct NavCandidate {
  record_index : Int
  source_line : Int
  satellite : String
  message : String
  toc : NavTime
  toe : NavTime
  health : Int
} derive(@debug.Debug, ToJson)

///|
pub struct NavRejection {
  candidate : NavCandidate
  reason : NavRejectionReason
} derive(@debug.Debug, ToJson)

///|
pub struct NavQueryReport {
  satellite : String
  at : NavTime
  candidates : Int
  eligible : Int
  rejected : Int
  rejection_counts : Map[String, Int]
  rejection_samples : Array[NavRejection]
  omitted_rejections : Int
} derive(@debug.Debug, ToJson)

///|
pub struct NavSelection {
  record : NavCandidate
  state : SatPosition
  equivalent_records : Int
  report : NavQueryReport
} derive(@debug.Debug, ToJson)

///|
pub struct NavAmbiguity {
  candidates : Array[NavCandidate]
  tied_records : Int
  omitted_candidates : Int
  report : NavQueryReport
} derive(@debug.Debug, ToJson)

///|
pub(all) enum NavQueryOutcome {
  Selected(NavSelection)
  Unavailable(NavQueryReport)
  Conflict(NavAmbiguity)
} derive(@debug.Debug, ToJson)

///|
priv struct CatalogEntry {
  record : NavRecord
  source_line : Int
}

///|
/// Bounded caller-supplied broadcast records. Finish any source NavReader before
/// treating catalog queries as a complete-file result. No record is evicted.
pub struct NavCatalog {
  priv capacity : Int
  priv entries : Array[CatalogEntry]
  priv by_satellite : Map[String, Array[Int]]
}

///|
pub fn NavCatalog::new(capacity? : Int = 4096) -> NavCatalog raise CatalogError {
  if capacity < 1 || capacity > 32768 {
    raise InvalidCatalogInput("capacity must be1..32768")
  }
  { capacity, entries: [], by_satellite: {}, }
}

///|
pub fn NavCatalog::len(self : NavCatalog) -> Int {
  self.entries.length()
}

///|
/// Stable one-based index, or None outside the stored range.
pub fn NavCatalog::record(self : NavCatalog, index : Int) -> NavRecord? {
  if index < 1 {
    None
  } else {
    self.entries.get(index - 1).map(entry => entry.record)
  }
}

///|
/// source_line=0 means unknown; otherwise use a one-based physical input line.
/// Invalid/capacity additions leave the catalog unchanged.
pub fn NavCatalog::add(
  self : NavCatalog,
  record : NavRecord,
  source_line? : Int = 0,
) -> Int raise CatalogError {
  if !satellite_ok(record.satellite) ||
    !["G", "C"].contains(part(record.satellite, 0, 1)) ||
    source_line < 0 {
    raise InvalidCatalogInput(
      "expected GPS/BDS record and nonnegative source line",
    )
  }
  if self.entries.length() == self.capacity {
    raise CatalogCapacityExceeded
  }
  let index = self.entries.length()
  self.entries.push({ record, source_line, })
  match self.by_satellite.get(record.satellite) {
    Some(indices) => indices.push(index)
    None => self.by_satellite[record.satellite] = [index]
  }
  index + 1
}

///|
fn catalog_candidate(entry : CatalogEntry, index : Int) -> NavCandidate {
  let r = entry.record
  {
    record_index: index + 1,
    source_line: entry.source_line,
    satellite: r.satellite,
    message: r.message,
    toc: r.toc,
    toe: r.toe,
    health: r.health,
  }
}

///|
fn catalog_same_record(a : NavRecord, b : NavRecord) -> Bool {
  if a.satellite != b.satellite ||
    a.message != b.message ||
    a.toc.gps_ticks != b.toc.gps_ticks ||
    a.toe.gps_ticks != b.toe.gps_ticks ||
    a.toe_sow != b.toe_sow ||
    a.health != b.health ||
    a.clock.length() != b.clock.length() ||
    a.data.length() != b.data.length() {
    return false
  }
  for i in 0..<a.clock.length() {
    if a.clock[i] != b.clock[i] {
      return false
    }
  }
  for i in 0..<a.data.length() {
    if a.data[i] != b.data[i] {
      return false
    }
  }
  true
}

///|
fn catalog_rejection(error : NavError) -> (String, NavRejectionReason) {
  match error {
    EphemerisExpired => ("expired", NavRejectionReason::Expired)
    UnhealthyEphemeris => ("unhealthy", NavRejectionReason::Unhealthy)
    OrbitTypeRequired =>
      ("orbit-type-required", NavRejectionReason::OrbitChoiceRequired)
    InvalidNavigation(detail) =>
      ("invalid-model", NavRejectionReason::InvalidModel(detail))
    KeplerDivergence => ("non-convergence", NavRejectionReason::NonConvergence)
    UnsupportedConstellation(system) =>
      ("unsupported", NavRejectionReason::Unsupported(system))
  }
}

///|
/// Offline policy: nearest usable Toe in exact ticks, then latest Toc.
/// Equivalent ties retain the first source index; conflicting ties are explicit.
/// Reuses all propagation health/fit/age/GEO rules; no positioning or RF history.
pub fn NavCatalog::query(
  self : NavCatalog,
  satellite : String,
  at : NavTime,
  bds_orbit? : BdsOrbit,
  max_age_seconds? : Double = 7200.0,
) -> NavQueryOutcome raise CatalogError {
  if !satellite_ok(satellite) || !["G", "C"].contains(part(satellite, 0, 1)) {
    raise InvalidCatalogInput("query requires a GPS/BDS satellite identifier")
  }
  if max_age_seconds <= 0.0 ||
    max_age_seconds > 14400.0 ||
    max_age_seconds.is_nan() ||
    max_age_seconds.is_inf() {
    raise InvalidCatalogInput("max age must be finite in(0,14400]")
  }
  let indices = self.by_satellite.get(satellite).unwrap_or([])
  let counts : Map[String, Int] = Map([])
  let samples : Array[NavRejection] = []
  let mut rejected = 0
  let mut eligible = 0
  let mut best : (Int, SatPosition)? = None
  let mut best_distance = 0L
  let mut best_toc = 0L
  let ties : Array[Int] = []
  let mut tied_records = 0
  let mut conflicting = false
  for index in indices {
    let entry = self.entries[index]
    let state = Some(
      entry.record.satellite_position(at, bds_orbit?, max_age_seconds~),
    ) catch {
      error => {
        let (code, reason) = catalog_rejection(error)
        rejected += 1
        counts[code] = counts.get(code).unwrap_or(0) + 1
        if samples.length() < 128 {
          samples.push({ candidate: catalog_candidate(entry, index), reason, })
        }
        None
      }
    }
    if state is Some(position) {
      eligible += 1
      let distance = (at.gps_ticks - entry.record.toe.gps_ticks).abs()
      let toc = entry.record.toc.gps_ticks
      if best is None ||
        distance < best_distance ||
        (distance == best_distance && toc > best_toc) {
        best = Some((index, position))
        best_distance = distance
        best_toc = toc
        tied_records = 1
        conflicting = false
        ties.clear()
        ties.push(index)
      } else if distance == best_distance && toc == best_toc {
        tied_records += 1
        let same = catalog_same_record(
          entry.record,
          self.entries[ties[0]].record,
        )
        if ties.length() < 128 {
          ties.push(index)
        } else if !same && !conflicting {
          // Even after many duplicates, expose at least one conflicting model.
          ties[127] = index
        }
        if !same {
          conflicting = true
        }
      }
    }
  }
  let report : NavQueryReport = {
    satellite,
    at,
    candidates: indices.length(),
    eligible,
    rejected,
    rejection_counts: counts,
    rejection_samples: samples,
    omitted_rejections: rejected - samples.length(),
  }
  match best {
    None => Unavailable(report)
    Some((index, state)) =>
      if conflicting {
        NavQueryOutcome::Conflict({
          candidates: ties.map(i => catalog_candidate(self.entries[i], i)),
          tied_records,
          omitted_candidates: tied_records - ties.length(),
          report,
        })
      } else {
        Selected({
          record: catalog_candidate(self.entries[index], index),
          state,
          equivalent_records: tied_records,
          report,
        })
      }
  }
}

///|
pub extend CatalogError with @debug.Debug::{to_repr}

///|
pub extend NavRejectionReason with @debug.Debug::{to_repr}

///|
pub extend NavRejectionReason with ToJson::{to_json}

///|
pub extend NavCandidate with @debug.Debug::{to_repr}

///|
pub extend NavCandidate with ToJson::{to_json}

///|
pub extend NavRejection with @debug.Debug::{to_repr}

///|
pub extend NavRejection with ToJson::{to_json}

///|
pub extend NavQueryReport with @debug.Debug::{to_repr}

///|
pub extend NavQueryReport with ToJson::{to_json}

///|
pub extend NavSelection with @debug.Debug::{to_repr}

///|
pub extend NavSelection with ToJson::{to_json}

///|
pub extend NavAmbiguity with @debug.Debug::{to_repr}

///|
pub extend NavAmbiguity with ToJson::{to_json}

///|
pub extend NavQueryOutcome with @debug.Debug::{to_repr}

///|
pub extend NavQueryOutcome with ToJson::{to_json}
