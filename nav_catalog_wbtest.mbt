// Project-authored synthetic records; state references independently produced byRTKLIB2.4.3b34.

///|
fn catalog_test_rows() -> Array[String] {
  [
    "     3.05           NAVIGATION DATA     MIXED               RINEX VERSION / TYPE",
    "Project-authored synthetic selection example; no measurementsCOMMENT", "                                                            END OF HEADER",
    "G01 2026 10 25 13 00 00 1.100000000000E-04 1.000000000000E-12 0.000000000000E+00",
    "     1.000000000000E+00 0.000000000000E+00 0.000000000000E+00 1.000000000000E-01",
    "     0.000000000000E+00 1.000000000000E-02 0.000000000000E+00 5.153795500000E+03",
    "     4.680000000000E+04 0.000000000000E+00 5.000000000000E-01 0.000000000000E+00",
    "     9.500000000000E-01 0.000000000000E+00 3.000000000000E-01-8.000000000000E-09",
    "     0.000000000000E+00 0.000000000000E+00 2.442000000000E+03 0.000000000000E+00",
    "     2.000000000000E+00 0.000000000000E+00 1.000000000000E-09 1.000000000000E+00",
    "     4.680000000000E+04 4.000000000000E+00                                      ",
    "G01 2026 10 25 14 00 00 1.200000000000E-04 1.000000000000E-12 0.000000000000E+00",
    "     2.000000000000E+00 0.000000000000E+00 0.000000000000E+00 2.000000000000E-01",
    "     0.000000000000E+00 1.000000000000E-02 0.000000000000E+00 5.153795500000E+03",
    "     5.040000000000E+04 0.000000000000E+00 5.000000000000E-01 0.000000000000E+00",
    "     9.500000000000E-01 0.000000000000E+00 3.000000000000E-01-8.000000000000E-09",
    "     0.000000000000E+00 0.000000000000E+00 2.442000000000E+03 0.000000000000E+00",
    "     2.000000000000E+00 1.000000000000E+00 1.000000000000E-09 2.000000000000E+00",
    "     5.040000000000E+04 4.000000000000E+00                                      ",
    "G01 2026 10 25 15 00 00 1.300000000000E-04 1.000000000000E-12 0.000000000000E+00",
    "     3.000000000000E+00 0.000000000000E+00 0.000000000000E+00 3.000000000000E-01",
    "     0.000000000000E+00 1.000000000000E-02 0.000000000000E+00 5.153795500000E+03",
    "     5.400000000000E+04 0.000000000000E+00 5.000000000000E-01 0.000000000000E+00",
    "     9.500000000000E-01 0.000000000000E+00 3.000000000000E-01-8.000000000000E-09",
    "     0.000000000000E+00 0.000000000000E+00 2.442000000000E+03 0.000000000000E+00",
    "     2.000000000000E+00 0.000000000000E+00 1.000000000000E-09 3.000000000000E+00",
    "     5.400000000000E+04 4.000000000000E+00                                      ",
    "C01 2026 10 25 00 00 00-2.000000000000E-04 1.000000000000E-12 0.000000000000E+00",
    "     4.000000000000E+00 0.000000000000E+00 0.000000000000E+00 4.000000000000E-01",
    "     0.000000000000E+00 1.000000000000E-03 0.000000000000E+00 6.493000000000E+03",
    "     0.000000000000E+00 0.000000000000E+00 5.000000000000E-01 0.000000000000E+00",
    "     1.000000000000E-01 0.000000000000E+00 3.000000000000E-01-8.000000000000E-09",
    "     0.000000000000E+00 0.000000000000E+00 1.086000000000E+03 0.000000000000E+00",
    "     2.000000000000E+00 0.000000000000E+00 1.000000000000E-09 4.000000000000E+00",
    "     0.000000000000E+00 0.000000000000E+00                                      ",
    "C06 2026 10 25 00 00 00 3.000000000000E-04 1.000000000000E-12 0.000000000000E+00",
    "     5.000000000000E+00 0.000000000000E+00 0.000000000000E+00 5.000000000000E-01",
    "     0.000000000000E+00 1.000000000000E-03 0.000000000000E+00 6.493000000000E+03",
    "     0.000000000000E+00 0.000000000000E+00 5.000000000000E-01 0.000000000000E+00",
    "     9.500000000000E-01 0.000000000000E+00 3.000000000000E-01-8.000000000000E-09",
    "     0.000000000000E+00 0.000000000000E+00 1.086000000000E+03 0.000000000000E+00",
    "     2.000000000000E+00 0.000000000000E+00 1.000000000000E-09 5.000000000000E+00",
    "     0.000000000000E+00 0.000000000000E+00                                      ",
  ]
}

///|
fn catalog_test_records() -> Array[NavRecord] raise NavError {
  let reader = NavReader::new()
  let records : Array[NavRecord] = []
  for row in catalog_test_rows() {
    if reader.feed_line(row) is Some(record) {
      records.push(record)
    }
  }
  reader.finish()
  records
}

///|
fn catalog_test_catalog() -> NavCatalog raise {
  let c = NavCatalog::new()
  let records = catalog_test_records()
  for i in 0..<records.length() {
    ignore(c.add(records[i], source_line=4 + i * 8))
  }
  c
}

///|
fn catalog_test_retime(
  record : NavRecord,
  week : Int,
  sow : Double,
) -> NavRecord raise NavError {
  let time = NavTime::week(week, sow)
  let data = record.data.copy()
  data[8] = Some(sow)
  data[18] = Some(week.to_double())
  { ..record, toe: time, toc: time, toe_sow: sow, data, }
}

