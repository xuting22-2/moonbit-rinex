///|
test "max06 type metadata cannot be orphaned excess or replaced mid-declaration" {
  for legacy in [true, false] {
    let crx = right_pad(if legacy { "1.0" } else { "3.0" }, 60) +
      "CRINEX VERS   / TYPE"
    let version = right_pad(
        "     " +
        (if legacy { "2.11" } else { "3.04" }) +
        "           OBSERVATION DATA    G",
        60,
      ) +
      "RINEX VERSION / TYPE"
    let label = if legacy {
      "# / TYPES OF OBSERV"
    } else {
      "SYS / # / OBS TYPES"
    }
    let complete = if legacy { "     1    C1" } else { "G    1 C1C" }
    let orphan = if legacy { "          L1" } else { "       L1C" }
    let excess = if legacy { "     1    C1    L1" } else { "G    1 C1C L1C" }
    let partial = if legacy {
      "    10    C1    L1    D1    S1    P1    P2    C2    L2    D2"
    } else {
      "G   14 C1C L1C D1C S1C C1W L1W D1W S1W C2W L2W D2W S2W C5I"
    }
    for records in [[complete, orphan], [excess], [partial, complete]] {
      for recover in [false, true] {
        let decoder = CrinexDecoder::new(recover~)
        ignore(decoder.feed_line(crx))
        ignore(
          decoder.feed_line(right_pad("synthetic", 60) + "CRINEX PROG / DATE"),
        )
        ignore(decoder.feed_line(version))
        let rejected = try {
          for record in records {
            ignore(decoder.feed_line(right_pad(record, 60) + label))
          }
          ignore(decoder.feed_line(right_pad("", 60) + "END OF HEADER"))
          false
        } catch {
          Rejected(code, _, _) => code == "crx-types"
        }
        assert_true(rejected)
        assert_true(
          try {
            ignore(decoder.finish())
            false
          } catch {
            Rejected(code, _, _) => code == "state"
          },
        )
      }
    }
  }
}
