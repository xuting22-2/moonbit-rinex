///|
pub suberror CheckError {
  Rejected(String, Int, String)
} derive(@debug.Debug)

///|
pub struct Window {
  start : Int64
  stop : Int64
  kind : String
} derive(ToJson, @debug.Debug)

///|
pub(all) struct Finding {
  code : String
  line : Int
  error : Bool
  detail : String
} derive(ToJson, @debug.Debug)

///|
pub struct Header {
  version : String
  marker : String
  time_system : String
  first : Int64
  last : Int64?
  interval : Int64?
  declared_satellites : Int?
  license : String
  doi : String
  observation_types : Map[String, Array[String]]
  uninterpreted_labels : Array[String]
} derive(ToJson, @debug.Debug)

///|
pub struct SignalCounts {
  code : String
  nonempty_fields : Int
  blank_fields : Int
  zero_values : Int
  lli_nonzero : Int
  lli_bit0 : Int
  lli_bit1 : Int
  lli_bit2 : Int
} derive(ToJson, @debug.Debug)

///|
pub struct SystemCounts {
  system : String
  records : Int
  satellites : Array[String]
  signals : Array[SignalCounts]
} derive(ToJson, @debug.Debug)

///|
pub struct Report {
  complete : Bool
  acceptable : Bool
  profile : String
  time_unit : String
  header : Header
  epochs : Int
  records : Int
  first : Int64
  last : Int64
  missing_epoch_slots : Int
  power_failure_epochs : Int
  receiver_clock_epochs : Int
  systems : Array[SystemCounts]
  findings : Array[Finding]
  finding_counts : Map[String, Int]
  omitted_findings : Int
} derive(ToJson, @debug.Debug)

///|
struct SignalCounter {
  code : String
  mut nonempty_fields : Int
  mut blank_fields : Int
  mut zero_values : Int
  mut lli_nonzero : Int
  mut lli_bit0 : Int
  mut lli_bit1 : Int
  mut lli_bit2 : Int
}

///|
pub struct Checker {
  window : Window?
  mut line : Int
  mut bytes : Int
  mut closed : Bool
  mut body : Bool
  mut version : String
  mut marker : String
  mut file_system : String
  mut time_system : String
  mut last_time_system : String
  mut header_first : Int64?
  mut header_last : Int64?
  mut interval : Int64?
  mut declared_satellites : Int?
  mut license : String
  mut doi : String
  mut station : String
  mut clock_applied : Int?
  types : Map[String, Array[String]]
  expected_types : Map[String, Int]
  headers_seen : Map[String, Int]
  other_labels : Map[String, Bool]
  mut continuation : String?
  prn_headers : Map[String, Bool]
  counts : Map[String, Array[SignalCounter]]
  system_records : Map[String, Int]
  satellites : Map[String, Bool]
  epoch_satellites : Map[String, Bool]
  mut remaining : Int
  mut epochs : Int
  mut records : Int
  mut first : Int64?
  mut last : Int64?
  mut missing : Int
  mut power : Int
  mut clocks : Int
  mut errors : Int
  findings : Array[Finding]
  finding_counts : Map[String, Int]
  mut total_findings : Int
}

///|
pub fn Checker::new(window? : Window) -> Checker {
  {
    window,
    line: 0,
    bytes: 0,
    closed: false,
    body: false,
    version: "",
    marker: "",
    file_system: "",
    time_system: "",
    last_time_system: "",
    header_first: None,
    header_last: None,
    interval: None,
    declared_satellites: None,
    license: "",
    doi: "",
    station: "",
    clock_applied: None,
    types: {},
    expected_types: {},
    headers_seen: {},
    other_labels: {},
    continuation: None,
    prn_headers: {},
    counts: {},
    system_records: {},
    satellites: {},
    epoch_satellites: {},
    remaining: 0,
    epochs: 0,
    records: 0,
    first: None,
    last: None,
    missing: 0,
    power: 0,
    clocks: 0,
    errors: 0,
    findings: [],
    finding_counts: {},
    total_findings: 0,
  }
}

///|
fn Checker::note(
  self : Checker,
  code : String,
  detail : String,
  error? : Bool = true,
  at? : Int = 0,
) -> Unit {
  if error {
    self.errors += 1
  }
  self.total_findings += 1
  self.finding_counts[code] = self.finding_counts.get(code).unwrap_or(0) + 1
  if self.findings.length() < 128 {
    self.findings.push({
      code,
      line: if at == 0 {
        self.line
      } else {
        at
      },
      error,
      detail,
    })
  }
}

///|
fn Checker::reject(
  self : Checker,
  code : String,
  detail : String,
) -> Unit raise CheckError {
  raise Rejected(code, self.line, detail)
}
