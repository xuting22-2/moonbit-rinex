///|
fn consume(lines : Array[String]) -> Report raise CheckError {
  let checker = Checker::new()
  for line in lines {
    checker.feed_line(line)
  }
  checker.finish()
}

///|
fn fixture() -> Array[String] {
  [
    "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
    "TEST00AAA                                                   MARKER NAME", "G    2 C1C L1C                                              SYS / # / OBS TYPES",
    "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
    "    30.000                                                  INTERVAL", "                                                            END OF HEADER",
    "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
    "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
  ]
}

///|
test "fixed-width fields and exact GPS timestamps preserve counters" {
  let result = consume(fixture())
  assert_true(result.complete && result.acceptable)
  assert_eq(result.epochs, 2)
  assert_eq(result.records, 2)
  assert_eq(result.last - result.first, 300000000L)
  assert_eq(result.first, 14745888000000000L)
  assert_eq(result.systems[0].signals[0].nonempty_fields, 2)
  assert_eq(result.systems[0].signals[1].lli_bit0, 2)
  assert_eq(result.systems[0].signals[1].lli_nonzero, 2)
}

///|
test "trailing blanks and omitted values do not become zero measurements" {
  let lines = fixture()
  lines[8] = "G01" + String::make(16, ' ') + "       123.00017"
  let result = consume(lines)
  assert_eq(result.systems[0].signals[0].blank_fields, 1)
  assert_eq(result.systems[0].signals[1].nonempty_fields, 2)
  let omitted = fixture()
  omitted[8] = "G01" + "       123.000"
  let short = consume(omitted)
  assert_eq(short.systems[0].signals[1].blank_fields, 1)
}

///|
test "poisoning and finish prevent using a partial stream as a report" {
  let checker = Checker::new()
  checker.feed_line("not a valid RINEX header") catch {
    Rejected(code, line, _) => {
      assert_eq(code, "header-width")
      assert_eq(line, 1)
    }
  }
  assert_true(
    try {
      ignore(checker.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
  assert_true(
    try {
      checker.feed_line(fixture()[0])
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
  let complete = Checker::new()
  for line in fixture() {
    complete.feed_line(line)
  }
  ignore(complete.finish())
  assert_true(
    try {
      ignore(complete.finish())
      false
    } catch {
      Rejected(code, _, _) => code == "state"
    },
  )
}

///|
test "calendar and decimal times are exact and bounded" {
  assert_eq(seconds_ticks("0.0000001"), 1L)
  assert_eq(day_ticks(2000, 3, 1) - day_ticks(2000, 2, 28), 1728000000000L)
  assert_eq(day_ticks(2100, 3, 1) - day_ticks(2100, 2, 28), 864000000000L)
  for parts in [(2100, 2, 29), (2026, 2, 29), (1979, 1, 1), (2026, 13, 1)] {
    assert_true(
      try {
        ignore(day_ticks(parts.0, parts.1, parts.2))
        false
      } catch {
        _ => true
      },
    )
  }
  for text in ["0.00000001", "-1", "1e2", "1.", "NaN"] {
    assert_true(
      try {
        ignore(seconds_ticks(text))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(Window::epn_hourly(2026, 9, 23, 24))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "delivery profile never hides missing day behind valid syntax" {
  let checker = Checker::new(window=Window::epn_daily(2026, 9, 23))
  for line in fixture() {
    checker.feed_line(line)
  }
  let result = checker.finish()
  assert_true(result.complete)
  assert_false(result.acceptable)
  assert_eq(result.finding_counts.get("profile-last"), Some(1))
  assert_eq(result.finding_counts.get("profile-epoch-count"), Some(1))
  assert_eq(result.finding_counts.get("profile-header-window"), Some(1))
}

///|
test "reject: duplicate satellite" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  2", "G01  20000000.000 7    123456.00017",
          "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "duplicate-satellite"
    },
  )
}

///|
test "reject: undeclared satellite" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "R01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "undeclared-system"
    },
  )
}

///|
test "reject: invalid PRN zero" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G00  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "satellite-id"
    },
  )
}

///|
test "reject: extra numeric field" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017         1.000  ",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "extra-observation-fields"
    },
  )
}

///|
test "reject: nonfinite value" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01           NaN      123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "observation-number"
    },
  )
}

