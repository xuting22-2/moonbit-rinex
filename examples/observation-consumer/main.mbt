///|
fn main raise {
  let range = @r.Window::epn_daily(2026, 9, 23)
  let reader = @r.Reader::new(gps_range=(range.start, range.start + 600000000L))
  let epochs : Array[@r.ObservationEpoch] = []
  for line in fixture() {
    if reader.feed_line(line) is Some(epoch) {
      epochs.push(epoch)
    }
  }
  let report = reader.finish()
  let result : Json = {
    "header": reader.header().unwrap().to_json(),
    "epochs": epochs.to_json(),
    "report": report.to_json(),
  }
  println(result.stringify())
}
