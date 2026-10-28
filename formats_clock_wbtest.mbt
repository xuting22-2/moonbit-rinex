///|
test "GSI clock ramp and steady order3" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       27-Oct-26 17:11     CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "3&123456789012", "3&-100000 &&",
      "                 1", "1", "1000", "                 2", "6", "0", "                 3",
      "6", "0", "                 4", "6", "0", "                 5", "6", "0", "                 6",
      "6", "0", "                 7", "6", "0",
    ] {
    for row in d.feed_line(line) {
      output.push(row)
    }
  }
  assert_true(d.finish().complete)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1        .123456789012", "G01      -100.000",
      "> 2026 10 27 00 01  0.0000000  0  1        .123456789013", "G01       -99.000",
      "> 2026 10 27 00 02  0.0000000  0  1        .123456789020", "G01       -98.000",
      "> 2026 10 27 00 03  0.0000000  0  1        .123456789039", "G01       -97.000",
      "> 2026 10 27 00 04  0.0000000  0  1        .123456789076", "G01       -96.000",
      "> 2026 10 27 00 05  0.0000000  0  1        .123456789137", "G01       -95.000",
      "> 2026 10 27 00 06  0.0000000  0  1        .123456789228", "G01       -94.000",
      "> 2026 10 27 00 07  0.0000000  0  1        .123456789355", "G01       -93.000",
    ].join("\n"),
  )
}
