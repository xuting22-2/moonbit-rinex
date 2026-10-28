// Project-authored synthetic controls; independent GSI4.2.0 expected outputs.

///|
fn max07_restore(
  input : Array[String],
  recover? : Bool = false,
) -> (Array[String], CrinexReport) raise CheckError {
  let d = CrinexDecoder::new(recover~)
  let output : Array[String] = []
  for line in input {
    for row in d.feed_line(line) {
      output.push(row)
    }
  }
  (output, d.finish())
}

///|
test "max07 legacy spellings preserve GSI arcs" {
  {
    let (output, report) = max07_restore([
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA                        RINEX VERSION / TYPE",
      "SYNTHETIC ID CONTROL                                        MARKER NAME",
      "     1    C1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  2  1 02", "", "3&100000", "3&110000", "              1                  02 &1",
      "", "1000", "1000",
    ])
    assert_true(report.complete && report.acceptable)
    assert_eq(
      output.join("\n"),
      [
        "     2.11           OBSERVATION DATA                        RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        " 26 10 27  0  0  0.0000000  0  2  1 02", "       100.000", "       110.000",
        " 26 10 27  0  1  0.0000000  0  2 02  1", "       111.000", "       101.000",
      ].join("\n"),
    )
    let reader = LegacyReader::new()
    let epochs : Array[LegacyEpoch] = []
    for row in output {
      if reader.feed_line(row) is Some(Epoch(e)) {
        epochs.push(e)
      }
    }
    reader.finish()
    assert_eq(epochs.length(), 2)
    assert_eq(epochs[0].satellites[0].values[0].observation.value, Some(100.0))
  }
  {
    let (output, report) = max07_restore([
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "SYNTHETIC ID CONTROL                                        MARKER NAME",
      "     1    C1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  2G 1G02", "", "3&100000", "3&110000", "              1                  02 &1",
      "", "1000", "1000",
    ])
    assert_true(report.complete && report.acceptable)
    assert_eq(
      output.join("\n"),
      [
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        " 26 10 27  0  0  0.0000000  0  2G 1G02", "       100.000", "       110.000",
        " 26 10 27  0  1  0.0000000  0  2G02G 1", "       111.000", "       101.000",
      ].join("\n"),
    )
    let reader = LegacyReader::new()
    let epochs : Array[LegacyEpoch] = []
    for row in output {
      if reader.feed_line(row) is Some(Epoch(e)) {
        epochs.push(e)
      }
    }
    reader.finish()
    assert_eq(epochs.length(), 2)
    assert_eq(epochs[0].satellites[0].values[0].observation.value, Some(100.0))
  }
  let (output, report) = max07_restore([
    "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
    "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
    "SYNTHETIC ID CONTROL                                        MARKER NAME", "     1    C1                                                # / TYPES OF OBSERV",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "&26 10 27  0  0  0.0000000  0  4G 1R 1E01S20", "", "3&100000", "3&110000", "3&120000",
    "3&130000", "              1                 S20E0 R& G&1", "", "1000", "1000",
    "1000", "1000",
  ])
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
      "SYNTHETIC ID CONTROL                                        MARKER NAME",
      "     1    C1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  4G 1R 1E01S20", "       100.000", "       110.000",
      "       120.000", "       130.000", " 26 10 27  0  1  0.0000000  0  4S20E01R 1G 1",
      "       131.000", "       121.000", "       111.000", "       101.000",
    ].join("\n"),
  )
  let reader = LegacyReader::new()
  let epochs : Array[LegacyEpoch] = []
  for row in output {
    if reader.feed_line(row) is Some(Epoch(e)) {
      epochs.push(e)
    }
  }
  reader.finish()
  assert_eq(epochs.length(), 2)
  assert_eq(epochs[0].satellites[0].values[0].observation.value, Some(100.0))
}

