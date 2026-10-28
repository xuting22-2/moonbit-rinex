// Synthetic header-system updates independently restored byGSI4.2.0.

///|
test "max08 header system updates drive satellite and default time interpretation" {
  {
    let initial = "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE"
    let d = CrinexDecoder::new()
    let restored : Array[String] = []
    for
      row in [
        "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:59     CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
        "SYNTHETIC HEADER STATE                                      MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "&26 10 27  0  0  0.0000000  0  1G01", "", "3&100000", "&26 10 27  0  1  0.0000000  4  1",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "&26 10 27  0  2  0.0000000  0  1  1", "", "3&200000",
      ] {
      for line in d.feed_line(row) {
        restored.push(line)
      }
    }
    assert_true(d.finish().complete)
    assert_eq(
      restored.join("\n"),
      [
        "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
        "SYNTHETIC HEADER STATE                                      MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        " 26 10 27  0  0  0.0000000  0  1G01", "       100.000", " 26 10 27  0  1  0.0000000  4  1",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        " 26 10 27  0  2  0.0000000  0  1  1", "       200.000",
      ].join("\n"),
    )
    let reader = LegacyReader::new()
    let epochs : Array[LegacyEpoch] = []
    let events : Array[LegacyEvent] = []
    for row in restored {
      match reader.feed_line(row) {
        Some(Epoch(e)) => epochs.push(e)
        Some(Event(e)) => events.push(e)
        _ => ()
      }
    }
    reader.finish()
    assert_eq(epochs.length(), 2)
    assert_eq(epochs[1].satellites[0].satellite, "G01")
    assert_eq(epochs[1].satellites[0].values[0].observation.value, Some(200.0))
    assert_eq(epochs[1].gps_ticks, epochs[0].gps_ticks + 1200000000L)
    assert_eq(events.length(), 1)
    assert_eq(events[0].flag, 4)
    assert_eq(reader.header()[0], initial)
  }
  {
    let initial = "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE"
    let d = CrinexDecoder::new()
    let restored : Array[String] = []
    for
      row in [
        "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:59     CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
        "SYNTHETIC HEADER STATE                                      MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "&26 10 27  0  0  0.0000000  0  1G01", "", "3&100000", "&26 10 27  0  1  0.0000000  4  2",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "  2026    10    27     0     0    0.0000000                 TIME OF FIRST OBS",
        "&26 10 27  0  2  0.0000000  0  1  1", "", "3&200000",
      ] {
      for line in d.feed_line(row) {
        restored.push(line)
      }
    }
    assert_true(d.finish().complete)
    assert_eq(
      restored.join("\n"),
      [
        "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
        "SYNTHETIC HEADER STATE                                      MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        " 26 10 27  0  0  0.0000000  0  1G01", "       100.000", " 26 10 27  0  1  0.0000000  4  2",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "  2026    10    27     0     0    0.0000000                 TIME OF FIRST OBS",
        " 26 10 27  0  2  0.0000000  0  1  1", "       200.000",
      ].join("\n"),
    )
    let reader = LegacyReader::new()
    let epochs : Array[LegacyEpoch] = []
    let events : Array[LegacyEvent] = []
    for row in restored {
      match reader.feed_line(row) {
        Some(Epoch(e)) => epochs.push(e)
        Some(Event(e)) => events.push(e)
        _ => ()
      }
    }
    reader.finish()
    assert_eq(epochs.length(), 2)
    assert_eq(epochs[1].satellites[0].satellite, "G01")
    assert_eq(epochs[1].satellites[0].values[0].observation.value, Some(200.0))
    assert_eq(epochs[1].gps_ticks, epochs[0].gps_ticks + 1200000000L)
    assert_eq(events.length(), 1)
    assert_eq(events[0].flag, 4)
    assert_eq(reader.header()[0], initial)
  }
  {
    let initial = "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE"
    let d = CrinexDecoder::new()
    let restored : Array[String] = []
    for
      row in [
        "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
        "RNX2CRX ver.4.2.0                       28-Oct-26 05:59     CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC HEADER STATE                                      MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        "&26 10 27  0  0  0.0000000  0  1G01", "", "3&100000", "&26 10 27  0  1  0.0000000  4  1",
        "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
        "&26 10 27  0  2  0.0000000  0  2G01R01", "", "3&200000", "3&201000",
      ] {
      for line in d.feed_line(row) {
        restored.push(line)
      }
    }
    assert_true(d.finish().complete)
    assert_eq(
      restored.join("\n"),
      [
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC HEADER STATE                                      MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        " 26 10 27  0  0  0.0000000  0  1G01", "       100.000", " 26 10 27  0  1  0.0000000  4  1",
        "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
        " 26 10 27  0  2  0.0000000  0  2G01R01", "       200.000", "       201.000",
      ].join("\n"),
    )
    let reader = LegacyReader::new()
    let epochs : Array[LegacyEpoch] = []
    let events : Array[LegacyEvent] = []
    for row in restored {
      match reader.feed_line(row) {
        Some(Epoch(e)) => epochs.push(e)
        Some(Event(e)) => events.push(e)
        _ => ()
      }
    }
    reader.finish()
    assert_eq(epochs.length(), 2)
    assert_eq(epochs[1].satellites[0].satellite, "G01")
    assert_eq(epochs[1].satellites[0].values[0].observation.value, Some(200.0))
    assert_eq(epochs[1].gps_ticks, epochs[0].gps_ticks + 1200000000L)
    assert_eq(events.length(), 1)
    assert_eq(events[0].flag, 4)
    assert_eq(reader.header()[0], initial)
  }
  let initial = "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE"
  let d = CrinexDecoder::new()
  let restored : Array[String] = []
  for
    row in [
      "1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE",
      "RNX2CRX ver.4.2.0                       28-Oct-26 06:01     CRINEX PROG / DATE",
      "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
      "SYNTHETIC HEADER STATE                                      MARKER NAME",
      "     1    C1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      "&26 10 27  0  0  0.0000000  0  1G01", "", "3&100000", "&26 10 27  0  1  0.0000000  3  2",
      "SYNTHETIC SITE B                                            MARKER NAME",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      "&26 10 27  0  2  0.0000000  0  1  1", "", "3&200000",
    ] {
    for line in d.feed_line(row) {
      restored.push(line)
    }
  }
  assert_true(d.finish().complete)
  assert_eq(
    restored.join("\n"),
    [
      "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
      "SYNTHETIC HEADER STATE                                      MARKER NAME",
      "     1    C1                                                # / TYPES OF OBSERV",
      "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
      "                                                            END OF HEADER",
      " 26 10 27  0  0  0.0000000  0  1G01", "       100.000", " 26 10 27  0  1  0.0000000  3  2",
      "SYNTHETIC SITE B                                            MARKER NAME",
      "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
      " 26 10 27  0  2  0.0000000  0  1  1", "       200.000",
    ].join("\n"),
  )
  let reader = LegacyReader::new()
  let epochs : Array[LegacyEpoch] = []
  let events : Array[LegacyEvent] = []
  for row in restored {
    match reader.feed_line(row) {
      Some(Epoch(e)) => epochs.push(e)
      Some(Event(e)) => events.push(e)
      _ => ()
    }
  }
  reader.finish()
  assert_eq(epochs.length(), 2)
  assert_eq(epochs[1].satellites[0].satellite, "G01")
  assert_eq(epochs[1].satellites[0].values[0].observation.value, Some(200.0))
  assert_eq(epochs[1].gps_ticks, epochs[0].gps_ticks + 1200000000L)
  assert_eq(events.length(), 1)
  assert_eq(events[0].flag, 3)
  assert_eq(reader.header()[0], initial)
}

