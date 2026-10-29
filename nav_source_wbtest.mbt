///|
test "NAV source snapshots follow emitted native records and own their arrays" {
  let rows = catalog_test_rows()
  let reader = NavReader::new(capture_source=true)
  for i in 0..<11 {
    let record = reader.feed_line(rows[i])
    assert_eq(record is Some(_), i == 10)
    assert_eq(reader.last_record_source() is Some(_), i == 10)
  }
  let source = reader.last_record_source().unwrap()
  assert_eq(source.first_line, 4)
  assert_eq(source.last_line, 11)
  assert_eq(source.raw_lines, [ for i in 3..<11 => rows[i] ])
  let header = reader.header_lines()
  assert_eq(header, [ for i in 0..<3 => rows[i] ])
  header[0] = "caller mutation"
  source.raw_lines[0] = "caller mutation"
  assert_eq(reader.header_lines()[0], rows[0])
  assert_eq(reader.last_record_source().unwrap().raw_lines[0], rows[3])
  reader.finish()
  assert_eq(reader.last_record_source().unwrap().last_line, 11)
  let plain = NavReader::new()
  for i in 0..<11 {
    ignore(plain.feed_line(rows[i]))
  }
  plain.finish()
  assert_true(plain.header_lines().is_empty())
  assert_true(plain.last_record_source() is None)
}

///|
test "NAV source physical lines include opaque skipped records and clear on next feed" {
  let rows = catalog_test_rows()
  let reader = NavReader::new(skip_unsupported=true, capture_source=true)
  for i in 0..<3 {
    ignore(reader.feed_line(rows[i]))
  }
  for line in ["R01 opaque", "opaque", "opaque", "opaque", "opaque"] {
    assert_true(reader.feed_line(line) is None)
    assert_true(reader.last_record_source() is None)
  }
  for i in 3..<11 {
    ignore(reader.feed_line(rows[i]))
  }
  let source = reader.last_record_source().unwrap()
  assert_eq(source.first_line, 9)
  assert_eq(source.last_line, 16)
  assert_eq(reader.skipped_records(), 1)
  ignore(reader.feed_line(rows[11]))
  assert_true(reader.last_record_source() is None)
  try reader.finish() catch {
    InvalidNavigation(_) => ()
    _ => fail("expected truncated navigation record")
  } noraise {
    _ => fail("partial following record must fail")
  }
}
