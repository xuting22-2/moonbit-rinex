///|
fn assert_reference(selection : @r.NavSelection) -> Unit raise {
  assert_eq(selection.record.record_index, 1)
  assert_eq(selection.record.source_line, 4)
  assert_true((selection.state.x - -15789254.26762028).abs() <= 0.00001)
  assert_true((selection.state.y - -11845667.979850149).abs() <= 0.00001)
  assert_true((selection.state.z - 17454897.504236296).abs() <= 0.00001)
  assert_true(
    (selection.state.clock_seconds - 0.00010998992248758549).abs() <= 1.0e-13,
  )
}

///|
test "modern observation ticks enter navigation without floating conversion" {
  let epoch = modern_observation()
  assert_eq(epoch.gps_ticks, 14774041000000001L)
  assert_eq(epoch.receiver_clock, Some(0.0001234))
  let time = @r.NavTime::from_gps_ticks(epoch.gps_ticks)
  assert_eq(time.gps_ticks, epoch.gps_ticks)
  json_inspect(time, content={ "gps_ticks": "14774041000000001" })
  guard navigation_catalog().query("G01", time) is @r.Selected(selection) else {
    abort("selected state")
  }
  assert_reference(selection)
  assert_eq(selection.report.at.gps_ticks, epoch.gps_ticks)
}

///|
test "legacy observation ticks use the same exact navigation coordinate" {
  let epoch = legacy_observation()
  assert_eq(epoch.gps_ticks, 14774041000000001L)
  assert_eq(epoch.receiver_clock, Some(0.0001234))
  let time = @r.NavTime::from_gps_ticks(epoch.gps_ticks)
  guard navigation_catalog().query("G01", time) is @r.Selected(selection) else {
    abort("selected state")
  }
  assert_reference(selection)
  assert_eq(selection.report.at.gps_ticks, epoch.gps_ticks)
}

///|
test "tick input bounds match observation calendar without changing older constructors" {
  assert_eq(@r.NavTime::from_gps_ticks(0L).gps_ticks, 0L)
  let last = @r.NavTime::from_gps_ticks(38184479999999999L)
  assert_eq(
    last.gps_ticks,
    @r.NavTime::calendar(2100, 12, 31, 23, 59, "59.9999999").gps_ticks,
  )
  for
    invalid in [
      -1L, 38184480000000000L, 38184480000000001L, 9223372036854775807L,
    ] {
    assert_true(
      try {
        ignore(@r.NavTime::from_gps_ticks(invalid))
        false
      } catch {
        @r.InvalidNavigation(_) => true
        _ => false
      },
    )
  }
  assert_true(@r.NavTime::week(7000, 0.0, bdt=true).gps_ticks > last.gps_ticks)
}
