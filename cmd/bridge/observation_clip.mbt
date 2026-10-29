///|
extern "js" fn fail_clipper(message : String) -> @r.ObservationClipper =
  #| (message) => { throw new Error(message); }

///|
fn make_clipper(input : String) -> @r.ObservationClipper raise {
  if input.length() > 4096 {
    raise Failure("clip range JSON limit")
  }
  guard @json.parse(input) is Json::Array([start, stop]) else {
    raise Failure("clip range requires two decimal tick strings")
  }
  @r.ObservationClipper::new(exact_tick(start), exact_tick(stop))
}

///|
pub fn clip_create(input : String) -> @r.ObservationClipper {
  make_clipper(input) catch {
    error => fail_clipper(@debug.to_string(error))
  }
}

///|
pub fn clip_feed(clipper : @r.ObservationClipper, line : String) -> String {
  clipper.feed_line(line).to_json().stringify() catch {
    error => {
      fail(@debug.to_string(error))
      ""
    }
  }
}

///|
pub fn clip_header(clipper : @r.ObservationClipper) -> String {
  match clipper.header() {
    Some(header) => header.to_json().stringify()
    None => "null"
  }
}

///|
pub fn clip_finish(clipper : @r.ObservationClipper) -> String {
  clipper.finish().to_json().stringify() catch {
    error => {
      fail(@debug.to_string(error))
      ""
    }
  }
}
