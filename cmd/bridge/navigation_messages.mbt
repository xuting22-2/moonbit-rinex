///|
pub struct NavigationSession {
  priv reader : @r.NavigationReader
  priv mut latest : @r.NavigationMessage?
}

///|
pub fn navigation_create() -> NavigationSession {
  { reader: @r.NavigationReader::new(), latest: None, }
}

///|
pub fn navigation_header(session : NavigationSession) -> String {
  session.reader.header_lines().to_json().stringify()
}

///|
pub fn navigation_feed(session : NavigationSession, line : String) -> String {
  try {
    session.latest = session.reader.feed_line(line)
    match session.latest {
      Some(m) => m.to_json().stringify()
      None => ""
    }
  } catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
pub fn navigation_finish(session : NavigationSession) -> String {
  try {
    let final_record = session.reader.finish()
    session.latest = final_record
    let record : Json = match final_record {
      Some(m) => m.to_json()
      None => Json::null()
    }
    let json : Json = {
      "final_record": record,
      "records": session.reader.record_count().to_json(),
      "unsupported_records": session.reader.unsupported_records().to_json(),
      "all_supported": (session.reader.unsupported_records() == 0).to_json(),
      "header_lines": session.reader.header_lines().to_json(),
    }
    json.stringify()
  } catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
pub fn navigation_evaluate(
  session : NavigationSession,
  seconds : Double,
  signal : String,
  orbit : Int,
  max_age : Double,
) -> String {
  try {
    let message = match session.latest {
      Some(m) => m
      None => {
        fail("no latest navigation record")
        return ""
      }
    }
    match message.category {
      "STO" => message.system_time_offset(seconds).to_json().stringify()
      "EOP" => message.earth_orientation(seconds).to_json().stringify()
      "EPH" => {
        let bds_orbit = match orbit {
          0 => None
          1 => Some(@r.BdsOrbit::MEO_IGSO)
          2 => Some(@r.BdsOrbit::GEO)
          _ => {
            fail("orbit must be0/1/2")
            return ""
          }
        }
        message
        .state_at_offset(seconds, signal~, bds_orbit?, max_age_seconds=max_age)
        .to_json()
        .stringify()
      }
      _ => {
        fail("no numerical evaluator for this category")
        ""
      }
    }
  } catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}
