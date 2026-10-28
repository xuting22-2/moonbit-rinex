// Synthetic GSI4.2.0 inputs/outputs; corruption removes a required type continuation.

///|
test "max06 v1-initial-header type declaration remains complete" {
  let valid = [
    "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:10     CRINEX PROG / DATE",
    "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "    10    C1    L1    D1    S1    P1    P2    C2    L2    D2# / TYPES OF OBSERV",
    "          S2                                                # / TYPES OF OBSERV",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "&26 10 27  0  0  0.0000000  0  1G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000",
  ]
  let bad = [
    "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:10     CRINEX PROG / DATE",
    "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "    10    C1    L1    D1    S1    P1    P2    C2    L2    D2# / TYPES OF OBSERV",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "&26 10 27  0  0  0.0000000  0  1G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000",
  ]
  let decoder = CrinexDecoder::new()
  let output : Array[String] = []
  for row in valid {
    for line in decoder.feed_line(row) {
      output.push(line)
    }
  }
  let report = decoder.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "    10    C1    L1    D1    S1    P1    P2    C2    L2    D2# / TYPES OF OBSERV",
      "          S2                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01", "       100.000         101.000         102.000         103.000         104.000",
      "       105.000         106.000         107.000         108.000         109.000",
    ].join("\n"),
  )
  for recover in [false, true] {
    let broken = CrinexDecoder::new(recover~)
    let failed = try {
      for row in bad {
        ignore(broken.feed_line(row))
      }
      ignore(broken.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "crx-types"
    }
    assert_true(failed)
    assert_true(
      try {
        ignore(broken.feed_line(""))
        false
      } catch {
        Rejected(code, _, _) => code == "state"
      },
    )
  }
}

///|
test "max06 v1-event-update type declaration remains complete" {
  let valid = [
    "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:10     CRINEX PROG / DATE",
    "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "     1    C1                                                # / TYPES OF OBSERV",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "&26 10 27  0  0  0.0000000  0  1G01", "", "3&100000", "&26 10 27  0  1  0.0000000  4  2",
    "    10    C1    L1    D1    S1    P1    P2    C2    L2    D2# / TYPES OF OBSERV",
    "          S2                                                # / TYPES OF OBSERV",
    "&26 10 27  0  2  0.0000000  0  1G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000",
  ]
  let bad = [
    "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:10     CRINEX PROG / DATE",
    "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "     1    C1                                                # / TYPES OF OBSERV",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "&26 10 27  0  0  0.0000000  0  1G01", "", "3&100000", "&26 10 27  0  1  0.0000000  4  1",
    "    10    C1    L1    D1    S1    P1    P2    C2    L2    D2# / TYPES OF OBSERV",
    "&26 10 27  0  2  0.0000000  0  1G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000",
  ]
  let decoder = CrinexDecoder::new()
  let output : Array[String] = []
  for row in valid {
    for line in decoder.feed_line(row) {
      output.push(line)
    }
  }
  let report = decoder.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     1    C1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01", "       100.000", " 26 10 27  0  1  0.0000000  4  2",
      "    10    C1    L1    D1    S1    P1    P2    C2    L2    D2# / TYPES OF OBSERV",
      "          S2                                                # / TYPES OF OBSERV",
      " 26 10 27  0  2  0.0000000  0  1G01", "       100.000         101.000         102.000         103.000         104.000",
      "       105.000         106.000         107.000         108.000         109.000",
    ].join("\n"),
  )
  for recover in [false, true] {
    let broken = CrinexDecoder::new(recover~)
    let failed = try {
      for row in bad {
        ignore(broken.feed_line(row))
      }
      ignore(broken.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "crx-types"
    }
    assert_true(failed)
    assert_true(
      try {
        ignore(broken.feed_line(""))
        false
      } catch {
        Rejected(code, _, _) => code == "state"
      },
    )
  }
}

///|
test "max06 v3-initial-header type declaration remains complete" {
  let valid = [
    "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:10     CRINEX PROG / DATE",
    "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "G   14 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I  SYS / # / OBS TYPES",
    "       L5I                                                  SYS / # / OBS TYPES",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000 3&110000 3&111000 3&112000 3&113000 &&&&&&&&&&&&&&&&&&&&&&&&&&&&",
  ]
  let bad = [
    "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:10     CRINEX PROG / DATE",
    "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "G   14 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I  SYS / # / OBS TYPES",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000 3&110000 3&111000 3&112000 3&113000 &&&&&&&&&&&&&&&&&&&&&&&&&&&&",
  ]
  let decoder = CrinexDecoder::new()
  let output : Array[String] = []
  for row in valid {
    for line in decoder.feed_line(row) {
      output.push(line)
    }
  }
  let report = decoder.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G   14 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I  SYS / # / OBS TYPES",
      "       L5I                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1", "G01       100.000         101.000         102.000         103.000         104.000         105.000         106.000         107.000         108.000         109.000         110.000         111.000         112.000         113.000",
    ].join("\n"),
  )
  for recover in [false, true] {
    let broken = CrinexDecoder::new(recover~)
    let failed = try {
      for row in bad {
        ignore(broken.feed_line(row))
      }
      ignore(broken.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "crx-types"
    }
    assert_true(failed)
    assert_true(
      try {
        ignore(broken.feed_line(""))
        false
      } catch {
        Rejected(code, _, _) => code == "state"
      },
    )
  }
}

