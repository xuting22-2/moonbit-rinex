// GSI4.2.0 reference outputs except the explicitly normative zero-SV clock case.
// ManualCRX3 inputs use required && initial blank flag text.

///|
test "deep first-empty-epoch GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 01:53     CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  0", "", "                 1                1      G01",
      "", "3&-100000 &&",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  0", "> 2026 10 27 00 01  0.0000000  0  1",
      "G01      -100.000",
    ].join("\n"),
  )
}

///|
// RINEX3.04 Table A3 requires six reserved columns before F15.12.
// GSI4.2.0 omits those columns for the short first zero-SV descriptor.
test "deep clock-zero-satellites normative reserved columns" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 01:53     CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  0", "3&123456", "                 1                1      G01",
      "1", "3&-100000 &&",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  0        .000000123456", "> 2026 10 27 00 01  0.0000000  0  1        .000000123457",
      "G01      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v1-order0-gap GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  1G01", "0&-12345678", "0&-100000 ", "              1",
      "-12345677", "0&-100000 ", "              2", "-12345670", "0&-100000 ", "              3",
      "-12345651", "0&-100000 ", "              4", "-12345614", "0&-100000 ", "              5",
      "-12345553", "0&-100000 ", "              6", "-12345462", "0&-100000 ", "              7",
      "-12345335", "0&-100000 ", "              8", "", "0&-100000 ", "              9",
      "0&-12344949", "0&-100000 ", "             10", "-12344678", "0&-100000 ",
      "              1", "-12344347", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01                                  -.012345678",
      "      -100.000", " 26 10 27  0  1  0.0000000  0  1G01                                  -.012345677",
      "      -100.000", " 26 10 27  0  2  0.0000000  0  1G01                                  -.012345670",
      "      -100.000", " 26 10 27  0  3  0.0000000  0  1G01                                  -.012345651",
      "      -100.000", " 26 10 27  0  4  0.0000000  0  1G01                                  -.012345614",
      "      -100.000", " 26 10 27  0  5  0.0000000  0  1G01                                  -.012345553",
      "      -100.000", " 26 10 27  0  6  0.0000000  0  1G01                                  -.012345462",
      "      -100.000", " 26 10 27  0  7  0.0000000  0  1G01                                  -.012345335",
      "      -100.000", " 26 10 27  0  8  0.0000000  0  1G01", "      -100.000",
      " 26 10 27  0  9  0.0000000  0  1G01                                  -.012344949",
      "      -100.000", " 26 10 27  0 10  0.0000000  0  1G01                                  -.012344678",
      "      -100.000", " 26 10 27  0 11  0.0000000  0  1G01                                  -.012344347",
      "      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v1-order1-gap GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  1G01", "1&-12345678", "0&-100000 ", "              1",
      "1", "0&-100000 ", "              2", "7", "0&-100000 ", "              3",
      "19", "0&-100000 ", "              4", "37", "0&-100000 ", "              5",
      "61", "0&-100000 ", "              6", "91", "0&-100000 ", "              7",
      "127", "0&-100000 ", "              8", "", "0&-100000 ", "              9",
      "1&-12344949", "0&-100000 ", "             10", "271", "0&-100000 ", "              1",
      "331", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01                                  -.012345678",
      "      -100.000", " 26 10 27  0  1  0.0000000  0  1G01                                  -.012345677",
      "      -100.000", " 26 10 27  0  2  0.0000000  0  1G01                                  -.012345670",
      "      -100.000", " 26 10 27  0  3  0.0000000  0  1G01                                  -.012345651",
      "      -100.000", " 26 10 27  0  4  0.0000000  0  1G01                                  -.012345614",
      "      -100.000", " 26 10 27  0  5  0.0000000  0  1G01                                  -.012345553",
      "      -100.000", " 26 10 27  0  6  0.0000000  0  1G01                                  -.012345462",
      "      -100.000", " 26 10 27  0  7  0.0000000  0  1G01                                  -.012345335",
      "      -100.000", " 26 10 27  0  8  0.0000000  0  1G01", "      -100.000",
      " 26 10 27  0  9  0.0000000  0  1G01                                  -.012344949",
      "      -100.000", " 26 10 27  0 10  0.0000000  0  1G01                                  -.012344678",
      "      -100.000", " 26 10 27  0 11  0.0000000  0  1G01                                  -.012344347",
      "      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v1-order2-gap GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  1G01", "2&-12345678", "0&-100000 ", "              1",
      "1", "0&-100000 ", "              2", "6", "0&-100000 ", "              3",
      "12", "0&-100000 ", "              4", "18", "0&-100000 ", "              5",
      "24", "0&-100000 ", "              6", "30", "0&-100000 ", "              7",
      "36", "0&-100000 ", "              8", "", "0&-100000 ", "              9",
      "2&-12344949", "0&-100000 ", "             10", "271", "0&-100000 ", "              1",
      "60", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01                                  -.012345678",
      "      -100.000", " 26 10 27  0  1  0.0000000  0  1G01                                  -.012345677",
      "      -100.000", " 26 10 27  0  2  0.0000000  0  1G01                                  -.012345670",
      "      -100.000", " 26 10 27  0  3  0.0000000  0  1G01                                  -.012345651",
      "      -100.000", " 26 10 27  0  4  0.0000000  0  1G01                                  -.012345614",
      "      -100.000", " 26 10 27  0  5  0.0000000  0  1G01                                  -.012345553",
      "      -100.000", " 26 10 27  0  6  0.0000000  0  1G01                                  -.012345462",
      "      -100.000", " 26 10 27  0  7  0.0000000  0  1G01                                  -.012345335",
      "      -100.000", " 26 10 27  0  8  0.0000000  0  1G01", "      -100.000",
      " 26 10 27  0  9  0.0000000  0  1G01                                  -.012344949",
      "      -100.000", " 26 10 27  0 10  0.0000000  0  1G01                                  -.012344678",
      "      -100.000", " 26 10 27  0 11  0.0000000  0  1G01                                  -.012344347",
      "      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v1-order3-gap GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  1G01", "3&-12345678", "0&-100000 ", "              1",
      "1", "0&-100000 ", "              2", "6", "0&-100000 ", "              3",
      "6", "0&-100000 ", "              4", "6", "0&-100000 ", "              5",
      "6", "0&-100000 ", "              6", "6", "0&-100000 ", "              7",
      "6", "0&-100000 ", "              8", "", "0&-100000 ", "              9",
      "3&-12344949", "0&-100000 ", "             10", "271", "0&-100000 ", "              1",
      "60", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01                                  -.012345678",
      "      -100.000", " 26 10 27  0  1  0.0000000  0  1G01                                  -.012345677",
      "      -100.000", " 26 10 27  0  2  0.0000000  0  1G01                                  -.012345670",
      "      -100.000", " 26 10 27  0  3  0.0000000  0  1G01                                  -.012345651",
      "      -100.000", " 26 10 27  0  4  0.0000000  0  1G01                                  -.012345614",
      "      -100.000", " 26 10 27  0  5  0.0000000  0  1G01                                  -.012345553",
      "      -100.000", " 26 10 27  0  6  0.0000000  0  1G01                                  -.012345462",
      "      -100.000", " 26 10 27  0  7  0.0000000  0  1G01                                  -.012345335",
      "      -100.000", " 26 10 27  0  8  0.0000000  0  1G01", "      -100.000",
      " 26 10 27  0  9  0.0000000  0  1G01                                  -.012344949",
      "      -100.000", " 26 10 27  0 10  0.0000000  0  1G01                                  -.012344678",
      "      -100.000", " 26 10 27  0 11  0.0000000  0  1G01                                  -.012344347",
      "      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v1-order4-gap GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  1G01", "4&-12345678", "0&-100000 ", "              1",
      "1", "0&-100000 ", "              2", "6", "0&-100000 ", "              3",
      "6", "0&-100000 ", "              4", "0", "0&-100000 ", "              5",
      "0", "0&-100000 ", "              6", "0", "0&-100000 ", "              7",
      "0", "0&-100000 ", "              8", "", "0&-100000 ", "              9",
      "4&-12344949", "0&-100000 ", "             10", "271", "0&-100000 ", "              1",
      "60", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01                                  -.012345678",
      "      -100.000", " 26 10 27  0  1  0.0000000  0  1G01                                  -.012345677",
      "      -100.000", " 26 10 27  0  2  0.0000000  0  1G01                                  -.012345670",
      "      -100.000", " 26 10 27  0  3  0.0000000  0  1G01                                  -.012345651",
      "      -100.000", " 26 10 27  0  4  0.0000000  0  1G01                                  -.012345614",
      "      -100.000", " 26 10 27  0  5  0.0000000  0  1G01                                  -.012345553",
      "      -100.000", " 26 10 27  0  6  0.0000000  0  1G01                                  -.012345462",
      "      -100.000", " 26 10 27  0  7  0.0000000  0  1G01                                  -.012345335",
      "      -100.000", " 26 10 27  0  8  0.0000000  0  1G01", "      -100.000",
      " 26 10 27  0  9  0.0000000  0  1G01                                  -.012344949",
      "      -100.000", " 26 10 27  0 10  0.0000000  0  1G01                                  -.012344678",
      "      -100.000", " 26 10 27  0 11  0.0000000  0  1G01                                  -.012344347",
      "      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v1-order5-gap GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  1G01", "5&-12345678", "0&-100000 ", "              1",
      "1", "0&-100000 ", "              2", "6", "0&-100000 ", "              3",
      "6", "0&-100000 ", "              4", "0", "0&-100000 ", "              5",
      "0", "0&-100000 ", "              6", "0", "0&-100000 ", "              7",
      "0", "0&-100000 ", "              8", "", "0&-100000 ", "              9",
      "5&-12344949", "0&-100000 ", "             10", "271", "0&-100000 ", "              1",
      "60", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    L1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01                                  -.012345678",
      "      -100.000", " 26 10 27  0  1  0.0000000  0  1G01                                  -.012345677",
      "      -100.000", " 26 10 27  0  2  0.0000000  0  1G01                                  -.012345670",
      "      -100.000", " 26 10 27  0  3  0.0000000  0  1G01                                  -.012345651",
      "      -100.000", " 26 10 27  0  4  0.0000000  0  1G01                                  -.012345614",
      "      -100.000", " 26 10 27  0  5  0.0000000  0  1G01                                  -.012345553",
      "      -100.000", " 26 10 27  0  6  0.0000000  0  1G01                                  -.012345462",
      "      -100.000", " 26 10 27  0  7  0.0000000  0  1G01                                  -.012345335",
      "      -100.000", " 26 10 27  0  8  0.0000000  0  1G01", "      -100.000",
      " 26 10 27  0  9  0.0000000  0  1G01                                  -.012344949",
      "      -100.000", " 26 10 27  0 10  0.0000000  0  1G01                                  -.012344678",
      "      -100.000", " 26 10 27  0 11  0.0000000  0  1G01                                  -.012344347",
      "      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v3-order0-gap-valid-flags GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "0&-12345678", "0&-100000 &&",
      "                 1", "-12345677", "0&-100000 ", "                 2", "-12345670",
      "0&-100000 ", "                 3", "-12345651", "0&-100000 ", "                 4",
      "-12345614", "0&-100000 ", "                 5", "-12345553", "0&-100000 ",
      "                 6", "-12345462", "0&-100000 ", "                 7", "-12345335",
      "0&-100000 ", "                 8", "", "0&-100000 ", "                 9",
      "0&-12344949", "0&-100000 ", "                10", "-12344678", "0&-100000 ",
      "                 1", "-12344347", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1       -.000012345678", "G01      -100.000",
      "> 2026 10 27 00 01  0.0000000  0  1       -.000012345677", "G01      -100.000",
      "> 2026 10 27 00 02  0.0000000  0  1       -.000012345670", "G01      -100.000",
      "> 2026 10 27 00 03  0.0000000  0  1       -.000012345651", "G01      -100.000",
      "> 2026 10 27 00 04  0.0000000  0  1       -.000012345614", "G01      -100.000",
      "> 2026 10 27 00 05  0.0000000  0  1       -.000012345553", "G01      -100.000",
      "> 2026 10 27 00 06  0.0000000  0  1       -.000012345462", "G01      -100.000",
      "> 2026 10 27 00 07  0.0000000  0  1       -.000012345335", "G01      -100.000",
      "> 2026 10 27 00 08  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 09  0.0000000  0  1       -.000012344949",
      "G01      -100.000", "> 2026 10 27 00 10  0.0000000  0  1       -.000012344678",
      "G01      -100.000", "> 2026 10 27 00 11  0.0000000  0  1       -.000012344347",
      "G01      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v3-order1-gap-valid-flags GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "1&-12345678", "0&-100000 &&",
      "                 1", "1", "0&-100000 ", "                 2", "7", "0&-100000 ",
      "                 3", "19", "0&-100000 ", "                 4", "37", "0&-100000 ",
      "                 5", "61", "0&-100000 ", "                 6", "91", "0&-100000 ",
      "                 7", "127", "0&-100000 ", "                 8", "", "0&-100000 ",
      "                 9", "1&-12344949", "0&-100000 ", "                10", "271",
      "0&-100000 ", "                 1", "331", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1       -.000012345678", "G01      -100.000",
      "> 2026 10 27 00 01  0.0000000  0  1       -.000012345677", "G01      -100.000",
      "> 2026 10 27 00 02  0.0000000  0  1       -.000012345670", "G01      -100.000",
      "> 2026 10 27 00 03  0.0000000  0  1       -.000012345651", "G01      -100.000",
      "> 2026 10 27 00 04  0.0000000  0  1       -.000012345614", "G01      -100.000",
      "> 2026 10 27 00 05  0.0000000  0  1       -.000012345553", "G01      -100.000",
      "> 2026 10 27 00 06  0.0000000  0  1       -.000012345462", "G01      -100.000",
      "> 2026 10 27 00 07  0.0000000  0  1       -.000012345335", "G01      -100.000",
      "> 2026 10 27 00 08  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 09  0.0000000  0  1       -.000012344949",
      "G01      -100.000", "> 2026 10 27 00 10  0.0000000  0  1       -.000012344678",
      "G01      -100.000", "> 2026 10 27 00 11  0.0000000  0  1       -.000012344347",
      "G01      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v3-order2-gap-valid-flags GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "2&-12345678", "0&-100000 &&",
      "                 1", "1", "0&-100000 ", "                 2", "6", "0&-100000 ",
      "                 3", "12", "0&-100000 ", "                 4", "18", "0&-100000 ",
      "                 5", "24", "0&-100000 ", "                 6", "30", "0&-100000 ",
      "                 7", "36", "0&-100000 ", "                 8", "", "0&-100000 ",
      "                 9", "2&-12344949", "0&-100000 ", "                10", "271",
      "0&-100000 ", "                 1", "60", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1       -.000012345678", "G01      -100.000",
      "> 2026 10 27 00 01  0.0000000  0  1       -.000012345677", "G01      -100.000",
      "> 2026 10 27 00 02  0.0000000  0  1       -.000012345670", "G01      -100.000",
      "> 2026 10 27 00 03  0.0000000  0  1       -.000012345651", "G01      -100.000",
      "> 2026 10 27 00 04  0.0000000  0  1       -.000012345614", "G01      -100.000",
      "> 2026 10 27 00 05  0.0000000  0  1       -.000012345553", "G01      -100.000",
      "> 2026 10 27 00 06  0.0000000  0  1       -.000012345462", "G01      -100.000",
      "> 2026 10 27 00 07  0.0000000  0  1       -.000012345335", "G01      -100.000",
      "> 2026 10 27 00 08  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 09  0.0000000  0  1       -.000012344949",
      "G01      -100.000", "> 2026 10 27 00 10  0.0000000  0  1       -.000012344678",
      "G01      -100.000", "> 2026 10 27 00 11  0.0000000  0  1       -.000012344347",
      "G01      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v3-order3-gap-valid-flags GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "3&-12345678", "0&-100000 &&",
      "                 1", "1", "0&-100000 ", "                 2", "6", "0&-100000 ",
      "                 3", "6", "0&-100000 ", "                 4", "6", "0&-100000 ",
      "                 5", "6", "0&-100000 ", "                 6", "6", "0&-100000 ",
      "                 7", "6", "0&-100000 ", "                 8", "", "0&-100000 ",
      "                 9", "3&-12344949", "0&-100000 ", "                10", "271",
      "0&-100000 ", "                 1", "60", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1       -.000012345678", "G01      -100.000",
      "> 2026 10 27 00 01  0.0000000  0  1       -.000012345677", "G01      -100.000",
      "> 2026 10 27 00 02  0.0000000  0  1       -.000012345670", "G01      -100.000",
      "> 2026 10 27 00 03  0.0000000  0  1       -.000012345651", "G01      -100.000",
      "> 2026 10 27 00 04  0.0000000  0  1       -.000012345614", "G01      -100.000",
      "> 2026 10 27 00 05  0.0000000  0  1       -.000012345553", "G01      -100.000",
      "> 2026 10 27 00 06  0.0000000  0  1       -.000012345462", "G01      -100.000",
      "> 2026 10 27 00 07  0.0000000  0  1       -.000012345335", "G01      -100.000",
      "> 2026 10 27 00 08  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 09  0.0000000  0  1       -.000012344949",
      "G01      -100.000", "> 2026 10 27 00 10  0.0000000  0  1       -.000012344678",
      "G01      -100.000", "> 2026 10 27 00 11  0.0000000  0  1       -.000012344347",
      "G01      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v3-order4-gap-valid-flags GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "4&-12345678", "0&-100000 &&",
      "                 1", "1", "0&-100000 ", "                 2", "6", "0&-100000 ",
      "                 3", "6", "0&-100000 ", "                 4", "0", "0&-100000 ",
      "                 5", "0", "0&-100000 ", "                 6", "0", "0&-100000 ",
      "                 7", "0", "0&-100000 ", "                 8", "", "0&-100000 ",
      "                 9", "4&-12344949", "0&-100000 ", "                10", "271",
      "0&-100000 ", "                 1", "60", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1       -.000012345678", "G01      -100.000",
      "> 2026 10 27 00 01  0.0000000  0  1       -.000012345677", "G01      -100.000",
      "> 2026 10 27 00 02  0.0000000  0  1       -.000012345670", "G01      -100.000",
      "> 2026 10 27 00 03  0.0000000  0  1       -.000012345651", "G01      -100.000",
      "> 2026 10 27 00 04  0.0000000  0  1       -.000012345614", "G01      -100.000",
      "> 2026 10 27 00 05  0.0000000  0  1       -.000012345553", "G01      -100.000",
      "> 2026 10 27 00 06  0.0000000  0  1       -.000012345462", "G01      -100.000",
      "> 2026 10 27 00 07  0.0000000  0  1       -.000012345335", "G01      -100.000",
      "> 2026 10 27 00 08  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 09  0.0000000  0  1       -.000012344949",
      "G01      -100.000", "> 2026 10 27 00 10  0.0000000  0  1       -.000012344678",
      "G01      -100.000", "> 2026 10 27 00 11  0.0000000  0  1       -.000012344347",
      "G01      -100.000",
    ].join("\n"),
  )
}

