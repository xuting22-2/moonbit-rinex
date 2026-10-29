// Inputs/full CSV and native report are frozen before implementation in R08.

///|
fn csv_test_lines() -> Array[String] {
  [
    "     3.05           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
    "CSV \"raw\", station                                          MARKER NAME",
    "G    2 C1C L1C                                              SYS / # / OBS TYPES",
    "R    2 C1C L1C                                              SYS / # / OBS TYPES",
    "  2026    10    29     0     0    0.0000001     GPS         TIME OF FIRST OBS",
    "  2026    10    29     0     1   30.0000001     GPS         TIME OF LAST OBS",
    "    30.000                                                  INTERVAL", "     0                                                      RCV CLOCK OFFS APPL",
    "MIT; fully synthetic OBS table fixture                      LICENSE OF USE",
    "R08 self-authored; no measurements or corrections           COMMENT", "                                                            END OF HEADER",
    "> 2026 10 29 00 00 00.0000001  0  2", "G01         0.000 0       -12.25017",
    "R02              09     1.250D+0220", "> 2026 10 29 00 00 30.0000001  0  1          0.000000001",
    "G01         3.50009", "> 2026 10 29 00 01 00.0000001  1  0", "> 2026 10 29 00 01 30.0000001  0  1",
    "G12     1.000E-0300        -0.00046",
  ]
}

