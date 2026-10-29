///|
extern "js" fn fail_csv_reader(message : String) -> @r.ObservationCsvReader =
  #| (message) => { throw new Error(message); }

///|
pub fn csv_create() -> @r.ObservationCsvReader {
  @r.ObservationCsvReader::new() catch {
    error => fail_csv_reader(@debug.to_string(error))
  }
}

///|
pub fn csv_columns() -> String {
  @r.observation_csv_columns()
}

///|
pub fn csv_feed(reader : @r.ObservationCsvReader, line : String) -> String {
  reader.feed_line(line).to_json().stringify() catch {
    error => {
      fail(@debug.to_string(error))
      ""
    }
  }
}

///|
pub fn csv_header(reader : @r.ObservationCsvReader) -> String {
  match reader.header() {
    Some(header) => header.to_json().stringify()
    None => "null"
  }
}

///|
pub fn csv_finish(reader : @r.ObservationCsvReader) -> String {
  reader.finish().to_json().stringify() catch {
    error => {
      fail(@debug.to_string(error))
      ""
    }
  }
}
