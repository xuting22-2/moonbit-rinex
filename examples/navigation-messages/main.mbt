///|
fn main {
  let reader = @r.NavigationReader::new()
  let lines = [
    "     4.02           NAVIGATION DATA     M                   RINEX VERSION / TYPE",
    "                                                            END OF HEADER",
    "> EPH R01 FDMA", "R01 2025 01 01 00 00 00 2.000000000000E-04 1.000000000000E-11 2.592000000000E+05",
    "     2.000000000000E+04-1.500000000000E+00 1.000000000000E-09 0.000000000000E+00",
    "     1.500000000000E+04 2.000000000000E+00 2.000000000000E-09-7.000000000000E+00",
    "     1.200000000000E+04 1.000000000000E+00-1.000000000000E-09 0.000000000000E+00",
    "     0.000000000000E+00 1.000000000000E-09 4.000000000000E+00 0.000000000000E+00",
  ]
  let mut record = None
  for line in lines {
    if (try! reader.feed_line(line)) is Some(m) {
      record = Some(m)
    }
  }
  ignore(try! reader.finish())
  let message = record.unwrap()
  try! assert_eq(reader.unsupported_records(), 0)
  try! assert_eq(message.value("frequency_channel"), Some(-7.0))
  let state = try! message.state_at_offset(600.0)
  try! assert_eq(state.frame, "PZ-90")
  println(state.to_json().stringify())
}
