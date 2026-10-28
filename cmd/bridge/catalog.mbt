///|
pub struct CatalogSession {
  priv reader : @r.NavReader
  priv catalog : @r.NavCatalog
  priv mut lines : Int
  priv mut closed : Bool
  priv mut ready : Bool
}

///|
pub fn nav_catalog_create(capacity : Int, skip : Bool) -> CatalogSession {
  {
    reader: @r.NavReader::new(skip_unsupported=skip),
    catalog: @r.NavCatalog::new(capacity~),
    lines: 0,
    closed: false,
    ready: false,
  } catch {
    error => {
      fail(@debug.to_string(error))
      abort("catalog creation failed")
    }
  }
}

///|
pub fn nav_catalog_feed(session : CatalogSession, line : String) -> Unit {
  try {
    if session.closed {
      raise Failure("catalog input failed or finished")
    }
    session.lines += 1
    if session.reader.feed_line(line) is Some(record) {
      // Both supported NAV2/3 GPS/BDS formats have eight-line records.
      ignore(session.catalog.add(record, source_line=session.lines - 7))
    }
  } catch {
    error => {
      session.closed = true
      session.ready = false
      fail(@debug.to_string(error))
    }
  }
}

///|
pub fn nav_catalog_finish(session : CatalogSession) -> String {
  try {
    if session.closed {
      raise Failure("catalog input failed or finished")
    }
    session.reader.finish()
    session.closed = true
    session.ready = true
    let report : Json = {
      "complete": true,
      "stored_records": session.catalog.len().to_json(),
      "skipped_unsupported": session.reader.skipped_records().to_json(),
    }
    report.stringify()
  } catch {
    error => {
      session.closed = true
      session.ready = false
      fail(@debug.to_string(error))
      ""
    }
  }
}

///|
pub fn nav_catalog_query(
  session : CatalogSession,
  satellite : String,
  week : Int,
  sow : Double,
  bdt : Bool,
  orbit : Int,
  max_age : Double,
) -> String {
  try {
    let (output, _) = catalog_evaluate(
      session, satellite, week, sow, bdt, orbit, max_age,
    )
    output.stringify()
  } catch {
    error => {
      fail(@debug.to_string(error))
      ""
    }
  }
}

///|
fn catalog_evaluate(
  session : CatalogSession,
  satellite : String,
  week : Int,
  sow : Double,
  bdt : Bool,
  orbit : Int,
  max_age : Double,
) -> (Json, Int) raise {
  if !session.ready {
    raise Failure("catalog requires a successfully finished input")
  }
  let time = @r.NavTime::week(week, sow, bdt~)
  catalog_evaluate_at(session, satellite, time, orbit, max_age)
}

///|
fn catalog_evaluate_at(
  session : CatalogSession,
  satellite : String,
  time : @r.NavTime,
  orbit : Int,
  max_age : Double,
) -> (Json, Int) raise {
  let bds_orbit = match orbit {
    0 => None
    1 => Some(@r.GEO)
    2 => Some(@r.MEO_IGSO)
    _ => raise Failure("invalid BDS orbit option")
  }
  let result = session.catalog.query(
    satellite,
    time,
    bds_orbit?,
    max_age_seconds=max_age,
  )
  match result {
    @r.Selected(selection) =>
      ({ "status": "selected", "selection": selection.to_json() }, 0)
    @r.Unavailable(report) =>
      ({ "status": "unavailable", "report": report.to_json() }, 1)
    @r.NavQueryOutcome::Conflict(conflict) =>
      ({ "status": "ambiguous", "conflict": conflict.to_json() }, 2)
  }
}

///|
fn batch_number(fields : Map[String, Json], key : String) -> Double raise {
  match fields.get(key) {
    Some(Json::Number(value, ..)) if !value.is_nan() && !value.is_inf() => value
    _ => raise Failure("invalid batch number " + key)
  }
}

///|
/// Fully normalized argument JSON from the host; MoonBit owns batch outcomes,
/// counters and atomic result construction as well as each query's semantics.
pub fn nav_catalog_query_batch(
  session : CatalogSession,
  input : String,
) -> String {
  try {
    if !session.ready {
      raise Failure("catalog requires a successfully finished input")
    }
    if input.length() > 1048576 {
      raise Failure("batch query JSON limit")
    }
    guard @json.parse(input) is Json::Array(requests) else {
      raise Failure("batch requires a query array")
    }
    if requests.length() < 1 || requests.length() > 256 {
      raise Failure("batch requires 1..256 queries")
    }
    let results : Array[Json] = []
    let mut selected = 0
    let mut unavailable = 0
    let mut ambiguous = 0
    for index, request in requests {
      let (result, status) = try {
        guard request is Json::Object(fields) else {
          raise Failure("query object required")
        }
        guard fields.get("satellite") is Some(Json::String(satellite)) else {
          raise Failure("satellite string required")
        }
        let time = match fields.get("gps_ticks") {
          Some(value) => {
            if fields.contains("week") ||
              fields.contains("sow") ||
              fields.contains("bdt") {
              raise Failure("gps_ticks cannot be combined with week/sow/bdt")
            }
            @r.NavTime::from_gps_ticks(exact_tick(value))
          }
          None => {
            let week = batch_number(fields, "week")
            if week < 0.0 || week > 7000.0 || week.to_int().to_double() != week {
              raise Failure("continuous week/sow out of range")
            }
            let bdt = match fields.get("bdt") {
              Some(Json::True) => true
              Some(Json::False) => false
              _ => raise Failure("bdt boolean required")
            }
            @r.NavTime::week(week.to_int(), batch_number(fields, "sow"), bdt~)
          }
        }
        let orbit = batch_number(fields, "orbit")
        if orbit < 0.0 || orbit > 2.0 || orbit.to_int().to_double() != orbit {
          raise Failure("invalid BDS orbit option")
        }
        catalog_evaluate_at(
          session,
          satellite,
          time,
          orbit.to_int(),
          batch_number(fields, "maxAge"),
        )
      } catch {
        error =>
          raise Failure(
            "query " + (index + 1).to_string() + ": " + @debug.to_string(error),
          )
      }
      match status {
        0 => selected += 1
        1 => unavailable += 1
        _ => ambiguous += 1
      }
      results.push({ "query_index": (index + 1).to_json(), "result": result })
    }
    let output : Json = {
      "results": Json::array(results),
      "summary": {
        "queries": requests.length().to_json(),
        "selected": selected.to_json(),
        "unavailable": unavailable.to_json(),
        "ambiguous": ambiguous.to_json(),
        "all_selected": (selected == requests.length()).to_json(),
      },
    }
    output.stringify()
  } catch {
    error => {
      fail(@debug.to_string(error))
      ""
    }
  }
}
