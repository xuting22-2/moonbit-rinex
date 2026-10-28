///|
/// Accept already-normalized GPST calendar ticks from Reader/LegacyReader.
/// Exact 100ns since 1980-01-01, within their supported years 1980..2100.
/// This does not infer a time scale, apply receiver clock offsets or finish input.
pub fn NavTime::from_gps_ticks(gps_ticks : Int64) -> NavTime raise NavError {
  let stop = (try! day_ticks(2100, 12, 31)) + 864000000000L
  if gps_ticks < 0L || gps_ticks >= stop {
    raise InvalidNavigation("GPS calendar ticks require years 1980..2100")
  }
  { gps_ticks, }
}
