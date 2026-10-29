///|
/// CSV projection of the existing modern OBS Reader. One completed epoch is
/// emitted at a time; every row remains provisional until finish succeeds.
pub struct ObservationCsvReader {
  priv reader : Reader
  priv mut epochs : Int
  priv mut satellite_records : Int
  priv mut observation_rows : Int
}

///|
/// Native input quality remains separate from successful table serialization.
pub struct ObservationCsvReport {
  input_report : Report
  epochs : Int
  satellite_records : Int
  observation_rows : Int
  rows : Int
} derive(ToJson, @debug.Debug)

///|
pub extend ObservationCsvReport with ToJson::{to_json}

///|
pub extend ObservationCsvReport with @debug.Debug::{to_repr}

///|
fn observation_csv_row(cells : Array[String]) -> String {
  cells.map(cell => "\"" + cell.replace(old="\"", new="\"\"") + "\"").join(",")
}

///|
/// Fixed long-table schema; all cells are quoted, records use LF in file hosts.
pub fn observation_csv_columns() -> String {
  observation_csv_row([
    "row_kind", "epoch_index", "gps_ticks", "epoch_flag", "source_line", "satellite",
    "observation_code", "source_column", "raw_field", "value_text", "lli", "ssi",
    "receiver_clock_raw",
  ])
}

///|
/// Whole input, existing OBS versions/GPS time/flags0..1; no extra corrections.
pub fn ObservationCsvReader::new() -> ObservationCsvReader raise CheckError {
  {
    reader: Reader::new(),
    epochs: 0,
    satellite_records: 0,
    observation_rows: 0,
  }
}

///|
pub fn ObservationCsvReader::header(
  self : ObservationCsvReader,
) -> ObservationHeader? {
  self.reader.header()
}

///|
/// Always emit an epoch marker, even when no satellite observations are present.
/// value_text uses the original numeric lexeme, not a Double reformatting.
pub fn ObservationCsvReader::feed_line(
  self : ObservationCsvReader,
  line : String,
) -> Array[String] raise CheckError {
  guard self.reader.feed_line(line) is Some(epoch) else { return [] }
  self.epochs += 1
  let index = self.epochs.to_string()
  let ticks = epoch.gps_ticks.to_string()
  let flag = epoch.flag.to_string()
  let rows = [
    observation_csv_row([
      "epoch",
      index,
      ticks,
      flag,
      epoch.line.to_string(),
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      epoch.receiver_clock_raw,
    ]),
  ]
  for satellite in epoch.satellites {
    self.satellite_records += 1
    for value in satellite.observations {
      self.observation_rows += 1
      rows.push(
        observation_csv_row([
          "observation",
          index,
          ticks,
          flag,
          satellite.line.to_string(),
          satellite.satellite,
          value.code,
          value.column.to_string(),
          value.raw_field,
          trimmed(value.raw_field, 0, 14),
          match value.lli {
            Some(lli) => lli.to_string()
            None => ""
          },
          match value.ssi {
            Some(ssi) => ssi.to_string()
            None => ""
          },
          "",
        ]),
      )
    }
  }
  rows
}

///|
pub fn ObservationCsvReader::finish(
  self : ObservationCsvReader,
) -> ObservationCsvReport raise CheckError {
  let input_report = self.reader.finish()
  {
    input_report,
    epochs: self.epochs,
    satellite_records: self.satellite_records,
    observation_rows: self.observation_rows,
    rows: self.epochs + self.observation_rows,
  }
}
