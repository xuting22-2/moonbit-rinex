///|
// Controlled, specification-derived cases. Real public data and independent
// RTKLIB/RINEX4 recipients are exercised separately by host/reference checks.
fn navigation_contract(
  lines : Array[String],
  version? : String = "4.02",
) -> NavigationMessage raise NavError {
  let reader = NavigationReader::new()
  ignore(
    reader.feed_line(
      "     " +
      version +
      "           NAVIGATION DATA     M                   RINEX VERSION / TYPE",
    ),
  )
  ignore(
    reader.feed_line(
      "                                                            END OF HEADER",
    ),
  )
  let mut found = None
  for s in lines {
    if reader.feed_line(s) is Some(m) {
      found = Some(m)
    }
  }
  if reader.finish() is Some(m) {
    found = Some(m)
  }
  found.unwrap()
}

///|
fn navigation_fixture_glo() -> Array[String] {
  [
    "> EPH R01 FDMA", "R01 2025 01 01 00 00 00 2.000000000000E-04 1.000000000000E-11 2.592000000000E+05",
    "     2.000000000000E+04-1.500000000000E+00 1.000000000000E-09 0.000000000000E+00",
    "     1.500000000000E+04 2.000000000000E+00 2.000000000000E-09-7.000000000000E+00",
    "     1.200000000000E+04 1.000000000000E+00-1.000000000000E-09 0.000000000000E+00",
    "     0.000000000000E+00 1.000000000000E-09 4.000000000000E+00 0.000000000000E+00",
  ]
}

///|
fn navigation_fixture_gal() -> Array[String] {
  [
    "> EPH E02 INAV", "E02 2025 01 01 00 00 00 1.000000000000E-04 1.000000000000E-12 0.000000000000E+00",
    "     1.000000000000E+00 1.000000000000E+02 4.000000000000E-09 4.000000000000E-01",
    "     1.000000000000E-06 1.000000000000E-03 2.000000000000E-06 5.440000000000E+03",
    "     2.592000000000E+05 1.000000000000E-08 1.000000000000E+00 2.000000000000E-08",
    "     9.600000000000E-01 2.000000000000E+02 3.000000000000E-01-8.000000000000E-09",
    "     1.000000000000E-10 5.170000000000E+02 2.347000000000E+03                   ",
    "     5.000000000000E-01 0.000000000000E+00-5.000000000000E-09-6.000000000000E-09",
    "     2.592100000000E+05                                                         ",
  ]
}

///|
fn navigation_fixture_fnav() -> Array[String] {
  [
    "> EPH E02 FNAV", "E02 2025 01 01 00 00 00 1.000000000000E-04 1.000000000000E-12 0.000000000000E+00",
    "     1.000000000000E+00 1.000000000000E+02 4.000000000000E-09 4.000000000000E-01",
    "     1.000000000000E-06 1.000000000000E-03 2.000000000000E-06 5.440000000000E+03",
    "     2.592000000000E+05 1.000000000000E-08 1.000000000000E+00 2.000000000000E-08",
    "     9.600000000000E-01 2.000000000000E+02 3.000000000000E-01-8.000000000000E-09",
    "     1.000000000000E-10 2.580000000000E+02 2.347000000000E+03                   ",
    "     5.000000000000E-01 7.000000000000E+00-5.000000000000E-09                   ",
    "     2.592100000000E+05                                                         ",
  ]
}

///|
fn navigation_fixture_eop() -> Array[String] {
  [
    "> EOP G   CNVX", "    2025 01 01 00 00 00 1.000000000000E-01 2.000000000000E-02 3.000000000000E-04",
    "                        2.000000000000E-01 1.000000000000E-02 2.000000000000E-04",
    "     2.592000000000E+05-1.810000000000E+01 1.000000000000E-03 1.000000000000E-05",
  ]
}

///|
fn navigation_fixture_sto() -> Array[String] {
  [
    "> STO G   CNVX", "    2025 01 01 00 00 00 GPUT                                  UTC(USNO)         ",
    "    -1.000000000000E+02 1.000000000000E-09 2.000000000000E-12 3.000000000000E-18",
  ]
}

