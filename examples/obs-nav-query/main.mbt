///|
fn main raise {
  let modern = modern_observation()
  let legacy = legacy_observation()
  let catalog = navigation_catalog()
  let modern_time = @r.NavTime::from_gps_ticks(modern.gps_ticks)
  let legacy_time = @r.NavTime::from_gps_ticks(legacy.gps_ticks)
  if modern_time.gps_ticks != 14774041000000001L ||
    legacy_time.gps_ticks != modern_time.gps_ticks {
    abort("exact observation time")
  }
  guard catalog.query("G01", modern_time) is @r.Selected(modern_selection) else {
    abort("modern query")
  }
  guard catalog.query("G01", legacy_time) is @r.Selected(legacy_selection) else {
    abort("legacy query")
  }
  if modern_selection.record.record_index != 1 ||
    modern_selection.record.source_line != 4 {
    abort("navigation provenance")
  }
  let output : Json = {
    "time": modern_time.to_json(),
    "modern": modern_selection.to_json(),
    "legacy": legacy_selection.to_json(),
    "modern_receiver_clock": modern.receiver_clock.to_json(),
    "legacy_receiver_clock": legacy.receiver_clock.to_json(),
  }
  println(output.stringify())
}