///|
test "max06 v3-event-update type declaration remains complete" {
  let valid = [
    "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:10     CRINEX PROG / DATE",
    "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "G    1 C1C                                                  SYS / # / OBS TYPES",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "3&100000 &&", "> 2026 10 27 00 01  0.0000000  4  2",
    "G   14 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I  SYS / # / OBS TYPES",
    "       L5I                                                  SYS / # / OBS TYPES",
    "> 2026 10 27 00 02  0.0000000  0  1      G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000 3&110000 3&111000 3&112000 3&113000 &&&&&&&&&&&&&&&&&&&&&&&&&&&&",
  ]
  let bad = [
    "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
    "RNX2CRX ver.4.2.0                       28-Oct-26 05:10     CRINEX PROG / DATE",
    "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "G    1 C1C                                                  SYS / # / OBS TYPES",
    "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "                                                            END OF HEADER",
    "> 2026 10 27 00 00  0.0000000  0  1      G01", "", "3&100000 &&", "> 2026 10 27 00 01  0.0000000  4  1",
    "G   14 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I  SYS / # / OBS TYPES",
    "> 2026 10 27 00 02  0.0000000  0  1      G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000 3&110000 3&111000 3&112000 3&113000 &&&&&&&&&&&&&&&&&&&&&&&&&&&&",
  ]
  let decoder = CrinexDecoder::new()
  let output : Array[String] = []
  for row in valid {
    for line in decoder.feed_line(row) {
      output.push(line)
    }
  }
  let report = decoder.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "G    1 C1C                                                  SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  1", "G01       100.000", "> 2026 10 27 00 01  0.0000000  4  2",
      "G   14 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I  SYS / # / OBS TYPES",
      "       L5I                                                  SYS / # / OBS TYPES",
      "> 2026 10 27 00 02  0.0000000  0  1", "G01       100.000         101.000         102.000         103.000         104.000         105.000         106.000         107.000         108.000         109.000         110.000         111.000         112.000         113.000",
    ].join("\n"),
  )
  for recover in [false, true] {
    let broken = CrinexDecoder::new(recover~)
    let failed = try {
      for row in bad {
        ignore(broken.feed_line(row))
      }
      ignore(broken.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "crx-types"
    }
    assert_true(failed)
    assert_true(
      try {
        ignore(broken.feed_line(""))
        false
      } catch {
        Rejected(code, _, _) => code == "state"
      },
    )
  }
}

///|
test "max06 complete three-row GPS declaration followed by GLONASS" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    row in [
      "3.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 05:13     CRINEX PROG / DATE",
      "     3.04           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
      "G   27 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I  SYS / # / OBS TYPES",
      "       L5I D5I S5I C5Q L5Q D5Q S5Q C5X L5X D5X S5X C2L L2L  SYS / # / OBS TYPES",
      "       D2L                                                  SYS / # / OBS TYPES",
      "R    2 C1C L1C                                              SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  2      G01R01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000 3&110000 3&111000 3&112000 3&113000 3&114000 3&115000 3&116000 3&117000 3&118000 3&119000 3&120000 3&121000 3&122000 3&123000 3&124000 3&125000 3&126000 &&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&",
      "3&200000 3&201000 &&&&",
    ] {
    for line in d.feed_line(row) {
      output.push(line)
    }
  }
  let report = d.finish()
  assert_true(report.complete && report.acceptable)
  assert_eq(report.epochs, 1)
  assert_eq(
    output.join("\n"),
    [
      "     3.04           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
      "G   27 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I  SYS / # / OBS TYPES",
      "       L5I D5I S5I C5Q L5Q D5Q S5Q C5X L5X D5X S5X C2L L2L  SYS / # / OBS TYPES",
      "       D2L                                                  SYS / # / OBS TYPES",
      "R    2 C1C L1C                                              SYS / # / OBS TYPES",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "> 2026 10 27 00 00  0.0000000  0  2", "G01       100.000         101.000         102.000         103.000         104.000         105.000         106.000         107.000         108.000         109.000         110.000         111.000         112.000         113.000         114.000         115.000         116.000         117.000         118.000         119.000         120.000         121.000         122.000         123.000         124.000         125.000         126.000",
      "R01       200.000         201.000",
    ].join("\n"),
  )
}
