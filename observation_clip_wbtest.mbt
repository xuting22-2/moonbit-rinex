// Frozen independent source/full output before implementation, no self roundtrip oracle.

///|
fn clip_test_lines() -> Array[String] {
  [
    "     3.05           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "R10 project-authored window                                 MARKER NAME", "G    2 C1C L1C                                              SYS / # / OBS TYPES",
    "  2026    10    31    23    59   30.0000007     GPS         TIME OF FIRST OBS",
    "  2026    11     1     0     1   30.0000007     GPS         TIME OF LAST OBS",
    "    30.000                                                  INTERVAL", "     0                                                      RCV CLOCK OFFS APPL",
    "G   10   2 C1C L1C                                          SYS / SCALE FACTOR",
    "MIT; fully synthetic, no measurements                       LICENSE OF USE",
    "Keep stored values/flags; apply no extra corrections        COMMENT", "     3                                                      # OF SATELLITES",
    "   G01     2     2                                          PRN / # OF OBS",
    "   G02     2     1                                          PRN / # OF OBS",
    "   G03     0     1                                          PRN / # OF OBS",
    "                                                            END OF HEADER",
    "> 2026 10 31 23 59 30.0000007  0  1", "G01       100.25007       -10.12516",
    "> 2026 11 01 00 00 00.0000007  0  1          0.000000003", "G02         0.00000       -12.50028",
    "> 2026 11 01 00 00 30.0000007  1  0", "> 2026 11 01 00 01 00.0000007  0  2",
    "G02         3.25009", "G03               0        -0.00045", "> 2026 11 01 00 01 30.0000007  0  1",
    "G01        99.75007        -9.87506",
  ]
}

///|
test "raw OBS clip full independent header and body across midnight" {
  let clipper = ObservationClipper::new(14779584000000007L, 14779584900000007L)
  let body : Array[String] = []
  for line in clip_test_lines() {
    for row in clipper.feed_line(line) {
      body.push(row)
    }
  }
  assert_eq(body, [
    "> 2026 11 01 00 00 00.0000007  0  1          0.000000003", "G02         0.00000       -12.50028",
    "> 2026 11 01 00 00 30.0000007  1  0", "> 2026 11 01 00 01 00.0000007  0  2",
    "G02         3.25009", "G03               0        -0.00045",
  ])
  let report = clipper.finish()
  assert_true(report.input_report.complete)
  assert_true(report.input_report.acceptable)
  assert_eq(report.input_report.epochs, 5)
  assert_eq(report.input_report.records, 5)
  assert_eq(report.selected_epochs, 3)
  assert_eq(report.selected_satellite_records, 3)
  assert_eq(report.first_gps_ticks, Some(14779584000000007L))
  assert_eq(report.last_gps_ticks, Some(14779584600000007L))
  assert_eq(report.omitted_summary_lines, 4)
  assert_eq(report.output_header.unwrap(), [
    "     3.05           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "R10 project-authored window                                 MARKER NAME", "G    2 C1C L1C                                              SYS / # / OBS TYPES",
    "  2026    11     1     0     0    0.0000007     GPS         TIME OF FIRST OBS   ",
    "  2026    11     1     0     1    0.0000007     GPS         TIME OF LAST OBS    ",
    "    30.000                                                  INTERVAL", "     0                                                      RCV CLOCK OFFS APPL",
    "G   10   2 C1C L1C                                          SYS / SCALE FACTOR",
    "MIT; fully synthetic, no measurements                       LICENSE OF USE",
    "Keep stored values/flags; apply no extra corrections        COMMENT", "                                                            END OF HEADER",
  ])
  assert_eq(
    clipper.header().unwrap().raw_lines,
    clip_test_lines()[:15].to_owned(),
  )
  try clipper.feed_line("> 2026 11 01 00 02 00.0000007  0  0") catch {
    Rejected("state", _, _) => ()
    _ => fail("expected finished state")
  } noraise {
    _ => fail("must not feed finished clipper")
  }
}

///|
test "OBS clip empty selection and selected zero satellite epoch differ" {
  let none = ObservationClipper::new(14779584000000008L, 14779584300000007L)
  for line in clip_test_lines() {
    assert_true(none.feed_line(line).is_empty())
  }
  let report = none.finish()
  assert_true(report.input_report.acceptable)
  assert_eq(report.selected_epochs, 0)
  assert_true(report.output_header is None)
  let empty = ObservationClipper::new(14779584300000007L, 14779584600000007L)
  let rows : Array[String] = []
  for line in clip_test_lines() {
    for row in empty.feed_line(line) {
      rows.push(row)
    }
  }
  assert_eq(rows, ["> 2026 11 01 00 00 30.0000007  1  0"])
  let report = empty.finish()
  assert_eq(report.selected_epochs, 1)
  assert_eq(report.selected_satellite_records, 0)
  assert_true(report.output_header is Some(_))
}

///|
test "OBS clip full source quality and finish gate output header" {
  let quality = ObservationClipper::new(14779584000000007L, 14779584900000007L)
  let rows = clip_test_lines()
  for i, line in rows {
    ignore(
      quality.feed_line(
        if i == 4 {
          "  2026    11     1     0     2    0.0000007     GPS         TIME OF LAST OBS"
        } else {
          line
        },
      ),
    )
  }
  let report = quality.finish()
  assert_true(report.input_report.complete)
  assert_false(report.input_report.acceptable)
  assert_eq(report.selected_epochs, 3)
  assert_true(report.output_header is None)
  let partial = ObservationClipper::new(14779584000000007L, 14779584900000007L)
  for i in 0..<(rows.length() - 1) {
    ignore(partial.feed_line(rows[i]))
  }
  try partial.finish() catch {
    Rejected("truncated-epoch", _, _) => ()
    _ => fail("expected original final epoch truncation")
  } noraise {
    _ => fail("selected good window cannot bypass full finish")
  }
}
