///|
test "legacy codes keep unknown ambiguity and explicit caller provenance" {
  assert_true(map_legacy_code("G", "L1") is Ambiguous(_))
  assert_true(map_legacy_code("G", "C2") is Unknown)
  assert_true(map_legacy_code("G", "C1") is RuleMapped("C1C", _))
  assert_true(
    map_legacy_code("G", "L1", overrides={ "G:L1": "L1W" })
    is ExplicitOverride("L1W"),
  )
  assert_true(
    try {
      ignore(map_legacy_code("E", "C1", overrides={ "E:C1": "C1W" }))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "OBS2 independent restored continuations and updated header" {
  let reader = LegacyReader::new()
  let epochs : Array[LegacyEpoch] = []
  let events : Array[LegacyEvent] = []
  for line in golden_legacy_output() {
    match reader.feed_line(line) {
      Some(Epoch(e)) => epochs.push(e)
      Some(Event(e)) => events.push(e)
      _ => ()
    }
  }
  reader.finish()
  assert_eq(epochs.length(), 3)
  assert_eq(epochs[0].satellites.length(), 13)
  assert_eq(epochs[0].satellites[12].satellite, "G13")
  let values = epochs[0].satellites[0].values
  assert_eq(values.length(), 13)
  assert_true(values[1].mapping is Ambiguous(_))
  assert_eq(values[1].observation.value, Some(-100000.5))
  assert_eq(values[1].observation.lli, Some(1))
  assert_eq(values[2].observation.value, None)
  assert_eq(values[3].observation.value, Some(0.0))
  assert_eq(events[0].flag, 4)
  assert_eq(epochs[2].satellites[0].values.length(), 2)
}

///|
test "OBS2 truncated continuation poisons and finish never validates partial epoch" {
  let reader = LegacyReader::new()
  let lines = golden_legacy_output()
  for line in lines[0:10] {
    ignore(reader.feed_line(line))
  }
  assert_true(
    try {
      ignore(reader.finish())
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(reader.feed_line(""))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "time constructors distinguish week origins and normalize fourteen seconds" {
  let bdt = NavTime::week(0, 604795.0, bdt=true)
  let gps = NavTime::week(1357, 9.0)
  assert_eq(bdt.gps_ticks, gps.gps_ticks)
  let calendar = NavTime::calendar(2006, 1, 1, 0, 0, "0", bdt=true)
  assert_eq(calendar.gps_ticks, NavTime::week(1356, 14.0).gps_ticks)
  assert_true(
    try {
      ignore(NavTime::week(1, 604800.0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(NavTime::week(-1, 0.0))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "NAV expiry health orbit-type and incomplete-record errors" {
  let record = golden_nav_2()
  assert_true(
    try {
      ignore(record.satellite_position(record.toe.offset_seconds(20000)))
      false
    } catch {
      EphemerisExpired => true
      _ => false
    },
  )
  let r = golden_nav_1()
  assert_true(
    try {
      ignore(r.satellite_position(r.toe))
      false
    } catch {
      OrbitTypeRequired => true
      _ => false
    },
  )
  let unhealthy : NavRecord = { ..record, health: 1, }
  assert_true(
    try {
      ignore(unhealthy.satellite_position(unhealthy.toe))
      false
    } catch {
      UnhealthyEphemeris => true
      _ => false
    },
  )
  let reader = NavReader::new()
  assert_true(
    try {
      ignore(reader.finish())
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(reader.feed_line(""))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "CRINEX3 escape is not reset and negative phase is preserved" {
  let input = golden_modern_input()
  let decoder = CrinexDecoder::new()
  let output : Array[String] = []
  let mut header_end = 0
  for i in 0..<input.length() {
    if input[i].contains("END OF HEADER") {
      header_end = i
      break
    }
  }
  for i in 0..<input.length() {
    if i == header_end + 1 {
      assert_eq(decoder.feed_line("&escape"), [])
    }
    for s in decoder.feed_line(input[i]) {
      output.push(s)
    }
  }
  assert_true(decoder.finish().complete)
  assert_eq(output.join("\n"), golden_modern_output().join("\n"))
  assert_true(output.iter().any(s => s.contains("-100.500")))
}

///|
test "CRINEX truncation uninitialized arc overflow and poisoning" {
  let d = CrinexDecoder::new()
  let lines = golden_modern_input()
  let mut stop = 0
  for i in 0..<lines.length() {
    if lines[i].has_prefix(">") {
      stop = i
      break
    }
  }
  for s in lines[0:stop + 1] {
    ignore(d.feed_line(s))
  }
  assert_true(
    try {
      ignore(d.finish())
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(d.feed_line(""))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_arc("1", None))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_arc("6&1", None))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(decode_arc("3&9223372036854775808", None))
      false
    } catch {
      _ => true
    },
  )
  let first = decode_arc("1&9223372036854775807", None)
  assert_true(
    try {
      ignore(decode_arc("1", Some(first)))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "CRINEX recovery drops provisional epoch and never reports acceptance" {
  let input = golden_modern_input()
  let d = CrinexDecoder::new(recover=true)
  let output : Array[String] = []
  let mut first_epoch = 0
  for i in 0..<input.length() {
    if input[i].has_prefix(">") {
      first_epoch = i
      break
    }
  }
  for i in 0..<input.length() {
    let line = if i == first_epoch + 2 { "0" } else { input[i] }
    for row in d.feed_line(line) {
      output.push(row)
    }
  }
  let report = d.finish()
  assert_true(!report.complete && !report.acceptable)
  assert_eq(report.recovered_epochs, 1)
  assert_eq(report.epochs, 1)
  assert_eq(report.findings.length(), 1)
  assert_true(!output.iter().any(row => row.contains("-100.500")))
}

///|
test "NAV3.05 skip is explicit and consumes GLONASS fifth line" {
  let header = right_pad("     3.05           N: GNSS NAV DATA     M", 60) +
    "RINEX VERSION / TYPE"
  let end = right_pad("", 60) + "END OF HEADER"
  let reader = NavReader::new(skip_unsupported=true)
  ignore(reader.feed_line(header))
  ignore(reader.feed_line(end))
  ignore(reader.feed_line("R01 2026 10 27 00 00 00"))
  for _ in 0..<4 {
    ignore(reader.feed_line("    "))
  }
  reader.finish()
  assert_eq(reader.skipped_records(), 1)
  let strict = NavReader::new()
  ignore(strict.feed_line(header))
  ignore(strict.feed_line(end))
  assert_true(
    try {
      ignore(strict.feed_line("R01 2026 10 27 00 00 00"))
      false
    } catch {
      UnsupportedConstellation("R") => true
      _ => false
    },
  )
}

///|
test "Kepler bounded failure does not return last iterate" {
  let record = golden_nav_2()
  let data = record.data.copy()
  data[3] = Some(0.000001)
  data[5] = Some(0.999999999)
  let adversarial : NavRecord = { ..record, data, }
  assert_true(
    try {
      ignore(adversarial.satellite_position(adversarial.toe))
      false
    } catch {
      KeplerDivergence => true
      _ => false
    },
  )
}
