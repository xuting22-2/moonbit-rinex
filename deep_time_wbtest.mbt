///|
test "deep time 100ns decimal grid survives week constructor" {
  let gps = NavTime::week(0, 0.0000021)
  let exact = NavTime::calendar(1980, 1, 6, 0, 0, "0.0000021")
  assert_eq(gps.gps_ticks, exact.gps_ticks)
  let bdt = NavTime::week(0, 0.0000021, bdt=true)
  let bdt_exact = NavTime::calendar(2006, 1, 1, 0, 0, "0.0000021", bdt=true)
  assert_eq(bdt.gps_ticks, bdt_exact.gps_ticks)
}

///|
test "deep time quantization grid and GPST BDT week boundaries" {
  let origin = NavTime::week(0, 0.0).gps_ticks
  let bdt_origin = NavTime::week(0, 0.0, bdt=true).gps_ticks
  for tick in 1..<=10000 {
    let seconds = tick.to_double() / 10000000.0
    assert_eq(NavTime::week(0, seconds).gps_ticks, origin + tick.to_int64())
    assert_eq(
      NavTime::week(0, seconds, bdt=true).gps_ticks,
      bdt_origin + tick.to_int64(),
    )
  }
  let gps_end = NavTime::week(1356, 604799.9999999)
  assert_eq(
    gps_end.gps_ticks,
    NavTime::calendar(2006, 1, 7, 23, 59, "59.9999999").gps_ticks,
  )
  let bdt_end = NavTime::week(0, 604799.9999999, bdt=true)
  assert_eq(bdt_end.gps_ticks, NavTime::week(1357, 13.9999999).gps_ticks)
  assert_eq(
    bdt_end.offset_seconds(1).gps_ticks,
    NavTime::week(1357, 14.9999999).gps_ticks,
  )
}
