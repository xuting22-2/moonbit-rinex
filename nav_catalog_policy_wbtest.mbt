///|
test "catalog unavailable cases and explicit BDS orbit choice" {
  let c = catalog_test_catalog()
  let time = NavTime::week(1086, 0.0, bdt=true)
  guard c.query("C06", time) is Unavailable(missing) else {
    abort("expected missing orbit choice")
  }
  assert_eq(missing.candidates, 1)
  assert_eq(missing.rejection_counts.get("orbit-type-required"), Some(1))
  assert_true(missing.rejection_samples[0].reason is OrbitChoiceRequired)
  assert_true(c.query("C06", time, bds_orbit=MEO_IGSO) is Selected(_))
  guard c.query("G99", time) is Unavailable(absent) else {
    abort("expected absent satellite")
  }
  assert_eq(absent.candidates, 0)
  assert_eq(absent.rejected, 0)
  let empty = NavCatalog::new()
  assert_true(empty.query("G01", time) is Unavailable(_))
  guard c.query("G01", NavTime::week(2442, 64800.0)) is Unavailable(stale) else {
    abort("expected stale records")
  }
  assert_eq(stale.rejection_counts.get("expired"), Some(3))
  assert_eq(stale.eligible, 0)
}

///|
test "catalog exact tick ranking crosses week and is input-order independent" {
  let record = catalog_test_records()[0]
  let left = catalog_test_retime(record, 2442, 604784.0)
  let right = catalog_test_retime(record, 2443, 0.0)
  for reverse in [false, true] {
    let c = NavCatalog::new()
    let ordered = if reverse { [right, left] } else { [left, right] }
    for r in ordered {
      ignore(c.add(r))
    }
    guard c.query("G01", NavTime::week(2442, 604791.9999999)) is Selected(a) else {
      abort("left side")
    }
    assert_eq(a.record.toe.gps_ticks, left.toe.gps_ticks)
    guard c.query("G01", NavTime::week(2442, 604792.0000001)) is Selected(b) else {
      abort("right side")
    }
    assert_eq(b.record.toe.gps_ticks, right.toe.gps_ticks)
    guard c.query("G01", NavTime::week(2442, 604792.0)) is Selected(tie) else {
      abort("latest toc tie")
    }
    assert_eq(tie.record.toc.gps_ticks, right.toc.gps_ticks)
  }
}

///|
test "catalog equivalent ties conflicts and better candidate reset" {
  let base = catalog_test_records()[0]
  let c = NavCatalog::new()
  assert_eq(c.add(base, source_line=4), 1)
  assert_eq(c.add(base, source_line=12), 2)
  assert_true(c.record(0) is None)
  assert_true(c.record(3) is None)
  assert_eq(c.record(1).unwrap().satellite, "G01")
  guard c.query("G01", base.toe) is Selected(equal) else {
    abort("equivalent record")
  }
  assert_eq(equal.record.record_index, 1)
  assert_eq(equal.equivalent_records, 2)
  let clock = base.clock.copy()
  clock[0] += 0.000001
  let conflict : NavRecord = { ..base, clock, }
  assert_eq(c.add(conflict, source_line=20), 3)
  guard c.query("G01", base.toe) is NavQueryOutcome::Conflict(ties) else {
    abort("conflicting model must not be silently selected")
  }
  assert_eq(ties.tied_records, 3)
  assert_eq(ties.candidates.map(x => x.record_index), [1, 2, 3])
  let better = catalog_test_retime(base, 2442, 46816.0)
  assert_eq(c.add(better), 4)
  guard c.query("G01", better.toe) is Selected(selected) else {
    abort("better rank must clear previous conflict")
  }
  assert_eq(selected.record.record_index, 4)
  assert_eq(selected.equivalent_records, 1)
}

///|
test "catalog rejection totals stay exact when samples are capped" {
  let base = catalog_test_records()[0]
  let unhealthy : NavRecord = { ..base, health: 1, }
  let c = NavCatalog::new(capacity=140)
  for i in 0..<130 {
    ignore(c.add(unhealthy, source_line=i + 1))
  }
  guard c.query("G01", base.toe) is Unavailable(report) else {
    abort("all unhealthy")
  }
  assert_eq(report.candidates, 130)
  assert_eq(report.rejected, 130)
  assert_eq(report.rejection_counts.get("unhealthy"), Some(130))
  assert_eq(report.rejection_samples.length(), 128)
  assert_eq(report.omitted_rejections, 2)
  report.rejection_samples.clear()
  report.rejection_counts["unhealthy"] = 0
  guard c.query("G01", base.toe) is Unavailable(again) else {
    abort("fresh query")
  }
  assert_eq(again.rejection_samples.length(), 128)
  assert_eq(again.rejection_counts.get("unhealthy"), Some(130))
}

