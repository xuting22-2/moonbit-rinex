# Navigation examples and independent verification

The0.5.0 remediation implements the missing GLONASS/Galileo and RINEX4 core
paths. The exact version/family/time/field/propagation boundary is in
[the compatibility matrix](NAVIGATION-COMPATIBILITY.md). Existing OBS/CRINEX and
legacy NAV consumers remain part of the full CI, not substituted by new examples.

With the pinned MoonBit/Node toolchain in TOOLCHAIN.md, run at repository root:

```sh
moon build --target js --release --deny-warn
moon run examples/navigation-messages --target wasm-gc --deny-warn
node tools/navigation-file.mjs inspect examples/navigation-core-4.02.rnx
node tools/navigation-file.mjs exchange examples/navigation-core-4.02.rnx NEW_NAV_DIRECTORY
python tools/reference/verify-navigation-exchange.py examples/navigation-core-4.02.rnx NEW_NAV_DIRECTORY
node tools/navigation-file.mjs evaluate examples/navigation-core-4.02.rnx 1 600
node tools/navigation-file.mjs evaluate examples/navigation-core-4.02.rnx 3 600 E5a
```

The controlled file is wholly project-authored synthetic data, explicitly labelled
in its header. Record1 is GLO FDMA; record3 is Galileo FNAV. `evaluate` chooses a
one-based physical record, not an implicit best-ephemeris catalog. Its offset is
elapsed SI seconds from that record's clock epoch, not UTC/GPST wall time. The
Galileo FNAV example deliberately has unhealthy E1 bits but healthy E5a; its E5a
query succeeds while an E1B request fails. No signal group-delay correction is applied.

The file API exports `inspectNavigation`, `exchangeNavigationFile` and
`evaluateNavigationRecord`. A completed exchange has native typed NDJSON and exact
same-version raw RINEX lines plus identity-bearing manifest. A numerical evaluator
is available for G LNAV,C D1/D2,R FDMA,E INAV/FNAV,STO,EOP. Other typed EPH/ION
parameters can be consumed by name/unit; calling an unavailable orbit evaluator
fails explicitly. Inspect/exchange is not an orbit-health or accuracy certificate.

Real public source verification is separate from the synthetic example:

```sh
python tools/reference/fetch-navigation-data.py TASK_LOCAL_NAV_CACHE
node tools/test-navigation-public.mjs TASK_LOCAL_NAV_CACHE NEW_PUBLIC_CHECK_DIRECTORY
```

The anonymous IGS/BKG downloads are DLR/GSOC's BRD400DLR and BRDM00DLR daily
2025/001 products. [IGS publishes their provenance and availability](https://igs.org/mgex/mgex-product-descriptions/).
Their actual current headers are4.02 and3.04. The historically named BRD400DLR
DOI title is not used to infer the file's version. Exact compressed/decompressed
SHA256 identities and independent inventories are pinned in the fetch script and
`examples/navigation-public-expected.json`. If a publisher replaces the bytes,
verification fails visibly rather than accepting a new oracle. Downloads are not
included in the source ZIP or relicensed as MIT.

The independent Python recipient uses original fixed columns, Decimal, integer
calendar arithmetic and hashes. It reopens both actual outputs and checks every
physical raw/numeric slot, missing/spare semantics, key unit mappings, time-scale
tags, descriptor/subtype, source span, header, counts and normalized RINEX bytes.
The measured totals are492,642 slots in20,355 real4.02 records and376,736 slots
in17,152 real3.04 records. This is source-field fidelity, not receiver accuracy.

Numeric expectations in `tools/reference/rtklib-navigation-expected.json` were
obtained by actually compiling byte-preserved orbital routines from
[RTKLIB commit965e945](https://github.com/rtklibexplorer/RTKLIB/blob/965e94507b628e84597c73b3a3d6530ecb9df272/src/ephemeris.c).
The private adapter supplies original public numeric parameters and relative
times, disables logging, and calls `eph2pos`/`geph2pos`; it does not port the
algorithm to Python or use product results as expectations. Function spans/hashes,
compiler, source and executable identities are recorded.18 GLO/Galileo states
cover -1800,-600,0,17,600,1800seconds. The contract tolerances are0.1mm coordinate
and1e-13s clock; observed agreement is numerical only. RTKLIB's parser is **not**
used as a RINEX4 reference.

The independent4.02 parser was actually built with private Rust1.90 from
[nav-solutions/rinex commit4871949](https://github.com/nav-solutions/rinex/tree/4871949d06554e0be75fe96b1b045210137e0334),
crate metadata0.24.0, MPL2.0. Its parser/math files were checked byte-identical to
the pinned archive; only private Cargo dependency locations changed to same-commit
downloads. It reads all38 selected real groups and34 controlled records.559
selected numeric fields and raw calendars match after explicit name mapping.
It also reopens the complete physical native4.02 exchange; its entire decoded
map equals its original-file decoded map. An optional reproducible reader is in
`tools/reference/rinex4-reader`:

```sh
cargo run --release --manifest-path tools/reference/rinex4-reader/Cargo.toml -- INPUT.rnx > independent-rinex4.json
```

Two reference differences are preserved, not concealed:

* The reference map keeps20,343 entries because12 GLO records repeat its
  satellite/epoch/frame-time identity; seven repeated groups have differing
  payloads. The native streaming exchange keeps all20,355 physical records,
  including conflicting candidates. No automatic R/E conflict selection is claimed.
* For an observed `ION J LNAV JAPN` record the reference reports `Worldwide`.
  Native output retains the explicit `JAPN` descriptor and both coefficient sets.
  RINEX4.02 §5.4.11 describes both regions for LNAV/CNAV/CNAV-2, whereas Table25
  lists the subtype rows under CNVX. This producer spelling is documented rather
  than silently normalized away.

[Ginan's official parser](https://github.com/GeoscienceAustralia/ginan/blob/5033996b279a4b128b70df9ecc6544cf0600248c/src/cpp/common/rinex.cpp)
was a second schema inspection source, not an executed orbit reference. GFZRNX's
registration/license boundary was respected; no downloaded or borrowed license
was used. References remain outside the runtime library. Full same-commit CI
executes the product tests and real-file Decimal/RTKLIB expectation checks; the
optional Rust build is an independently recorded local reference run, not a hidden CI claim.

The task's full raw logs/reference identities and final source/compiled/CI/ZIP
receipt are separately sealed in its new reports directory. Older task evidence
is not overwritten. See THIRD-PARTY-0.5.md for attribution and distribution scope.
