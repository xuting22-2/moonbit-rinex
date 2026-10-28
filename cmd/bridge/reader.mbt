///|
extern "js" fn fail_reader(message : String) -> @r.Reader =
  #| (message) => { throw new Error(message); }

///|
fn exact_tick(value : Json) -> Int64 raise {
  guard value is String(text) else {
    raise Failure("GPS ticks must be decimal strings")
  }
  if text.is_empty() ||
    text.length() > 17 ||
    text.iter().any(c => c < '0' || c > '9') {
    raise Failure("GPS ticks must be bounded unsigned decimal strings")
  }
  @strconv.parse_int64(text[:])
}

///|
fn make_reader(options : String) -> @r.Reader raise {
  if options.length() > 4096 {
    raise Failure("reader options exceed 4096 characters")
  }
  guard @json.parse(options) is Object(object) else {
    raise Failure("reader options must be object")
  }
  let range = match object.get("gps_range") {
    None | Some(Null) => None
    Some(Array([start, stop])) => Some((exact_tick(start), exact_tick(stop)))
    _ => raise Failure("gps_range must contain two decimal tick strings")
  }
  @r.Reader::new(gps_range?=range)
}

///|
pub fn reader_create(options : String) -> @r.Reader {
  make_reader(options) catch {
    e => fail_reader(@debug.to_string(e))
  }
}

///|
pub fn reader_feed(reader : @r.Reader, line : String) -> String {
  try {
    match reader.feed_line(line) {
      Some(epoch) => epoch.to_json().stringify()
      None => "null"
    }
  } catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
pub fn reader_header(reader : @r.Reader) -> String {
  match reader.header() {
    Some(header) => header.to_json().stringify()
    None => "null"
  }
}

///|
pub fn reader_finish(reader : @r.Reader) -> String {
  reader.finish().to_json().stringify() catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}