///|
test "catalog independent RTKLIB selected states and provenance" {
  let c = catalog_test_catalog()
  assert_eq(c.len(), 5)
  {
    guard c.query("G01", NavTime::week(2442, 46900.0, bdt=false)) is Selected(s) else {
      abort("expected selected gps-old")
    }
    assert_eq(s.record.record_index, 1)
    assert_eq(s.record.source_line, 4)
    assert_true((s.state.x - -22096045.64113677).abs() < 0.00001)
    assert_true((s.state.y - -11327418.095180582).abs() < 0.00001)
    assert_true((s.state.z - 8661814.022148753).abs() < 0.00001)
    assert_true(
      (s.state.clock_seconds - 0.00010999745579564237).abs() < 1.0e-13,
    )
    assert_eq(s.state.group_delay_seconds, 0.000000001)
  }
  {
    guard c.query("G01", NavTime::week(2442, 50500.0, bdt=false)) is Selected(s) else {
      abort("expected selected gps-fallback")
    }
    assert_eq(s.record.record_index, 3)
    assert_eq(s.record.source_line, 20)
    assert_true((s.state.x - -26237691.64230223).abs() < 0.00001)
    assert_true((s.state.y - -231163.87072261167).abs() < 0.00001)
    assert_true((s.state.z - 1823109.6166810368).abs() < 0.00001)
    assert_true(
      (s.state.clock_seconds - 0.00013000133053746334).abs() < 1.0e-13,
    )
    assert_eq(s.state.group_delay_seconds, 0.000000001)
  }
  {
    guard c.query("G01", NavTime::week(2442, 50400.0, bdt=false)) is Selected(s) else {
      abort("expected selected gps-tie-latest-toc")
    }
    assert_eq(s.record.record_index, 3)
    assert_eq(s.record.source_line, 20)
    assert_true((s.state.x - -26258955.437229156).abs() < 0.00001)
    assert_true((s.state.y - -194768.5107339843).abs() < 0.00001)
    assert_true((s.state.z - 1505937.3035463907).abs() < 0.00001)
    assert_true(
      (s.state.clock_seconds - 0.00013000155964558216).abs() < 1.0e-13,
    )
    assert_eq(s.state.group_delay_seconds, 0.000000001)
  }
  {
    guard c.query("G01", NavTime::week(2442, 53999.9999999, bdt=false))
      is Selected(s) else {
      abort("expected selected gps-100ns")
    }
    assert_eq(s.record.record_index, 3)
    assert_eq(s.record.source_line, 20)
    assert_true((s.state.x - -23226121.756250348).abs() < 0.00001)
    assert_true((s.state.y - -2025999.7168705985).abs() < 0.00001)
    assert_true((s.state.z - 12188446.466589114).abs() < 0.00001)
    assert_true(
      (s.state.clock_seconds - 0.00012999316814165505).abs() < 1.0e-13,
    )
    assert_eq(s.state.group_delay_seconds, 0.000000001)
  }
  {
    guard c.query("C01", NavTime::week(2442, 14.0, bdt=false)) is Selected(s) else {
      abort("expected selected bds-geo-gpst")
    }
    assert_eq(s.record.record_index, 4)
    assert_eq(s.record.source_line, 28)
    assert_true((s.state.x - 15297025.748138368).abs() < 0.00001)
    assert_true((s.state.y - 38765211.486445926).abs() < 0.00001)
    assert_true((s.state.z - 6113319.938875452).abs() < 0.00001)
    assert_true(
      (s.state.clock_seconds - -0.00020000112439640222).abs() < 1.0e-13,
    )
    assert_eq(s.state.group_delay_seconds, 0.000000001)
  }
  {
    guard c.query("C01", NavTime::week(1086, 0.0, bdt=true)) is Selected(s) else {
      abort("expected selected bds-geo-bdt")
    }
    assert_eq(s.record.record_index, 4)
    assert_eq(s.record.source_line, 28)
    assert_true((s.state.x - 15297025.748138368).abs() < 0.00001)
    assert_true((s.state.y - 38765211.486445926).abs() < 0.00001)
    assert_true((s.state.z - 6113319.938875452).abs() < 0.00001)
    assert_true(
      (s.state.clock_seconds - -0.00020000112439640222).abs() < 1.0e-13,
    )
    assert_eq(s.state.group_delay_seconds, 0.000000001)
  }
  {
    guard c.query(
        "C06",
        NavTime::week(2442, 14.0, bdt=false),
        bds_orbit=MEO_IGSO,
      )
      is Selected(s) else {
      abort("expected selected bds-igso-gpst")
    }
    assert_eq(s.record.record_index, 5)
    assert_eq(s.record.source_line, 36)
    assert_true((s.state.x - 17294260.920421556).abs() < 0.00001)
    assert_true((s.state.y - 29494803.385516677).abs() < 0.00001)
    assert_true((s.state.z - 24601485.858317837).abs() < 0.00001)
    assert_true(
      (s.state.clock_seconds - 0.00029999861577945157).abs() < 1.0e-13,
    )
    assert_eq(s.state.group_delay_seconds, 0.000000001)
  }
  guard c.query(
      "C06",
      NavTime::week(1086, 1200.0, bdt=true),
      bds_orbit=MEO_IGSO,
    )
    is Selected(s) else {
    abort("expected selected bds-igso-bdt")
  }
  assert_eq(s.record.record_index, 5)
  assert_eq(s.record.source_line, 36)
  assert_true((s.state.x - 16706026.143295582).abs() < 0.00001)
  assert_true((s.state.y - 28070916.72505823).abs() < 0.00001)
  assert_true((s.state.z - 26596265.98762639).abs() < 0.00001)
  assert_true((s.state.clock_seconds - 0.00029999959967175107).abs() < 1.0e-13)
  assert_eq(s.state.group_delay_seconds, 0.000000001)
}