///|
test "deep clock-v3-order5-gap-valid-flags GSI golden" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "DEEP REPAIR SYNTHETIC CLOCK SERIES                          CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "5&-12345678", "0&-100000 &&",
      "                 1", "1", "0&-100000 ", "                 2", "6", "0&-100000 ",
      "                 3", "6", "0&-100000 ", "                 4", "0", "0&-100000 ",
      "                 5", "0", "0&-100000 ", "                 6", "0", "0&-100000 ",
      "                 7", "0", "0&-100000 ", "                 8", "", "0&-100000 ",
      "                 9", "5&-12344949", "0&-100000 ", "                10", "271",
      "0&-100000 ", "                 1", "60", "0&-100000 ",
    ] {
    for s in d.feed_line(row) {
      output.push(s)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1       -.000012345678", "G01      -100.000",
      "> 2026 10 27 00 01  0.0000000  0  1       -.000012345677", "G01      -100.000",
      "> 2026 10 27 00 02  0.0000000  0  1       -.000012345670", "G01      -100.000",
      "> 2026 10 27 00 03  0.0000000  0  1       -.000012345651", "G01      -100.000",
      "> 2026 10 27 00 04  0.0000000  0  1       -.000012345614", "G01      -100.000",
      "> 2026 10 27 00 05  0.0000000  0  1       -.000012345553", "G01      -100.000",
      "> 2026 10 27 00 06  0.0000000  0  1       -.000012345462", "G01      -100.000",
      "> 2026 10 27 00 07  0.0000000  0  1       -.000012345335", "G01      -100.000",
      "> 2026 10 27 00 08  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 09  0.0000000  0  1       -.000012344949",
      "G01      -100.000", "> 2026 10 27 00 10  0.0000000  0  1       -.000012344678",
      "G01      -100.000", "> 2026 10 27 00 11  0.0000000  0  1       -.000012344347",
      "G01      -100.000",
    ].join("\n"),
  )
}