///|
test "reject: bad LLI" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00087",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "lli"
    },
  )
}

///|
test "reject: bad SSI" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 x    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "ssi"
    },
  )
}

///|
test "reject: unsupported event" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  4  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "unsupported-event"
    },
  )
}

///|
test "reject: bad delimiter" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026x09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "epoch-layout"
    },
  )
}

///|
test "reject: shifted header" {
  assert_true(
    try {
      ignore(
        consume([
          "      4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "header-width"
    },
  )
}

///|
test "reject: bad code" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 X1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "observation-code"
    },
  )
}

///|
test "reject: short types" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    3 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "observation-types-count"
    },
  )
}

///|
test "reject: duplicate type" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C C1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "observation-code"
    },
  )
}

///|
test "reject: GPS only" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     UTC         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "time-system"
    },
  )
}

///|
test "reject: leap second unsupported" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00 60.0000000  0  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1", "G01  20000000.000 7    123456.00017",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "time"
    },
  )
}

///|
test "reject: partial final epoch" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
          "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
          "> 2026 09 23 00 00 30.0000000  0  1",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "truncated-epoch"
    },
  )
}

///|
test "reject: no END OF HEADER" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "truncated-header"
    },
  )
}

///|
test "reject: no epochs" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
          "TEST00AAA                                                   MARKER NAME",
          "G    2 C1C L1C                                              SYS / # / OBS TYPES",
          "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
          "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
          "    30.000                                                  INTERVAL",
          "                                                            END OF HEADER",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "empty-body"
    },
  )
}

///|
test "reject: oversized line" {
  assert_true(
    try {
      ignore(
        consume([
          "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "capacity"
    },
  )
}

///|
test "reject: control byte" {
  assert_true(
    try {
      ignore(
        consume([
          "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE\t",
        ]),
      )
      false
    } catch {
      Rejected(code, _, _) => code == "ascii"
    },
  )
}

///|
test "report duplicate" {
  let result = consume([
    "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
    "TEST00AAA                                                   MARKER NAME", "G    2 C1C L1C                                              SYS / # / OBS TYPES",
    "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
    "    30.000                                                  INTERVAL", "                                                            END OF HEADER",
    "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
    "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
  ])
  assert_true(result.complete)
  assert_false(result.acceptable)
  assert_eq(result.finding_counts.get("epoch-order"), Some(1))
}

///|
test "report off-grid" {
  let result = consume([
    "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
    "TEST00AAA                                                   MARKER NAME", "G    2 C1C L1C                                              SYS / # / OBS TYPES",
    "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
    "    30.000                                                  INTERVAL", "                                                            END OF HEADER",
    "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
    "> 2026 09 23 00 00 30.0000001  0  1", "G01  20000000.000 7    123456.00017",
  ])
  assert_true(result.complete)
  assert_false(result.acceptable)
  assert_eq(result.finding_counts.get("epoch-interval"), Some(1))
}

///|
test "report gap" {
  let result = consume([
    "     4.01           OBSERVATION DATA    M                   RINEX VERSION / TYPE",
    "TEST00AAA                                                   MARKER NAME", "G    2 C1C L1C                                              SYS / # / OBS TYPES",
    "  2026     9    23     0     0    0.0000000     GPS         TIME OF FIRST OBS",
    "  2026     9    23     0     0   30.0000000     GPS         TIME OF LAST OBS",
    "    30.000                                                  INTERVAL", "                                                            END OF HEADER",
    "> 2026 09 23 00 00  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
    "> 2026 09 23 00 01  0.0000000  0  1", "G01  20000000.000 7    123456.00017",
  ])
  assert_true(result.complete)
  assert_false(result.acceptable)
  assert_eq(result.finding_counts.get("epoch-interval"), Some(1))
}

///|
test "explicit zero numeric fields are counted separately from blanks" {
  let lines = fixture()
  lines[8] = "G01        -0.000 7              0 "
  let report = consume(lines)
  assert_eq(report.systems[0].signals[0].zero_values, 1)
  assert_eq(report.systems[0].signals[0].nonempty_fields, 2)
  assert_eq(report.systems[0].signals[0].blank_fields, 0)
  assert_eq(report.systems[0].signals[1].blank_fields, 1)
}
