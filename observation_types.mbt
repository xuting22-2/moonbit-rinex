///|
/// One stored observation slot. Numeric zero is retained, not declared usable.
/// raw_field contains only characters present in the source, without padding.
pub struct ObservationValue {
  code : String
  column : Int
  raw_field : String
  value : Double?
  lli : Int?
  ssi : Int?
} derive(@debug.Debug)

///|
pub impl ToJson for ObservationValue with fn to_json(self) -> Json {
  {
    "code": self.code.to_json(),
    "column": self.column.to_json(),
    "raw_field": self.raw_field.to_json(),
    "value": match self.value {
      Some(v) => v.to_json()
      None => Json::null()
    },
    "lli": match self.lli {
      Some(v) => v.to_json()
      None => Json::null()
    },
    "ssi": match self.ssi {
      Some(v) => v.to_json()
      None => Json::null()
    },
  }
}

///|
pub struct SatelliteObservation {
  satellite : String
  line : Int
  raw_record : String
  observations : Array[ObservationValue]
} derive(ToJson, @debug.Debug)

///|
/// A complete flag-0/1 epoch. Clock, scale and other header corrections are not
/// applied; raw records and the raw header let callers retain their semantics.
pub struct ObservationEpoch {
  gps_ticks : Int64
  flag : Int
  line : Int
  end_line : Int
  raw_record : String
  receiver_clock : Double?
  receiver_clock_raw : String
  satellites : Array[SatelliteObservation]
} derive(@debug.Debug)

///|
pub impl ToJson for ObservationEpoch with fn to_json(self) -> Json {
  {
    "gps_ticks": self.gps_ticks.to_json(),
    "flag": self.flag.to_json(),
    "line": self.line.to_json(),
    "end_line": self.end_line.to_json(),
    "raw_record": self.raw_record.to_json(),
    "receiver_clock": match self.receiver_clock {
      Some(v) => v.to_json()
      None => Json::null()
    },
    "receiver_clock_raw": self.receiver_clock_raw.to_json(),
    "satellites": self.satellites.to_json(),
  }
}

///|
pub struct ObservationHeader {
  parsed : Header
  raw_lines : Array[String]
} derive(ToJson, @debug.Debug)

///|
priv struct EpochStart {
  gps_ticks : Int64
  flag : Int
  line : Int
  raw_record : String
  receiver_clock : Double?
  receiver_clock_raw : String
}

///|
priv enum ParsedLine {
  Epoch(EpochStart)
  Satellite(SatelliteObservation)
}

///|
priv struct PendingEpoch {
  start : EpochStart
  selected : Bool
  satellites : Array[SatelliteObservation]
}

///|
pub extend ObservationValue with ToJson::{to_json}

///|
pub extend ObservationValue with @debug.Debug::{to_repr}

///|
pub extend SatelliteObservation with ToJson::{to_json}

///|
pub extend SatelliteObservation with @debug.Debug::{to_repr}

///|
pub extend ObservationEpoch with ToJson::{to_json}

///|
pub extend ObservationEpoch with @debug.Debug::{to_repr}

///|
pub extend ObservationHeader with ToJson::{to_json}

///|
pub extend ObservationHeader with @debug.Debug::{to_repr}
