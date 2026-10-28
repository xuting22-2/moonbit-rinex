///|
test "reader preserves raw zero, blank and indicators while matching the checker report" {
  let lines = fixture()
  lines[8] = "G01" + String::make(14, ' ') + "07" + "         0.000" + "0 "
  let reader = Reader::new()
  assert_true(reader.header() is None)
  let epochs : Array[ObservationEpoch] = []
  for line in lines {
    if reader.feed_line(line) is Some(epoch) {
      epochs.push(epoch)
    }
  }
  assert_eq(epochs.length(), 2)
  let first = epochs[0]
  assert_eq(first.line, 8)
  assert_eq(first.end_line, 9)
  assert_eq(first.raw_record, lines[7])
  assert_eq(first.satellites[0].raw_record, lines[8])
  assert_eq(first.satellites[0].line, 9)
  let a = first.satellites[0].observations[0]
  let b = first.satellites[0].observations[1]
  assert_eq(a.code, "C1C")
  assert_eq(a.column, 4)
  assert_eq(a.value, None)
  assert_eq(a.lli, Some(0))
  assert_eq(a.ssi, Some(7))
  assert_eq(b.column, 20)
  assert_eq(b.value, Some(0.0))
  assert_eq(b.lli, Some(0))
  assert_eq(b.ssi, None)
  assert_true(a.to_json().stringify().contains("\"value\":null"))
  assert_eq(reader.finish().to_json(), consume(lines).to_json())
}

///|
test "reader emits only complete epochs and poisons truncated or malformed streams" {
  let lines = fixture()
  lines[7] = lines[7].replace(old="0  1", new="0  2")
  let reader = Reader::new()
  for i in 0..<9 {
    assert_true(reader.feed_line(lines[i]) is None)
  }
  assert_true(
    try {
      ignore(reader.feed_line(lines[8]))
      false
    } catch {
      Rejected(code, line, _) => code == "duplicate-satellite" && line == 10
    },
  )
  assert_true(
    try {
      ignore(reader.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
  let partial = Reader::new()
  for i in 0..<8 {
    ignore(partial.feed_line(lines[i]))
  }
  assert_true(
    try {
      ignore(partial.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "truncated-epoch"
    },
  )
  assert_true(
    try {
      ignore(partial.feed_line(lines[8]))
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
}

///|
test "half-open output range validates all input and supports immediate empty epochs" {
  let start = 14745888000000000L
  let selected = Reader::new(gps_range=(start, start + 300000000L))
  let epochs : Array[ObservationEpoch] = []
  for line in fixture() {
    if selected.feed_line(line) is Some(epoch) {
      epochs.push(epoch)
    }
  }
  assert_eq(epochs.length(), 1)
  assert_eq(epochs[0].gps_ticks, start)
  assert_eq(selected.finish().epochs, 2)
  for range in [(-1L, 1L), (0L, 0L), (10L, 9L), (0L, 999999999999999999L)] {
    assert_true(
      try {
        ignore(Reader::new(gps_range=range))
        false
      } catch {
        Rejected(code, _, _) => code == "range"
      },
    )
  }
  let empty = Reader::new()
  let lines = fixture()
  for i in 0..<7 {
    ignore(empty.feed_line(lines[i]))
  }
  let epoch = empty.feed_line(lines[7].replace(old="0  1", new="0  0")).unwrap()
  assert_eq(epoch.line, epoch.end_line)
  assert_eq(epoch.satellites.length(), 0)
  ignore(empty.feed_line(lines[9]))
  ignore(empty.feed_line(lines[10]))
  assert_eq(empty.finish().epochs, 2)
  let rejected = Reader::new(gps_range=(start + 300000000L, start + 600000000L))
  for i in 0..<8 {
    ignore(rejected.feed_line(lines[i]))
  }
  assert_true(
    try {
      ignore(rejected.feed_line("G00"))
      false
    } catch {
      Rejected(code, _, _) => code == "satellite-id"
    },
  )
}

///|
test "header snapshots retain correction semantics and callers cannot mutate reader state" {
  let lines = fixture()
  let reader = Reader::new()
  for i in 0..<6 {
    ignore(reader.feed_line(lines[i]))
  }
  let scale = "G   10  0" + String::make(51, ' ') + "SYS / SCALE FACTOR"
  let clock = "     0" + String::make(54, ' ') + "RCV CLOCK OFFS APPL"
  ignore(reader.feed_line(scale))
  ignore(reader.feed_line(clock))
  ignore(reader.feed_line(lines[6]))
  let snapshot = reader.header().unwrap()
  assert_true(snapshot.raw_lines.contains(scale))
  assert_true(
    snapshot.parsed.uninterpreted_labels.contains("SYS / SCALE FACTOR"),
  )
  snapshot.raw_lines[0] = "changed by caller"
  snapshot.parsed.observation_types["G"].push("D1C")
  assert_eq(reader.header().unwrap().parsed.observation_types["G"].length(), 2)
  assert_eq(reader.header().unwrap().raw_lines[0], lines[0])
  let epoch_line = lines[7] + String::make(6, ' ') + " 0.000001000000"
  ignore(reader.feed_line(epoch_line))
  let first = reader.feed_line(lines[8]).unwrap()
  assert_eq(first.receiver_clock, Some(0.000001))
  assert_eq(first.gps_ticks, 14745888000000000L)
  assert_eq(first.satellites[0].observations[0].value, Some(20000000.0))
  first.satellites.push(first.satellites[0])
  ignore(reader.feed_line(lines[9]))
  assert_eq(reader.feed_line(lines[10]).unwrap().satellites.length(), 1)
  assert_eq(reader.finish().records, 2)
  assert_true(
    try {
      ignore(reader.feed_line(lines[10]))
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
}
