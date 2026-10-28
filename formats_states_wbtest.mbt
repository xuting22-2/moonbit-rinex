// Independent GSI4.2.0 decoding of event and differential-order inputs.

///|
test "GSI events-all state transitions" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       27-Oct-26 17:10     CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "3&-100000 &&", "> 2026 10 27 00 01  0.0000000  2  1",
      "event-2                                                     COMMENT", "> 2026 10 27 00 02  0.0000000  0  1      G01",
      "", "3&-101000 &&", "> 2026 10 27 00 03  0.0000000  3  1", "event-3                                                     MARKER NAME",
      "> 2026 10 27 00 04  0.0000000  0  1      G01", "", "3&-103000 &&", "> 2026 10 27 00 05  0.0000000  5  1",
      "event-5                                                     COMMENT", "> 2026 10 27 00 06  0.0000000  0  1      G01",
      "", "3&-105000 &&", "> 2026 10 27 00 07  0.0000000  6  1", "G01         2.000",
      "> 2026 10 27 00 08  0.0000000  0  1      G01", "", "3&-107000 &&",
    ] {
    for restored in d.feed_line(line) {
      output.push(restored)
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
      "> 2026 10 27 00 00  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 01  0.0000000  2  1",
      "event-2                                                     COMMENT", "> 2026 10 27 00 02  0.0000000  0  1",
      "G01      -101.000", "> 2026 10 27 00 03  0.0000000  3  1", "event-3                                                     MARKER NAME",
      "> 2026 10 27 00 04  0.0000000  0  1", "G01      -103.000", "> 2026 10 27 00 05  0.0000000  5  1",
      "event-5                                                     COMMENT", "> 2026 10 27 00 06  0.0000000  0  1",
      "G01      -105.000", "> 2026 10 27 00 07  0.0000000  6  1", "G01         2.000",
      "> 2026 10 27 00 08  0.0000000  0  1", "G01      -107.000",
    ].join("\n"),
  )
}

///|
test "GSI order-0 state transitions" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "ORIGINAL SYNTHETIC SPEC INPUT                               CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "0&-100000 & ", "                 1",
      "", "-99999", "                 2", "", "-99992", "                 3", "",
      "-99973", "                 4", "", "-99936", "                 5", "", "-99875",
      "                 6", "", "-99784", "                 7", "", "-99657",
    ] {
    for restored in d.feed_line(line) {
      output.push(restored)
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
      "> 2026 10 27 00 00  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 01  0.0000000  0  1",
      "G01       -99.999", "> 2026 10 27 00 02  0.0000000  0  1", "G01       -99.992",
      "> 2026 10 27 00 03  0.0000000  0  1", "G01       -99.973", "> 2026 10 27 00 04  0.0000000  0  1",
      "G01       -99.936", "> 2026 10 27 00 05  0.0000000  0  1", "G01       -99.875",
      "> 2026 10 27 00 06  0.0000000  0  1", "G01       -99.784", "> 2026 10 27 00 07  0.0000000  0  1",
      "G01       -99.657",
    ].join("\n"),
  )
}

///|
test "GSI order-1 state transitions" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "ORIGINAL SYNTHETIC SPEC INPUT                               CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "1&-100000 & ", "                 1",
      "", "1", "                 2", "", "7", "                 3", "", "19", "                 4",
      "", "37", "                 5", "", "61", "                 6", "", "91", "                 7",
      "", "127",
    ] {
    for restored in d.feed_line(line) {
      output.push(restored)
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
      "> 2026 10 27 00 00  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 01  0.0000000  0  1",
      "G01       -99.999", "> 2026 10 27 00 02  0.0000000  0  1", "G01       -99.992",
      "> 2026 10 27 00 03  0.0000000  0  1", "G01       -99.973", "> 2026 10 27 00 04  0.0000000  0  1",
      "G01       -99.936", "> 2026 10 27 00 05  0.0000000  0  1", "G01       -99.875",
      "> 2026 10 27 00 06  0.0000000  0  1", "G01       -99.784", "> 2026 10 27 00 07  0.0000000  0  1",
      "G01       -99.657",
    ].join("\n"),
  )
}

