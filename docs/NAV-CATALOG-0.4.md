# Bounded broadcast navigation queries0.4

NavReader parses individual records; NavCatalog answers which supplied record can provide a state for one satellite/time. It stores records, not raw input history, under a caller-selected limit. Existing0.3APIs and propagation policy are unchanged.

```moonbit
let catalog = NavCatalog::new(capacity=4096)
// Add records returned by NavReader; source_line=0 means unknown.
let index = catalog.add(record, source_line=first_line)
// Finish the source reader before claiming a complete-file query.
reader.finish()
match catalog.query("G01", NavTime::week(2442, 50500.0)) {
  Selected(selection) => println(selection.to_json().stringify())
  Unavailable(report) => println(report.to_json().stringify())
  NavQueryOutcome::Conflict(conflict) => println(conflict.to_json().stringify())
}
```

Run the complete publicAPI example with `moon run examples/nav-query --target js` or `--target wasm-gc`; it asserts selected GPS provenance and required explicitC06orbit type before printing two results.

## Storage and input ownership

Capacity default4096, allowed1..32768. add returns a stable one-based record index and accepts a nonnegative one-based source line (0unknown). Invalid/capacity additions throw CatalogError before mutation; no silent eviction or deduplication. len reports stored count; record(index) returns the original immutable NavRecord orNone. Input records must come from the caller's intended sources. Catalog query success does not prove an unfinished source reader completed.

The CLI bridge enforces a successful NavReader.finish before any query. Truncation, capacity, unsupported/default or IO errors produce no query result. Host code handles boundedASCII/file identity/arguments only; MoonBit owns parsing, storage, normalized time, selection and diagnostics.

## Selection contract

Only GPS/BDS identifiers accepted by current broadcast propagation. Use existing NavTime GPST/BDT constructors, which normalize to exactGPS100ns ticks. max_age_seconds defaults7200 and must be finite in(0,14400]; it cannot bypass record fit/health or conservativeBDS age. BDS outside legacyPRN1..5 still needs explicitGEO/MEO_IGSO.

Each matching satellite record is evaluated by NavRecord.satellite_position. Rejections preserve its first failure category: expired, unhealthy, orbit-type-required, invalid-model, non-convergence or unsupported. Exact totals/reason counts are returned; at most128provenance samples, plus omitted_rejections. No matching/usable record returns Unavailable with a report.

Eligible rank is nearest absolute full-tickToe distance, then latestToc. This is an offline/caller-supplied catalog: it does not model RF reception time; records with futureToe can be eligible within existing fit limits. A live application controls which records it has supplied.

Same-rank broadcast records equal in all NavRecord model/clock/metadata fields are equivalent; source provenance may differ. The earliest source index is selected and equivalent_records includes it. Different same-rank records return Conflict (CLI status ambiguous), without a selected state. Its tied_records is exact, samples≤128, and omitted_candidates explicit. A late conflicting model remains visible even after128equivalent copies. A strictly better later-ranked candidate clears an earlier tie/conflict. Reports/samples are fresh query snapshots; mutating them cannot alter the catalog. The constructor name Conflict preserves the preexisting CodeMapping.Ambiguous constructor and its unannotated caller inference.

Selected returns NavCandidate (record_index,source_line,satellite,message,toc,toe,health), SatPosition and report. TGD remains separate and unapplied; WGS84/CGCS2000 and clock conventions are unchanged. This is no receiver positioning, Sagnac/light-time correction, new NAVmessage/constellation or fullICD certification.

## CLI

```
moon build --target js --release --deny-warn
node tools/nav-query.mjs examples/catalog-synthetic.nav G01 2442 50500
node tools/nav-query.mjs examples/catalog-synthetic.nav C06 1086 0 --bdt --meo-igso
node tools/nav-query.mjs examples/catalog-synthetic.nav G99 2442 50500
```

The last exits2/unavailable. Omitting the explicitC06orbit choice also exits2 with an orbit-type-required rejection. Options: --max-age SECONDS, --capacity N, --skip-unsupported, --geo, --meo-igso, --bdt. GPST continuous week is default; noUTC/leap conversion. One JSON result onstdout only after complete input; receipt onstderr. Exit0selected,2unavailable/ambiguous,1input/argument failure. Explicit unsupported skipping reports its count and only consumes known record sizes; it does not validate those records' values.

Programmatic Node consumer: import queryNavigation from tools/nav-query.mjs; await queryNavigation(file,{satellite,week,sow,bdt?,orbit?,maxAge?,capacity?,skip?}). orbit0/1/2meansdefault/GEO/MEO_IGSO. It returns result and receipt. Repeated native queries on one NavCatalog avoid rereading a source file.

For multiple Node requests, [the bounded batch API/CLI](NAV-BATCH-QUERY.md) loads one file once and returns ordered point outcomes. Existing point entry points and the native catalog contract remain unchanged; batch counters and atomic result construction also execute in the MoonBit bridge.

## Evidence, overlap and rights

examples/catalog-synthetic.nav is fully project-authored, not station data. CATALOG-SOURCE.json identifies it; CATALOG-REFERENCE.json pins8RTKLIB2.4.3b34states from the explicitly eligible healthy subset. Core policy tests independently cover exact-week ranking, identical/conflicting ties, diagnostic caps, fit/propagation failures, capacity atomicity and missing records. `node tools/test-nav-query.mjs` verifies publicCLI/API boundaries, source integrity and no partial result on input failure. Numerical same-model agreement is not physical accuracy.

RTKLIB's established closestToe selector and Rust rinex's nav_ephemeris_selection demonstrate the use case. This is original MoonBit code, not a C/Rust binding or source port. Our health/fit filtering, latestToc/conflict rule and receipt caps are explicit project policy, not a claim of identical universal selection behavior.

- RTKLIB fixed source: https://github.com/tomojitakasu/RTKLIB/blob/71db0ffa0d9735697c6adfd06fdf766d0e5ce807/src/ephemeris.c
- Rust rinex API: https://docs.rs/rinex/0.24.0/rinex/struct.Rinex.html#method.nav_ephemeris_selection
- Adjacent MoonBit NMEA toolkit: https://github.com/jiujitong/moonbit-nmea-toolkit (sentence/fusion/track evidence; different input/role).

Bounded liveMooncakes/GitHub search located no same-scope MoonBit broadcast selector; this is not proof of absence. All previous code/data/tool notices in THIRD-PARTY-0.3.md remain. New synthetic examples are original project material; external reference binaries/dependencies are not distributed.