///|
test "navigation R3 GLO version-dependent row count and signed channel" {
  let r4 = navigation_fixture_glo()
  for version in ["3.00", "3.01", "3.02", "3.03", "3.04", "3.05"] {
    let n = if version == "3.05" { 5 } else { 4 }
    let r3 = [ for i in 1..<(n + 1) => r4[i] ]
    let m = navigation_contract(r3, version~)
    assert_eq(m.raw_lines().length(), n)
    assert_eq(m.value("frequency_channel"), Some(-7.0))
    assert_eq(m.epoch.unwrap().scale, "UTC")
    let state = m.state_at_offset(0.0)
    assert_eq(state.x, 20000000.0)
    assert_eq(state.clock_seconds, 0.0002)
  }
}

///|
test "navigation Galileo signal health, source, BGD and GPS-aligned week" {
  let i = navigation_contract(navigation_fixture_gal())
  let f = navigation_contract(navigation_fixture_fnav())
  assert_eq(i.value("data_sources"), Some(517.0))
  assert_eq(i.epoch.unwrap().calendar_ticks, try! day_ticks(2025, 1, 1))
  assert_eq(i.epoch.unwrap().scale, "GST")
  assert_eq(i.value("week"), Some(2347.0))
  assert_eq(i.value("bgd_e5b_e1"), Some(-6.0e-9))
  assert_eq(f.value("bgd_e5b_e1"), None)
  assert_eq(f.state_at_offset(0.0, signal="E5a").frame, "GTRF")
  assert_eq(
    i.state_at_offset(0.0, signal="E1B").clock_seconds,
    i.state_at_offset(0.0, signal="E5b").clock_seconds,
  )
  assert_true(
    try {
      ignore(f.state_at_offset(0.0, signal="E1B"))
      false
    } catch {
      _ => true
    },
  )
  let r3 = navigation_fixture_gal()[1:].to_owned()
  assert_eq(navigation_contract(r3, version="3.04").family, "INAV")
}

///|
test "navigation STO SI seconds and EOP day derivative units" {
  let s = navigation_contract(navigation_fixture_sto())
  assert_eq(s.text("correction_type"), Some("GPUT"))
  assert_eq(s.text("utc_id"), Some("UTC(USNO)"))
  assert_eq(s.value("transmission_time"), Some(-100.0))
  assert_true((s.system_time_offset(10.0) - 1.0200003e-9).abs() < 1.0e-22)
  let e = navigation_contract(navigation_fixture_eop()).earth_orientation(
    86400.0,
  )
  assert_true((e.xp_arcsec - 0.12015).abs() < 1.0e-14)
  assert_true((e.yp_arcsec - 0.2101).abs() < 1.0e-14)
  assert_true((e.delta_ut1_seconds + 18.098995).abs() < 1.0e-12)
}

///|
test "navigation no silent unknown record and final opaque flush" {
  let r = NavigationReader::new()
  ignore(
    r.feed_line(
      "     4.02           NAVIGATION DATA     M                   RINEX VERSION / TYPE",
    ),
  )
  ignore(
    r.feed_line(
      "                                                            END OF HEADER",
    ),
  )
  ignore(r.feed_line("> XYZ G01 FUTR"))
  ignore(r.feed_line("future uninterpreted payload"))
  let m = r.finish().unwrap()
  assert_false(m.known)
  assert_eq(m.raw_lines()[1], "future uninterpreted payload")
  assert_eq(r.unsupported_records(), 1)
  assert_true(
    try {
      ignore(r.finish())
      false
    } catch {
      _ => true
    },
  )
}

