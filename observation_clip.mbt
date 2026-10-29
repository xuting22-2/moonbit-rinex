///|
/// A raw time-window RINEX writer over the existing Reader. Body lines remain
/// provisional until full source finish and successful file delivery.
pub struct ObservationClipper {
  priv reader : Reader
  priv gps_range : (Int64, Int64)
  priv mut epochs : Int
  priv mut records : Int
  priv mut first_raw : String?
  priv mut last_raw : String?
  priv mut first_ticks : Int64?
  priv mut last_ticks : Int64?
}

///|
pub struct ObservationClipReport {
  input_report : Report
  gps_range : (Int64, Int64)
  selected_epochs : Int
  selected_satellite_records : Int
  first_gps_ticks : Int64?
  last_gps_ticks : Int64?
  output_header : Array[String]?
  omitted_summary_lines : Int
} derive(ToJson, @debug.Debug)

///|
pub extend ObservationClipReport with ToJson::{to_json}

///|
pub extend ObservationClipReport with @debug.Debug::{to_repr}

///|
pub fn ObservationClipper::new(
  start : Int64,
  stop : Int64,
) -> ObservationClipper raise CheckError {
  {
    reader: Reader::new(gps_range=(start, stop)),
    gps_range: (start, stop),
    epochs: 0,
    records: 0,
    first_raw: None,
    last_raw: None,
    first_ticks: None,
    last_ticks: None,
  }
}

///|
pub fn ObservationClipper::header(
  self : ObservationClipper,
) -> ObservationHeader? {
  self.reader.header()
}

///|
/// Preserve every selected raw epoch/satellite character, including missing
/// trailing fields, zero-satellite epochs and receiver-clock spelling.
pub fn ObservationClipper::feed_line(
  self : ObservationClipper,
  line : String,
) -> Array[String] raise CheckError {
  guard self.reader.feed_line(line) is Some(epoch) else { return [] }
  self.epochs += 1
  self.records += epoch.satellites.length()
  if self.first_raw is None {
    self.first_raw = Some(epoch.raw_record)
    self.first_ticks = Some(epoch.gps_ticks)
  }
  self.last_raw = Some(epoch.raw_record)
  self.last_ticks = Some(epoch.gps_ticks)
  let rows = [epoch.raw_record]
  for satellite in epoch.satellites {
    rows.push(satellite.raw_record)
  }
  rows
}

///|
// The calendar fields have already passed Reader validation. Keep their GPS
// date, format seconds with integer100ns arithmetic, never through Double/UTC.
fn clipped_time_header(raw : String, label : String) -> String raise CheckError {
  let b = StringBuilder()
  for (start, stop) in [(2, 6), (7, 9), (10, 12), (13, 15), (16, 18)] {
    b.write_string(left_pad(digits(part(raw, start, stop)).to_string(), 6))
  }
  let ticks = seconds_ticks(part(raw, 18, 29))
  let fraction = (ticks % 10000000L).to_string()
  let seconds = StringBuilder()
  seconds.write_string((ticks / 10000000L).to_string())
  seconds.write_string(".")
  for _ in fraction.length()..<7 {
    seconds.write_string("0")
  }
  seconds.write_string(fraction)
  b.write_string(left_pad(seconds.to_string(), 13))
  b.write_string("     GPS")
  right_pad(b.to_string(), 60) + right_pad(label, 20)
}

///|
/// Only an acceptable WHOLE source and a nonempty selected epoch sequence get
/// a proposed output header. Optional original dataset totals are omitted;
/// existing first/last extents are replaced, absent optional last is not added.
pub fn ObservationClipper::finish(
  self : ObservationClipper,
) -> ObservationClipReport raise CheckError {
  let input_report = self.reader.finish()
  let mut omitted = 0
  let output_header = if input_report.acceptable &&
    self.first_raw is Some(first) &&
    self.last_raw is Some(last) {
    let source = self.reader.header().unwrap().raw_lines
    let header : Array[String] = []
    for line in source {
      match trimmed(line, 60, 80) {
        "# OF SATELLITES" | "PRN / # OF OBS" => omitted += 1
        "TIME OF FIRST OBS" =>
          header.push(clipped_time_header(first, "TIME OF FIRST OBS"))
        "TIME OF LAST OBS" =>
          header.push(clipped_time_header(last, "TIME OF LAST OBS"))
        _ => header.push(line)
      }
    }
    Some(header)
  } else {
    None
  }
  {
    input_report,
    gps_range: self.gps_range,
    selected_epochs: self.epochs,
    selected_satellite_records: self.records,
    first_gps_ticks: self.first_ticks,
    last_gps_ticks: self.last_ticks,
    output_header,
    omitted_summary_lines: omitted,
  }
}
