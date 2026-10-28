///|
test "deep CRX event count is not satellite count" {
  let input : Array[String] = [
    "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 01:58     CRINEX PROG / DATE",
    "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "G    1 L1C                                                  SYS / # / OBS TYPES",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "> 2026 10 27 00 00  0.0000000  4694",
  ]
  for _ in 0..<694 {
    input.push(
      "valid special record                                        COMMENT",
    )
  }
  for
    row in ["> 2026 10 27 00 01  0.0000000  0  1      G01", "", "3&-100000 &&"] {
    input.push(row)
  }
  let expected : Array[String] = [
    "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "G    1 L1C                                                  SYS / # / OBS TYPES",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "> 2026 10 27 00 00  0.0000000  4694",
  ]
  for _ in 0..<694 {
    expected.push(
      "valid special record                                        COMMENT",
    )
  }
  for row in ["> 2026 10 27 00 01  0.0000000  0  1", "G01      -100.000"] {
    expected.push(row)
  }
  let decoder = CrinexDecoder::new()
  let output : Array[String] = []
  for row in input {
    for line in decoder.feed_line(row) {
      output.push(line)
    }
  }
  let report = decoder.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(report.epochs, 1)
  assert_eq(output.join("\n"), expected.join("\n"))
}