///|
test "catalog bounded tie evidence exposes a late conflicting record" {
  let base = catalog_test_records()[0]
  let c = NavCatalog::new(capacity=140)
  for _ in 0..<129 {
    ignore(c.add(base))
  }
  let clock = base.clock.copy()
  clock[0] += 0.000001
  ignore(c.add({ ..base, clock, }))
  guard c.query("G01", base.toe) is NavQueryOutcome::Conflict(report) else {
    abort("late conflict")
  }
  assert_eq(report.tied_records, 130)
  assert_eq(report.candidates.length(), 128)
  assert_eq(report.omitted_candidates, 2)
  assert_eq(report.candidates[0].record_index, 1)
  assert_true(report.candidates.iter().any(x => x.record_index == 130))
}

///|
test "catalog capacity and argument failures leave stored records intact" {
  let base = catalog_test_records()[0]
  for limit in [-1, 0, 32769] {
    assert_true(
      try {
        ignore(NavCatalog::new(capacity=limit))
        false
      } catch {
        InvalidCatalogInput(_) => true
        _ => false
      },
    )
  }
  let c = NavCatalog::new(capacity=1)
  assert_true(
    try {
      ignore(c.add(base, source_line=-1))
      false
    } catch {
      InvalidCatalogInput(_) => true
      _ => false
    },
  )
  assert_eq(c.len(), 0)
  assert_true(
    try {
      ignore(c.add({ ..base, satellite: "R01", }))
      false
    } catch {
      InvalidCatalogInput(_) => true
      _ => false
    },
  )
  assert_eq(c.add(base), 1)
  assert_true(
    try {
      ignore(c.add(base))
      false
    } catch {
      CatalogCapacityExceeded => true
      _ => false
    },
  )
  assert_eq(c.len(), 1)
  assert_true(c.query("G01", base.toe) is Selected(_))
  for satellite in ["G00", "G 1", "R01", "x"] {
    assert_true(
      try {
        ignore(c.query(satellite, base.toe))
        false
      } catch {
        InvalidCatalogInput(_) => true
        _ => false
      },
    )
  }
  let empty = NavCatalog::new()
  for age in [-1.0, 0.0, 14401.0, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(
      try {
        ignore(empty.query("G01", base.toe, max_age_seconds=age))
        false
      } catch {
        InvalidCatalogInput(_) => true
        _ => false
      },
    )
  }
}

///|
test "catalog preserves propagation failures and cannot bypass GPS fit bounds" {
  let base = catalog_test_records()[0]
  let invalid_data = base.data.copy()
  invalid_data[7] = Some(0.0)
  let divergent_data = base.data.copy()
  divergent_data[3] = Some(0.000001)
  divergent_data[5] = Some(0.999999999)
  let c = NavCatalog::new()
  ignore(c.add({ ..base, data: invalid_data, }))
  ignore(c.add({ ..base, data: divergent_data, }))
  guard c.query("G01", base.toe) is Unavailable(bad) else {
    abort("invalid models")
  }
  assert_eq(bad.rejection_counts.get("invalid-model"), Some(1))
  assert_eq(bad.rejection_counts.get("non-convergence"), Some(1))
  ignore(c.add(base))
  guard c.query("G01", base.toe) is Selected(good) else {
    abort("healthy model fallback")
  }
  assert_eq(good.record.record_index, 3)
  assert_eq(good.report.rejected, 2)
  let farther = catalog_test_retime(base, 2442, 45792.0)
  let data = farther.data.copy()
  data[25] = Some(8.0)
  let fit = NavCatalog::new()
  ignore(fit.add(base))
  ignore(fit.add({ ..farther, data, }))
  guard fit.query("G01", base.toe.offset_seconds(8000), max_age_seconds=14400.0)
    is Selected(long_fit) else {
    abort("declared eight-hour fit")
  }
  assert_eq(long_fit.record.record_index, 2)
  assert_eq(long_fit.report.rejection_counts.get("expired"), Some(1))
  let bds = catalog_test_records()[3]
  let bds_catalog = NavCatalog::new()
  ignore(bds_catalog.add(bds))
  assert_true(
    bds_catalog.query(
      "C01",
      bds.toe.offset_seconds(8000),
      max_age_seconds=14400.0,
    )
    is Unavailable(_),
  )
}
