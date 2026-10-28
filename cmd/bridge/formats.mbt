///|
pub fn legacy_create() -> @r.LegacyReader {
  @r.LegacyReader::new()
}

///|
pub fn legacy_feed(reader : @r.LegacyReader, line : String) -> String {
  try {
    match reader.feed_line(line) {
      Some(item) => item.to_json().stringify()
      None => "null"
    }
  } catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
pub fn legacy_finish(reader : @r.LegacyReader) -> String {
  try {
    reader.finish()
    "{\"complete\":true}"
  } catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
pub fn crx_create(recover : Bool) -> @r.CrinexDecoder {
  @r.CrinexDecoder::new(recover~)
}

///|
pub fn crx_feed(decoder : @r.CrinexDecoder, line : String) -> String {
  decoder.feed_line(line).to_json().stringify() catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
pub fn crx_finish(decoder : @r.CrinexDecoder) -> String {
  decoder.finish().to_json().stringify() catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
pub fn nav_create(skip : Bool) -> @r.NavReader {
  @r.NavReader::new(skip_unsupported=skip)
}

///|
pub fn nav_feed(reader : @r.NavReader, line : String, orbit : Int) -> String {
  try {
    match reader.feed_line(line) {
      None => "null"
      Some(record) => {
        let states : Array[Json] = []
        for delta in [-1800, 0, 1800] {
          let at = record.toe.offset_seconds(delta)
          let bds_orbit = match orbit {
            1 => Some(@r.GEO)
            2 => Some(@r.MEO_IGSO)
            _ => None
          }
          let state = record.satellite_position(at, bds_orbit?)
          states.push({ "offset": delta.to_json(), "state": state.to_json() })
        }
        let result : Json = {
          "satellite": record.satellite.to_json(),
          "toc": record.toc.to_json(),
          "toe": record.toe.to_json(),
          "states": states.to_json(),
        }
        result.stringify()
      }
    }
  } catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
pub fn nav_finish(reader : @r.NavReader) -> String {
  try {
    reader.finish()
    "{\"complete\":true,\"skipped\":\{reader.skipped_records()}}"
  } catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}
