// RINEX2.11TableA2 flag6 uses complete observation-format records, including continuations.

///|
test "deep cycle6-1sat-6types preserves normative slip continuation" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 02:00     CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     6    C1    L1    L2    D1    D2    S1                  # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  6  1G01", "                         2.000           3.000",
      "", "&26 10 27  0  1  0.0000000  0  1G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000",
    ] {
    for row in d.feed_line(line) {
      output.push(row)
    }
  }
  assert_true(d.finish().complete)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "     6    C1    L1    L2    D1    D2    S1                  # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  6  1G01", "                         2.000           3.000",
      "", " 26 10 27  0  1  0.0000000  0  1G01", "       100.000         101.000         102.000         103.000         104.000",
      "       105.000",
    ].join("\n"),
  )
  let legacy = LegacyReader::new()
  let mut slips : LegacyEpoch? = None
  for line in output {
    if legacy.feed_line(line) is Some(CycleSlip(e)) {
      slips = Some(e)
    }
  }
  legacy.finish()
  assert_eq(slips.unwrap().satellites.length(), 1)
  assert_eq(slips.unwrap().satellites[0].values[1].observation.value, Some(2.0))
}

///|
test "deep cycle6-13sat-13types preserves normative slip continuation" {
  let d = CrinexDecoder::new()
  let output : Array[String] = []
  for
    line in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 02:00     CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "    13    C1    L1    L2    D1    D2    S1    P1    P2    C2# / TYPES OF OBSERV",
      "          S2    C5    L5    D5                              # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  6 13G01G02G03G04G05G06G07G08G09G10G11G12", "                                G13",
      "                         2.000           3.000", "", "                        12.000",
      "                         4.000           6.000", "", "                        24.000",
      "                         6.000           9.000", "", "                        36.000",
      "                         8.000          12.000", "", "                        48.000",
      "                        10.000          15.000", "", "                        60.000",
      "                        12.000          18.000", "", "                        72.000",
      "                        14.000          21.000", "", "                        84.000",
      "                        16.000          24.000", "", "                        96.000",
      "                        18.000          27.000", "", "                       108.000",
      "                        20.000          30.000", "", "                       120.000",
      "                        22.000          33.000", "", "                       132.000",
      "                        24.000          36.000", "", "                       144.000",
      "                        26.000          39.000", "", "                       156.000",
      "&26 10 27  0  1  0.0000000  0  1G01", "", "3&100000 3&101000 3&102000 3&103000 3&104000 3&105000 3&106000 3&107000 3&108000 3&109000 3&110000 3&111000 3&112000",
    ] {
    for row in d.feed_line(line) {
      output.push(row)
    }
  }
  assert_true(d.finish().complete)
  assert_eq(
    output.join("\n"),
    [
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "    13    C1    L1    L2    D1    D2    S1    P1    P2    C2# / TYPES OF OBSERV",
      "          S2    C5    L5    D5                              # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  6 13G01G02G03G04G05G06G07G08G09G10G11G12", "                                G13",
      "                         2.000           3.000", "", "                        12.000",
      "                         4.000           6.000", "", "                        24.000",
      "                         6.000           9.000", "", "                        36.000",
      "                         8.000          12.000", "", "                        48.000",
      "                        10.000          15.000", "", "                        60.000",
      "                        12.000          18.000", "", "                        72.000",
      "                        14.000          21.000", "", "                        84.000",
      "                        16.000          24.000", "", "                        96.000",
      "                        18.000          27.000", "", "                       108.000",
      "                        20.000          30.000", "", "                       120.000",
      "                        22.000          33.000", "", "                       132.000",
      "                        24.000          36.000", "", "                       144.000",
      "                        26.000          39.000", "", "                       156.000",
      " 26 10 27  0  1  0.0000000  0  1G01", "       100.000         101.000         102.000         103.000         104.000",
      "       105.000         106.000         107.000         108.000         109.000",
      "       110.000         111.000         112.000",
    ].join("\n"),
  )
  let legacy = LegacyReader::new()
  let mut slips : LegacyEpoch? = None
  for line in output {
    if legacy.feed_line(line) is Some(CycleSlip(e)) {
      slips = Some(e)
    }
  }
  legacy.finish()
  assert_eq(slips.unwrap().satellites.length(), 13)
  assert_eq(slips.unwrap().satellites[0].values[1].observation.value, Some(2.0))
}