///|
test "CSV complete frozen raw rows preserve exact values empty epochs and flags" {
  let reader = ObservationCsvReader::new()
  let rows = [observation_csv_columns()]
  for line in csv_test_lines() {
    for row in reader.feed_line(line) {
      rows.push(row)
    }
  }
  assert_eq(rows, [
    "\"row_kind\",\"epoch_index\",\"gps_ticks\",\"epoch_flag\",\"source_line\",\"satellite\",\"observation_code\",\"source_column\",\"raw_field\",\"value_text\",\"lli\",\"ssi\",\"receiver_clock_raw\"",
    "\"epoch\",\"1\",\"14776992000000001\",\"0\",\"12\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"",
    "\"observation\",\"1\",\"14776992000000001\",\"0\",\"13\",\"G01\",\"C1C\",\"4\",\"         0.000 0\",\"0.000\",\"\",\"0\",\"\"",
    "\"observation\",\"1\",\"14776992000000001\",\"0\",\"13\",\"G01\",\"L1C\",\"20\",\"       -12.25017\",\"-12.250\",\"1\",\"7\",\"\"",
    "\"observation\",\"1\",\"14776992000000001\",\"0\",\"14\",\"R02\",\"C1C\",\"4\",\"              09\",\"\",\"0\",\"9\",\"\"",
    "\"observation\",\"1\",\"14776992000000001\",\"0\",\"14\",\"R02\",\"L1C\",\"20\",\"     1.250D+0220\",\"1.250D+02\",\"2\",\"0\",\"\"",
    "\"epoch\",\"2\",\"14776992300000001\",\"0\",\"15\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"    0.000000001\"",
    "\"observation\",\"2\",\"14776992300000001\",\"0\",\"16\",\"G01\",\"C1C\",\"4\",\"         3.50009\",\"3.500\",\"0\",\"9\",\"\"",
    "\"observation\",\"2\",\"14776992300000001\",\"0\",\"16\",\"G01\",\"L1C\",\"20\",\"\",\"\",\"\",\"\",\"\"",
    "\"epoch\",\"3\",\"14776992600000001\",\"1\",\"17\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"",
    "\"epoch\",\"4\",\"14776992900000001\",\"0\",\"18\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"",
    "\"observation\",\"4\",\"14776992900000001\",\"0\",\"19\",\"G12\",\"C1C\",\"4\",\"     1.000E-0300\",\"1.000E-03\",\"0\",\"0\",\"\"",
    "\"observation\",\"4\",\"14776992900000001\",\"0\",\"19\",\"G12\",\"L1C\",\"20\",\"        -0.00046\",\"-0.000\",\"4\",\"6\",\"\"",
  ])
  let report = reader.finish()
  assert_eq(report.epochs, 4)
  assert_eq(report.satellite_records, 4)
  assert_eq(report.observation_rows, 8)
  assert_eq(report.rows, 12)
  assert_eq(
    report.input_report.to_json().stringify(),
    "{\"complete\":true,\"acceptable\":true,\"profile\":\"bounded OBS structural/time checks\",\"time_unit\":\"100ns calendar ticks since 1980-01-01 00:00:00 GPS; not UTC\",\"header\":{\"version\":\"3.05\",\"marker\":\"CSV \\\"raw\\\", station\",\"time_system\":\"GPS\",\"first\":\"14776992000000001\",\"last\":\"14776992900000001\",\"interval\":\"300000000\",\"license\":\"MIT; fully synthetic OBS table fixture\",\"doi\":\"\",\"observation_types\":{\"G\":[\"C1C\",\"L1C\"],\"R\":[\"C1C\",\"L1C\"]},\"uninterpreted_labels\":[\"COMMENT\"]},\"epochs\":4,\"records\":4,\"first\":\"14776992000000001\",\"last\":\"14776992900000001\",\"missing_epoch_slots\":0,\"power_failure_epochs\":1,\"receiver_clock_epochs\":1,\"systems\":[{\"system\":\"G\",\"records\":3,\"satellites\":[\"G01\",\"G12\"],\"signals\":[{\"code\":\"C1C\",\"nonempty_fields\":3,\"blank_fields\":0,\"zero_values\":1,\"lli_nonzero\":0,\"lli_bit0\":0,\"lli_bit1\":0,\"lli_bit2\":0},{\"code\":\"L1C\",\"nonempty_fields\":2,\"blank_fields\":1,\"zero_values\":1,\"lli_nonzero\":2,\"lli_bit0\":1,\"lli_bit1\":0,\"lli_bit2\":1}]},{\"system\":\"R\",\"records\":1,\"satellites\":[\"R02\"],\"signals\":[{\"code\":\"C1C\",\"nonempty_fields\":0,\"blank_fields\":1,\"zero_values\":0,\"lli_nonzero\":0,\"lli_bit0\":0,\"lli_bit1\":0,\"lli_bit2\":0},{\"code\":\"L1C\",\"nonempty_fields\":1,\"blank_fields\":0,\"zero_values\":0,\"lli_nonzero\":1,\"lli_bit0\":0,\"lli_bit1\":1,\"lli_bit2\":0}]}],\"findings\":[{\"code\":\"empty-epoch\",\"line\":17,\"error\":false,\"detail\":\"epoch contains no satellite observations\"},{\"code\":\"power-failure\",\"line\":17,\"error\":false,\"detail\":\"receiver power interruption flag\"}],\"finding_counts\":{\"empty-epoch\":1,\"power-failure\":1},\"omitted_findings\":0}",
  )
  try reader.feed_line("> 2026 10 29 00 02 00.0000001  0  0") catch {
    Rejected("state", _, _) => ()
    _ => fail("expected finished state")
  } noraise {
    _ => fail("no table rows after finish")
  }
}

///|
test "CSV failed last epoch stays provisional and complete quality failure stays separate" {
  let lines = csv_test_lines()
  let reader = ObservationCsvReader::new()
  let rows : Array[String] = []
  for i in 0..<(lines.length() - 1) {
    for row in reader.feed_line(lines[i]) {
      rows.push(row)
    }
  }
  assert_eq(rows.length(), 9)
  try reader.finish() catch {
    Rejected("truncated-epoch", _, _) => ()
    _ => fail("expected incomplete final satellite record")
  } noraise {
    _ => fail("must not finish partial CSV input")
  }
  let quality = ObservationCsvReader::new()
  for i, line in lines {
    ignore(
      quality.feed_line(
        if i == 5 {
          "  2026    10    29     0     1    0.0000001     GPS         TIME OF LAST OBS"
        } else {
          line
        },
      ),
    )
  }
  let report = quality.finish()
  assert_true(report.input_report.complete)
  assert_false(report.input_report.acceptable)
  assert_eq(report.input_report.finding_counts.get("header-last"), Some(1))
  assert_eq(report.rows, 12)
}