///|
test "max08 blank satellite systems cannot infer nonGPS identity" {
  {
    let reader = LegacyReader::new()
    let rejected = try {
      for
        row in [
          "     2.11           OBSERVATION DATA    R                   RINEX VERSION / TYPE",
          "SYNTHETIC HEADER STATE                                      MARKER NAME",
          "     1    C1                                                # / TYPES OF OBSERV",
          "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "                                                            END OF HEADER",
          " 26 10 27  0  0  0.0000000  0  1  1", "       100.000",
        ] {
        ignore(reader.feed_line(row))
      }
      reader.finish()
      false
    } catch {
      Rejected(code, _, _) => code == "legacy-satellite"
    }
    assert_true(rejected)
    assert_true(
      try {
        reader.finish()
        false
      } catch {
        Rejected(code, _, _) => code == "state"
      },
    )
  }
  {
    let reader = LegacyReader::new()
    let rejected = try {
      for
        row in [
          "     2.11           OBSERVATION DATA    E                   RINEX VERSION / TYPE",
          "SYNTHETIC HEADER STATE                                      MARKER NAME",
          "     1    C1                                                # / TYPES OF OBSERV",
          "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "                                                            END OF HEADER",
          " 26 10 27  0  0  0.0000000  0  1  1", "       100.000",
        ] {
        ignore(reader.feed_line(row))
      }
      reader.finish()
      false
    } catch {
      Rejected(code, _, _) => code == "legacy-satellite"
    }
    assert_true(rejected)
    assert_true(
      try {
        reader.finish()
        false
      } catch {
        Rejected(code, _, _) => code == "state"
      },
    )
  }
  let reader = LegacyReader::new()
  let rejected = try {
    for
      row in [
        "     2.11           OBSERVATION DATA    S                   RINEX VERSION / TYPE",
        "SYNTHETIC HEADER STATE                                      MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        " 26 10 27  0  0  0.0000000  0  1  1", "       100.000",
      ] {
      ignore(reader.feed_line(row))
    }
    reader.finish()
    false
  } catch {
    Rejected(code, _, _) => code == "legacy-satellite"
  }
  assert_true(rejected)
  assert_true(
    try {
      reader.finish()
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
}

///|
test "max08 updated malformed version system and mixed blank IDs poison" {
  {
    let reader = LegacyReader::new()
    let rejected = try {
      for
        row in [
          "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
          "SYNTHETIC HEADER STATE                                      MARKER NAME",
          "     1    C1                                                # / TYPES OF OBSERV",
          "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "                                                            END OF HEADER",
          " 26 10 27  0  0  0.0000000  0  1G01", "       100.000", " 26 10 27  0  1  0.0000000  4  1",
          "     2.11           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          " 26 10 27  0  2  0.0000000  0  2  1R01", "       200.000", "       201.000",
        ] {
        ignore(reader.feed_line(row))
      }
      reader.finish()
      false
    } catch {
      Rejected(code, _, _) => code == "legacy-satellite"
    }
    assert_true(rejected)
    assert_true(
      try {
        reader.finish()
        false
      } catch {
        Rejected(code, _, _) => code == "state"
      },
    )
  }
  {
    let reader = LegacyReader::new()
    let rejected = try {
      for
        row in [
          "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
          "SYNTHETIC HEADER STATE                                      MARKER NAME",
          "     1    C1                                                # / TYPES OF OBSERV",
          "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "                                                            END OF HEADER",
          " 26 10 27  0  0  0.0000000  0  1G01", "       100.000", " 26 10 27  0  1  0.0000000  4  1",
          "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
          " 26 10 27  0  2  0.0000000  0  1G01", "       200.000",
        ] {
        ignore(reader.feed_line(row))
      }
      reader.finish()
      false
    } catch {
      Rejected(code, _, _) => code == "legacy-version"
    }
    assert_true(rejected)
    assert_true(
      try {
        reader.finish()
        false
      } catch {
        Rejected(code, _, _) => code == "state"
      },
    )
  }
  let reader = LegacyReader::new()
  let rejected = try {
    for
      row in [
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "SYNTHETIC HEADER STATE                                      MARKER NAME",
        "     1    C1                                                # / TYPES OF OBSERV",
        "  2026    10    27     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "                                                            END OF HEADER",
        " 26 10 27  0  0  0.0000000  0  1G01", "       100.000", " 26 10 27  0  1  0.0000000  4  1",
        "     2.11           OBSERVATION DATA    X                   RINEX VERSION / TYPE",
        " 26 10 27  0  2  0.0000000  0  1G01", "       200.000",
      ] {
      ignore(reader.feed_line(row))
    }
    reader.finish()
    false
  } catch {
    Rejected(code, _, _) => code == "legacy-system"
  }
  assert_true(rejected)
  assert_true(
    try {
      reader.finish()
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
}