///|
test "GSI order-2 state transitions" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "ORIGINAL SYNTHETIC SPEC INPUT                               CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "2&-100000 & ", "                 1",
      "", "1", "                 2", "", "6", "                 3", "", "12", "                 4",
      "", "18", "                 5", "", "24", "                 6", "", "30", "                 7",
      "", "36",
    ] {
    for restored in d.feed_line(line) {
      output.push(restored)
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
      "> 2026 10 27 00 00  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 01  0.0000000  0  1",
      "G01       -99.999", "> 2026 10 27 00 02  0.0000000  0  1", "G01       -99.992",
      "> 2026 10 27 00 03  0.0000000  0  1", "G01       -99.973", "> 2026 10 27 00 04  0.0000000  0  1",
      "G01       -99.936", "> 2026 10 27 00 05  0.0000000  0  1", "G01       -99.875",
      "> 2026 10 27 00 06  0.0000000  0  1", "G01       -99.784", "> 2026 10 27 00 07  0.0000000  0  1",
      "G01       -99.657",
    ].join("\n"),
  )
}

///|
test "GSI order-3 state transitions" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "ORIGINAL SYNTHETIC SPEC INPUT                               CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "3&-100000 & ", "                 1",
      "", "1", "                 2", "", "6", "                 3", "", "6", "                 4",
      "", "6", "                 5", "", "6", "                 6", "", "6", "                 7",
      "", "6",
    ] {
    for restored in d.feed_line(line) {
      output.push(restored)
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
      "> 2026 10 27 00 00  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 01  0.0000000  0  1",
      "G01       -99.999", "> 2026 10 27 00 02  0.0000000  0  1", "G01       -99.992",
      "> 2026 10 27 00 03  0.0000000  0  1", "G01       -99.973", "> 2026 10 27 00 04  0.0000000  0  1",
      "G01       -99.936", "> 2026 10 27 00 05  0.0000000  0  1", "G01       -99.875",
      "> 2026 10 27 00 06  0.0000000  0  1", "G01       -99.784", "> 2026 10 27 00 07  0.0000000  0  1",
      "G01       -99.657",
    ].join("\n"),
  )
}

///|
test "GSI order-4 state transitions" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "ORIGINAL SYNTHETIC SPEC INPUT                               CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "4&-100000 & ", "                 1",
      "", "1", "                 2", "", "6", "                 3", "", "6", "                 4",
      "", "0", "                 5", "", "0", "                 6", "", "0", "                 7",
      "", "0",
    ] {
    for restored in d.feed_line(line) {
      output.push(restored)
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
      "> 2026 10 27 00 00  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 01  0.0000000  0  1",
      "G01       -99.999", "> 2026 10 27 00 02  0.0000000  0  1", "G01       -99.992",
      "> 2026 10 27 00 03  0.0000000  0  1", "G01       -99.973", "> 2026 10 27 00 04  0.0000000  0  1",
      "G01       -99.936", "> 2026 10 27 00 05  0.0000000  0  1", "G01       -99.875",
      "> 2026 10 27 00 06  0.0000000  0  1", "G01       -99.784", "> 2026 10 27 00 07  0.0000000  0  1",
      "G01       -99.657",
    ].join("\n"),
  )
}

///|
test "GSI order-5 state transitions" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "ORIGINAL SYNTHETIC SPEC INPUT                               CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 L1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "5&-100000 & ", "                 1",
      "", "1", "                 2", "", "6", "                 3", "", "6", "                 4",
      "", "0", "                 5", "", "0", "                 6", "", "0", "                 7",
      "", "0",
    ] {
    for restored in d.feed_line(line) {
      output.push(restored)
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
      "> 2026 10 27 00 00  0.0000000  0  1", "G01      -100.000", "> 2026 10 27 00 01  0.0000000  0  1",
      "G01       -99.999", "> 2026 10 27 00 02  0.0000000  0  1", "G01       -99.992",
      "> 2026 10 27 00 03  0.0000000  0  1", "G01       -99.973", "> 2026 10 27 00 04  0.0000000  0  1",
      "G01       -99.936", "> 2026 10 27 00 05  0.0000000  0  1", "G01       -99.875",
      "> 2026 10 27 00 06  0.0000000  0  1", "G01       -99.784", "> 2026 10 27 00 07  0.0000000  0  1",
      "G01       -99.657",
    ].join("\n"),
  )
}
