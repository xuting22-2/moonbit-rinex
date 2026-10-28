// Derived legal-grid week-boundary parameters independently read/evaluated byRTKLIB2.4.3b34.

///|
test "deep GPS-crossweek independent RTKLIB" {
  let reader = NavReader::new()
  let mut found : NavRecord? = None
  for
    line in [
      "     3.05           NAVIGATION DATA     MIXED               RINEX VERSION / TYPE",
      "                                                            END OF HEADER",
      "G01 2026 10 31 23 59 44 1.418138854206e-04-8.412825991400e-12 0.000000000000e+00",
      "     3.700000000000e+01-1.262187500000e+02 4.773056172525e-09 1.308299615199e+00",
      "    -6.677582859993e-06 2.114486764185e-03 4.556030035019e-06 5.153739910126e+03",
      "     6.047840000000E+05 3.166496753693e-08-1.124321027501e+00 5.587935447693e-08",
      "     9.559016049330e-01 2.889687500000e+02 1.457963556091e-01-8.493925562902e-09",
      "    -4.089455996059e-10 1.000000000000e+00 2.442000000000E+03 0.000000000000e+00",
      "     2.000000000000e+00 0.000000000000e+00-8.847564458847e-09 3.700000000000e+01",
      "     4.314000000000e+04 0.000000000000e+00 0.000000000000e+00 0.000000000000e+00",
    ] {
    if reader.feed_line(line) is Some(record) {
      found = Some(record)
    }
  }
  reader.finish()
  let record = found.unwrap()
  let eval_time = NavTime::week(2443, 1.0)
  assert_eq(eval_time.gps_ticks, record.toe.offset_seconds(17).gps_ticks)
  let state = record.satellite_position(eval_time, bds_orbit=MEO_IGSO)
  assert_true((state.x - 15353811.795007987).abs() <= 0.00001)
  assert_true((state.y - 2110637.927645754).abs() <= 0.00001)
  assert_true((state.z - 21552653.498528074).abs() <= 0.00001)
  assert_true((state.clock_seconds - 0.0001418090610574505).abs() <= 1.0e-13)
}

///|
test "deep BDT-crossweek independent RTKLIB" {
  let reader = NavReader::new()
  let mut found : NavRecord? = None
  for
    line in [
      "     3.05           NAVIGATION DATA     MIXED               RINEX VERSION / TYPE",
      "                                                            END OF HEADER",
      "C06 2026 10 31 23 59 52 3.155331360176e-04 1.841193864038e-12 0.000000000000e+00",
      "     1.000000000000e+00-1.544843750000e+02-6.785996764513e-11-2.945287506452e+00",
      "    -5.343463271856e-06 2.767161931843e-03 3.764731809497e-05 6.493880092621e+03",
      "     6.047920000000E+05-3.143213689327e-07 5.107289566539e-02 3.105960786343e-07",
      "     1.028303670644e+00-8.925156250000e+02-2.391625055298e+00-1.248266268128e-09",
      "     8.721791622257e-10 0.000000000000e+00 1.086000000000E+03 0.000000000000e+00",
      "     2.000000000000e+00 0.000000000000e+00 2.299999968258e-09 2.299999968258e-09",
      "     7.200000000000e+04 1.000000000000e+00 0.000000000000e+00 0.000000000000e+00",
    ] {
    if reader.feed_line(line) is Some(record) {
      found = Some(record)
    }
  }
  reader.finish()
  let record = found.unwrap()
  let eval_time = NavTime::week(2443, 15.0)
  assert_eq(eval_time.gps_ticks, record.toe.offset_seconds(9).gps_ticks)
  let state = record.satellite_position(eval_time, bds_orbit=MEO_IGSO)
  assert_true((state.x - 25906186.082304154).abs() <= 0.00001)
  assert_true((state.y - 15946548.404324835).abs() <= 0.00001)
  assert_true((state.z - 29370114.20294979).abs() <= 0.00001)
  assert_true((state.clock_seconds - 0.00031553471066412376).abs() <= 1.0e-13)
}
