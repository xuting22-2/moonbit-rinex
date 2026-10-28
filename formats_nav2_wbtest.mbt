///|
test "RTKLIB NAV2.11 GPS derived field-preserving input" {
  let reader = NavReader::new()
  let mut found : NavRecord? = None
  for
    line in [
      "     2.11           NAVIGATION DATA                         RINEX VERSION / TYPE",
      "                                                            END OF HEADER",
      " 1 26 10 25 14  0  0.0 1.418138854206e-04-8.412825991400e-12 0.000000000000e+00",
      "    3.700000000000e+01-1.262187500000e+02 4.773056172525e-09 1.308299615199e+00",
      "   -6.677582859993e-06 2.114486764185e-03 4.556030035019e-06 5.153739910126e+03",
      "    5.040000000000e+04 3.166496753693e-08-1.124321027501e+00 5.587935447693e-08",
      "    9.559016049330e-01 2.889687500000e+02 1.457963556091e-01-8.493925562902e-09",
      "   -4.089455996059e-10 1.000000000000e+00 2.442000000000e+03 0.000000000000e+00",
      "    2.000000000000e+00 0.000000000000e+00-8.847564458847e-09 3.700000000000e+01",
      "    4.314000000000e+04 0.000000000000e+00 0.000000000000e+00 0.000000000000e+00",
    ] {
    if reader.feed_line(line) is Some(record) {
      found = Some(record)
    }
  }
  reader.finish()
  let record = found.unwrap()
  let got = record.satellite_position(record.toe)
  assert_true((got.x - -14899401.736103931).abs() <= 0.00001)
  assert_true((got.y - 4296220.714971766).abs() <= 0.00001)
  assert_true((got.z - 21546562.403917465).abs() <= 0.00001)
  assert_true((got.clock_seconds - 0.00014180920715419274).abs() <= 1.0e-13)
}
