// Complete independently handwritten preimplementation CRINEX/RNX fixtures.

///|
fn recovery11_input(legacy : Bool, scenario : String) -> Array[String] {
  match (legacy, scenario) {
    (false, "loss") =>
      [
        "3.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "G    1 L1C                                                  SYS / # / OBS TYPES",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "> 2026 10 29 00 00  0.0000000  0  1      G01", "", "bad &&", "&", "> 2026 10 29 00 00 30.0000000  0  0",
        "0&125000000000", " &2026&10&29&00&01&&0.0000000&&0&&1&&&&&&G01", "", "3&-12345 &&",
        " &2026&10&29&00&01&30.0000000&&0&&1&&&&&&G01", "", "1000 15",
      ]
    (false, "clean") =>
      [
        "3.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "G    1 L1C                                                  SYS / # / OBS TYPES",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "> 2026 10 29 00 00  0.0000000  0  1      G01", "", "3&4000 &&", "&", "> 2026 10 29 00 00 30.0000000  0  0",
        "0&125000000000", " &2026&10&29&00&01&&0.0000000&&0&&1&&&&&&G01", "", "3&-12345 &&",
        " &2026&10&29&00&01&30.0000000&&0&&1&&&&&&G01", "", "1000 15",
      ]
    (false, "unsynchronized") =>
      [
        "3.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "G    1 L1C                                                  SYS / # / OBS TYPES",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "> 2026 10 29 00 00  0.0000000  0  1      G01", "", "bad &&", "&", " &2026&10&29&00&00&30.0000000&&0&&0&&&&&&&&&",
        "0&125000000000", " &2026&10&29&00&01&&0.0000000&&0&&1&&&&&&G01", "", "3&-12345 &&",
        " &2026&10&29&00&01&30.0000000&&0&&1&&&&&&G01", "", "1000 15", "> 2026 10 29 00 02  0.0000000  0  1      G01",
        "", "3&-10000 &&", " &2026&10&29&00&02&30.0000000&&0&&1&&&&&&G01", "", "3000 15",
      ]
    (false, "missing-clock") =>
      [
        "3.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "G    1 L1C                                                  SYS / # / OBS TYPES",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "> 2026 10 29 00 00  0.0000000  0  1      G01", "", "bad &&", "&", "> 2026 10 29 00 00 30.0000000  0  0",
      ]
    (false, "broken-clock") =>
      [
        "3.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "G    1 L1C                                                  SYS / # / OBS TYPES",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "> 2026 10 29 00 00  0.0000000  0  1      G01", "", "bad &&", "&", "> 2026 10 29 00 00 30.0000000  0  0",
        "0&bad",
      ]
    (true, "loss") =>
      [
        "1.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "     1    L1                                                # / TYPES OF OBSERV",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "&26 10 29  0  0  0.0000000  0  1G01", "", "bad &&", "&26 10 29  0  0 30.0000000  1  0",
        "0&125000000", " 26&10&29&&0&&1&&0.0000000&&0&&1G01", "", "3&-12345 &&",
        " 26&10&29&&0&&1&30.0000000&&0&&1G01", "", "1000 15",
      ]
    (true, "clean") =>
      [
        "1.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "     1    L1                                                # / TYPES OF OBSERV",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "&26 10 29  0  0  0.0000000  0  1G01", "", "3&4000 &&", "&26 10 29  0  0 30.0000000  1  0",
        "0&125000000", " 26&10&29&&0&&1&&0.0000000&&0&&1G01", "", "3&-12345 &&",
        " 26&10&29&&0&&1&30.0000000&&0&&1G01", "", "1000 15",
      ]
    (true, "unsynchronized") =>
      [
        "1.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "     1    L1                                                # / TYPES OF OBSERV",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "&26 10 29  0  0  0.0000000  0  1G01", "", "bad &&", " 26&10&29&&0&&0&30.0000000&&1&&0&&&",
        "0&125000000", " 26&10&29&&0&&1&&0.0000000&&0&&1G01", "", "3&-12345 &&",
        " 26&10&29&&0&&1&30.0000000&&0&&1G01", "", "1000 15", "&26 10 29  0  2  0.0000000  0  1G01",
        "", "3&-10000 &&", " 26&10&29&&0&&2&30.0000000&&0&&1G01", "", "3000 15",
      ]
    (true, "missing-clock") =>
      [
        "1.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "     1    L1                                                # / TYPES OF OBSERV",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "&26 10 29  0  0  0.0000000  0  1G01", "", "bad &&", "&26 10 29  0  0 30.0000000  1  0",
      ]
    (true, "broken-clock") =>
      [
        "1.0                                                         CRINEX VERS   / TYPE",
        "R11 HAND AUTHORED RECOVERY CONTRACT                         CRINEX PROG / DATE",
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "     1    L1                                                # / TYPES OF OBSERV",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "&26 10 29  0  0  0.0000000  0  1G01", "", "bad &&", "&26 10 29  0  0 30.0000000  1  0",
        "0&bad",
      ]
    _ => abort("unknown frozen recovery fixture")
  }
}

