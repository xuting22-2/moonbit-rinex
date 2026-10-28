// Project-authored observation rows and existing authored GPS parameters.

///|
fn modern_rows() -> Array[String] {
  [
    "     3.05           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "SYNTHETIC OBS NAV TIME                                      MARKER NAME", "G    1 C1C                                                  SYS / # / OBS TYPES",
    "  2026    10    25    14     1   40.0000001     GPS         TIME OF FIRST OBS",
    "     0                                                      RCV CLOCK OFFS APPL",
    "                                                            END OF HEADER",
    "> 2026 10 25 14 01 40.0000001  0  1            0.0001234", "G01  20000000.000 7",
  ]
}

///|
fn legacy_rows() -> Array[String] {
  [
    "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
    "SYNTHETIC OBS NAV TIME                                      MARKER NAME", "     1    C1                                                # / TYPES OF OBSERV",
    "  2026    10    25    14     1   40.0000001     GPS         TIME OF FIRST OBS",
    "     0                                                      RCV CLOCK OFFS APPL",
    "                                                            END OF HEADER",
    " 26 10 25 14  1 40.0000001  0  1G01                                   0.00012340",
    "  20000000.000 7",
  ]
}

///|
fn nav_rows() -> Array[String] {
  [
    "     3.05           NAVIGATION DATA     MIXED               RINEX VERSION / TYPE",
    "Project-authored synthetic selection example; no measurementsCOMMENT", "                                                            END OF HEADER",
    "G01 2026 10 25 13 00 00 1.100000000000E-04 1.000000000000E-12 0.000000000000E+00",
    "     1.000000000000E+00 0.000000000000E+00 0.000000000000E+00 1.000000000000E-01",
    "     0.000000000000E+00 1.000000000000E-02 0.000000000000E+00 5.153795500000E+03",
    "     4.680000000000E+04 0.000000000000E+00 5.000000000000E-01 0.000000000000E+00",
    "     9.500000000000E-01 0.000000000000E+00 3.000000000000E-01-8.000000000000E-09",
    "     0.000000000000E+00 0.000000000000E+00 2.442000000000E+03 0.000000000000E+00",
    "     2.000000000000E+00 0.000000000000E+00 1.000000000000E-09 1.000000000000E+00",
    "     4.680000000000E+04 4.000000000000E+00                                      ",
  ]
}

///|
fn modern_observation() -> @r.ObservationEpoch raise {
  let reader = @r.Reader::new()
  let mut found : @r.ObservationEpoch? = None
  for row in modern_rows() {
    if reader.feed_line(row) is Some(epoch) {
      found = Some(epoch)
    }
  }
  let report = reader.finish()
  if !report.complete || !report.acceptable {
    abort("incomplete observation input")
  }
  found.unwrap()
}

///|
fn legacy_observation() -> @r.LegacyEpoch raise {
  let reader = @r.LegacyReader::new()
  let mut found : @r.LegacyEpoch? = None
  for row in legacy_rows() {
    if reader.feed_line(row) is Some(@r.Epoch(epoch)) {
      found = Some(epoch)
    }
  }
  reader.finish()
  found.unwrap()
}

///|
fn navigation_catalog() -> @r.NavCatalog raise {
  let reader = @r.NavReader::new()
  let catalog = @r.NavCatalog::new()
  let mut line = 0
  for row in nav_rows() {
    line += 1
    if reader.feed_line(row) is Some(record) {
      ignore(catalog.add(record, source_line=line - 7))
    }
  }
  reader.finish()
  catalog
}