///|
test "max07 modern seven-system IDs preserve GSI" {
  {
    let (output, report) = max07_restore([
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
      "SYNTHETIC ID CONTROL                                        MARKER NAME",
      "G    1 C1C                                                  SYS / # / OBS TYPES",
      "R    1 C1C                                                  SYS / # / OBS TYPES",
      "E    1 C1C                                                  SYS / # / OBS TYPES",
      "C    1 C2I                                                  SYS / # / OBS TYPES",
      "J    1 C1C                                                  SYS / # / OBS TYPES",
      "I    1 C5A                                                  SYS / # / OBS TYPES",
      "S    1 C1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  7      G01R01E01C01J01I01S20", "", "3&100000 &&",
      "3&110000 &&", "3&120000 &&", "3&130000 &&", "3&140000 &&", "3&150000 &&",
      "3&160000 &&", "                 1                       S20I  J     E  R  G01",
      "", "1000", "1000", "1000", "1000", "1000", "1000", "1000",
    ])
    assert_true(report.complete && report.acceptable)
    assert_eq(
      output.join("\n"),
      [
        "     3.04           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "G    1 C1C                                                  SYS / # / OBS TYPES",
        "R    1 C1C                                                  SYS / # / OBS TYPES",
        "E    1 C1C                                                  SYS / # / OBS TYPES",
        "C    1 C2I                                                  SYS / # / OBS TYPES",
        "J    1 C1C                                                  SYS / # / OBS TYPES",
        "I    1 C5A                                                  SYS / # / OBS TYPES",
        "S    1 C1C                                                  SYS / # / OBS TYPES",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "> 2026 10 27 00 00  0.0000000  0  7", "G01       100.000", "R01       110.000",
        "E01       120.000", "C01       130.000", "J01       140.000", "I01       150.000",
        "S20       160.000", "> 2026 10 27 00 01  0.0000000  0  7", "S20       161.000",
        "I01       151.000", "J01       141.000", "C01       131.000", "E01       121.000",
        "R01       111.000", "G01       101.000",
      ].join("\n"),
    )
    let reader = Reader::new()
    for row in output {
      ignore(reader.feed_line(row))
    }
    assert_true(reader.finish().complete)
  }
  let (output, report) = max07_restore([
    "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
    "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
    "SYNTHETIC ID CONTROL                                        MARKER NAME", "G    1 C1C                                                  SYS / # / OBS TYPES",
    "R    1 C1C                                                  SYS / # / OBS TYPES",
    "E    1 C1C                                                  SYS / # / OBS TYPES",
    "C    1 C2I                                                  SYS / # / OBS TYPES",
    "J    1 C1C                                                  SYS / # / OBS TYPES",
    "I    1 C5A                                                  SYS / # / OBS TYPES",
    "S    1 C1C                                                  SYS / # / OBS TYPES",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "> 2026 10 27 00 00  0.0000000  0  7      G01R01E01C01J01I01S20", "", "3&100000 &&",
    "3&110000 &&", "3&120000 &&", "3&130000 &&", "3&140000 &&", "3&150000 &&", "3&160000 &&",
    "                 1                       S20I  J     E  R  G01", "", "1000",
    "1000", "1000", "1000", "1000", "1000", "1000",
  ])
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
      "SYNTHETIC ID CONTROL                                        MARKER NAME",
      "G    1 C1C                                                  SYS / # / OBS TYPES",
      "R    1 C1C                                                  SYS / # / OBS TYPES",
      "E    1 C1C                                                  SYS / # / OBS TYPES",
      "C    1 C2I                                                  SYS / # / OBS TYPES",
      "J    1 C1C                                                  SYS / # / OBS TYPES",
      "I    1 C5A                                                  SYS / # / OBS TYPES",
      "S    1 C1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  7", "G01       100.000", "R01       110.000",
      "E01       120.000", "C01       130.000", "J01       140.000", "I01       150.000",
      "S20       160.000", "> 2026 10 27 00 01  0.0000000  0  7", "S20       161.000",
      "I01       151.000", "J01       141.000", "C01       131.000", "E01       121.000",
      "R01       111.000", "G01       101.000",
    ].join("\n"),
  )
  let reader = Reader::new()
  for row in output {
    ignore(reader.feed_line(row))
  }
  assert_true(reader.finish().complete)
}

///|
test "max07 invalid and aliased normal descriptor IDs poison" {
  for
    input in [
      [
        "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "G    1 C1C                                                  SYS / # / OBS TYPES",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "> 2026 10 27 00 00  0.0000000  0  1      G00", "", "3&100000 &&",
      ],
      [
        "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "G    1 C1C                                                  SYS / # / OBS TYPES",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "> 2026 10 27 00 00  0.0000000  0  1      Gx1", "", "3&100000 &&",
      ],
      [
        "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "G    1 C1C                                                  SYS / # / OBS TYPES",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "> 2026 10 27 00 00  0.0000000  0  1      G 1", "", "3&100000 &&",
      ],
      [
        "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "&26 10 27  0  0  0.0000000  0  2G00G02", "", "3&100000", "3&110000",
      ],
      [
        "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "&26 10 27  0  0  0.0000000  0  2Gx1G02", "", "3&100000", "3&110000",
      ],
      [
        "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "&26 10 27  0  0  0.0000000  0  2G01G 1", "", "3&100000", "3&110000",
      ],
      [
        "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "&26 10 27  0  0  0.0000000  0  2G01 01", "", "3&100000", "3&110000",
      ],
      [
        "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "&26 10 27  0  0  0.0000000  0  2  1G02", "", "3&100000", "3&110000",
      ],
    ] {
    for recover in [false, true] {
      let d = CrinexDecoder::new(recover~)
      let rejected = try {
        for row in input {
          ignore(d.feed_line(row))
        }
        ignore(d.finish())
        false
      } catch {
        Rejected(code, _, _) => code == "crx-satellite"
      }
      assert_true(rejected)
      assert_true(
        try {
          ignore(d.finish())
          false
        } catch {
          Rejected(code, _, _) => code == "state"
        },
      )
    }
  }
}

///|
test "max07 recovery validates skipped descriptors and retains loss policy" {
  let (output, report) = max07_restore(
    [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "SYNTHETIC ID CONTROL                                        MARKER NAME",
      "G    1 C1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "3&100000 &&", "                 1",
      "", "bad", "                 2", "", "0", "> 2026 10 27 00 03  0.0000000  0  1      G01",
      "", "3&103000 &&",
    ],
    recover=true,
  )
  assert_true(!report.complete && !report.acceptable)
  assert_eq(report.epochs, 2)
  assert_eq(report.recovered_epochs, 1)
  assert_eq(report.findings.length(), 1)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "SYNTHETIC ID CONTROL                                        MARKER NAME",
      "G    1 C1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1", "G01       100.000", "> 2026 10 27 00 03  0.0000000  0  1",
      "G01       103.000",
    ].join("\n"),
  )
  let d = CrinexDecoder::new(recover=true)
  let failed = try {
    for
      row in [
        "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:42     CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC ID CONTROL                                        MARKER NAME",
        "G    1 C1C                                                  SYS / # / OBS TYPES",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "3&100000 &&", "                 1",
        "", "bad", "                 2                       G00", "", "0", "> 2026 10 27 00 03  0.0000000  0  1      G01",
        "", "3&103000 &&",
      ] {
      ignore(d.feed_line(row))
    }
    ignore(d.finish())
    false
  } catch {
    Rejected(code, _, _) => code == "crx-satellite"
  }
  assert_true(failed)
  assert_true(
    try {
      ignore(d.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
}