///|
fn recovery11_expected(legacy : Bool, scenario : String) -> Array[String] {
  match (legacy, scenario) {
    (false, "loss") =>
      [
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "G    1 L1C                                                  SYS / # / OBS TYPES",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "> 2026 10 29 00 00 30.0000000  0  0        .125000000000", "> 2026 10 29 00 01  0.0000000  0  1",
        "G01       -12.345", "> 2026 10 29 00 01 30.0000000  0  1", "G01       -11.34515",
      ]
    (false, "clean") =>
      [
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "G    1 L1C                                                  SYS / # / OBS TYPES",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "> 2026 10 29 00 00  0.0000000  0  1", "G01         4.000", "> 2026 10 29 00 00 30.0000000  0  0        .125000000000",
        "> 2026 10 29 00 01  0.0000000  0  1", "G01       -12.345", "> 2026 10 29 00 01 30.0000000  0  1",
        "G01       -11.34515",
      ]
    (false, "unsynchronized") =>
      [
        "     3.04           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "G    1 L1C                                                  SYS / # / OBS TYPES",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        "> 2026 10 29 00 02  0.0000000  0  1", "G01       -10.000", "> 2026 10 29 00 02 30.0000000  0  1",
        "G01        -7.00015",
      ]
    (true, "loss") =>
      [
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "     1    L1                                                # / TYPES OF OBSERV",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        " 26 10 29  0  0 30.0000000  1  0                                      .125000000",
        " 26 10 29  0  1  0.0000000  0  1G01", "       -12.345", " 26 10 29  0  1 30.0000000  0  1G01",
        "       -11.34515",
      ]
    (true, "clean") =>
      [
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "     1    L1                                                # / TYPES OF OBSERV",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        " 26 10 29  0  0  0.0000000  0  1G01", "         4.000", " 26 10 29  0  0 30.0000000  1  0                                      .125000000",
        " 26 10 29  0  1  0.0000000  0  1G01", "       -12.345", " 26 10 29  0  1 30.0000000  0  1G01",
        "       -11.34515",
      ]
    (true, "unsynchronized") =>
      [
        "     2.11           OBSERVATION DATA    G                   RINEX VERSION / TYPE",
        "R11 SYNTHETIC EMPTY RECOVERY                                MARKER NAME",
        "MIT                                                         LICENSE OF USE",
        "     1    L1                                                # / TYPES OF OBSERV",
        "  2026    10    29     0     0    0.0000000     GPS         TIME OF FIRST OBS",
        "     0                                                      RCV CLOCK OFFS APPL",
        "                                                            END OF HEADER",
        " 26 10 29  0  2  0.0000000  0  1G01", "       -10.000", " 26 10 29  0  2 30.0000000  0  1G01",
        "        -7.00015",
      ]
    _ => abort("unknown frozen recovery fixture")
  }
}

///|
fn recovery11_decode(
  legacy : Bool,
  scenario : String,
) -> (Array[String], CrinexReport) raise CheckError {
  let decoder = CrinexDecoder::new(recover=true)
  let output : Array[String] = []
  for row in recovery11_input(legacy, scenario) {
    for line in decoder.feed_line(row) {
      output.push(line)
    }
  }
  let report = decoder.finish()
  (output, report)
}

///|
test "recovery full initialized zero-SV epoch resumes both CRINEX differential streams" {
  for legacy in [false, true] {
    let (output, report) = recovery11_decode(legacy, "loss")
    assert_eq(output.join("\n"), recovery11_expected(legacy, "loss").join("\n"))
    assert_eq(report.epochs, 3)
    assert_eq(report.recovered_epochs, 1)
    assert_true(!report.complete && !report.acceptable)
    assert_eq(report.findings.length(), 1)
    assert_eq(report.findings[0].code, "crx-unsynchronized")
    assert_eq(report.findings[0].line, 12)
  }
}

///|
test "recovery clean streams and noninitialized empty epochs keep their contracts" {
  for legacy in [false, true] {
    let (clean, good) = recovery11_decode(legacy, "clean")
    assert_eq(clean.join("\n"), recovery11_expected(legacy, "clean").join("\n"))
    assert_eq(good.epochs, 4)
    assert_eq(good.recovered_epochs, 0)
    assert_true(good.complete && good.acceptable)
    let (skipped, loss) = recovery11_decode(legacy, "unsynchronized")
    assert_eq(
      skipped.join("\n"),
      recovery11_expected(legacy, "unsynchronized").join("\n"),
    )
    assert_eq(loss.epochs, 2)
    assert_eq(loss.recovered_epochs, 1)
    assert_true(!loss.complete && !loss.acceptable)
  }
}

///|
test "recovery empty reinitialization requires a successful complete clock and seals failures" {
  for legacy in [false, true] {
    for scenario in ["missing-clock", "broken-clock"] {
      let d = CrinexDecoder::new(recover=true)
      let mut caught = false
      let mut output = 0
      try {
        for row in recovery11_input(legacy, scenario) {
          output += d.feed_line(row).length()
        }
        ignore(d.finish())
      } catch {
        Rejected(code, _, _) => {
          assert_eq(
            code,
            if scenario == "missing-clock" {
              "crx-truncated"
            } else {
              "integer64"
            },
          )
          caught = true
        }
      }
      assert_true(caught)
      assert_eq(output, 7)
      assert_true(
        try {
          ignore(d.feed_line(""))
          false
        } catch {
          _ => true
        },
      )
      assert_true(
        try {
          ignore(d.finish())
          false
        } catch {
          _ => true
        },
      )
    }
  }
}