///|
test "navigation truncation, satellite mismatch and poisoned reader" {
  let lines = navigation_fixture_gal()
  assert_true(
    try {
      ignore(navigation_contract(lines[:lines.length() - 1].to_owned()))
      false
    } catch {
      _ => true
    },
  )
  lines[0] = "> EPH E03 INAV"
  assert_true(
    try {
      ignore(navigation_contract(lines))
      false
    } catch {
      _ => true
    },
  )
  let r = NavigationReader::new()
  assert_true(
    try {
      ignore(r.feed_line("bad"))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        r.feed_line(
          "                                                            END OF HEADER",
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "navigation GLONASS elapsed age and explicit UTC leap coordinate" {
  let lines = navigation_fixture_glo()
  let m = navigation_contract(lines)
  ignore(m.state_at_offset(-1800.0))
  ignore(m.state_at_offset(1800.0))
  assert_true(
    try {
      ignore(m.state_at_offset(1800.1))
      false
    } catch {
      _ => true
    },
  )
  lines[1] = "R01 2016 12 31 23 59 60" + part(lines[1], 23, 80)
  let leap = navigation_contract(lines).epoch.unwrap()
  assert_true(leap.leap_second)
  assert_eq(leap.calendar, "2016 12 31 23 59 60")
}

///|
test "navigation R4 version matrix core record consumption" {
  let qzss_ion = [
    "> ION J   LNAV", "    2025 01 01 00 00 00 1.000000000000E-08 2.000000000000E-08 3.000000000000E-08",
    "     4.000000000000E-08 1.000000000000E+05 2.000000000000E+05 3.000000000000E+05",
    "     4.000000000000E+05",
  ]
  for version in ["4.00", "4.01", "4.02"] {
    assert_true(navigation_contract(qzss_ion, version~).known)
    assert_eq(
      navigation_contract(navigation_fixture_glo(), version~).state_at_offset(
        0.0,
      ).frame,
      "PZ-90",
    )
    assert_eq(
      navigation_contract(navigation_fixture_gal(), version~).state_at_offset(
        0.0,
        signal="E1B",
      ).frame,
      "GTRF",
    )
    assert_eq(
      navigation_contract(navigation_fixture_sto(), version~).text(
        "correction_type",
      ),
      Some("GPUT"),
    )
    assert_true(
      navigation_contract(navigation_fixture_eop(), version~).earth_orientation(
        0.0,
      ).xp_arcsec >
      0.0,
    )
  }
}

///|
test "navigation legal GLONASS channel13 and explicit bad health/numeric errors" {
  let lines = navigation_fixture_glo()
  lines[3] = part(lines[3], 0, 61) + " 1.300000000000E+01"
  ignore(navigation_contract(lines).state_at_offset(0.0))
  lines[3] = part(lines[3], 0, 61) + " 1.400000000000E+01"
  assert_true(
    try {
      ignore(navigation_contract(lines).state_at_offset(0.0))
      false
    } catch {
      _ => true
    },
  )
  lines[3] = part(lines[3], 0, 61) + "-7.000000000000E+00"
  lines[5] = part(lines[5], 0, 61) + " 2.000000000000E+00"
  assert_true(
    try {
      ignore(navigation_contract(lines).state_at_offset(0.0))
      false
    } catch {
      _ => true
    },
  )
  lines[1] = part(lines[1], 0, 23) +
    "                NaN" +
    part(lines[1], 42, 80)
  assert_true(
    try {
      ignore(navigation_contract(lines))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "navigation unknown wire sentinels and M-dependent GLONASS health" {
  let lines = navigation_fixture_glo()
  lines[5] = "     1.280000000000E+02 9.999999999990E+08 1.500000000000E+01 4.000000000000E+00"
  let m = navigation_contract(lines)
  assert_eq(
    m.parameters().filter(f => f.name == "delta_tau")[0].availability,
    "unknown",
  )
  assert_eq(
    m.parameters().filter(f => f.name == "urai")[0].availability,
    "unknown",
  )
  assert_eq(m.value("delta_tau"), Some(999999999.999))
  assert_true(
    try {
      ignore(m.state_at_offset(0.0))
      false
    } catch {
      _ => true
    },
  )
  // l(3) is only valid for M/K when M=status bits7-8=01.
  lines[5] = "     0.000000000000E+00 9.999999999990E+08 1.500000000000E+01 4.000000000000E+00"
  ignore(navigation_contract(lines).state_at_offset(0.0))
}
