# Navigation compatibility, source and consumption contract (0.5.0)

`NavigationReader` is the new native multi-GNSS NAV path. `NavReader`,
`NavCatalog` and the old `nav-query` tools keep their GPS/BDS contracts.
Use `NavigationMessage.state_at_offset` or `tools/navigation-file.mjs` for
GLONASS/Galileo; the old catalog does not acquire a new selection policy.

Normative layouts: [IGS RINEX4.02](https://files.igs.org/pub/data/format/rinex_4.02.pdf),
Tables A9–A40, and [RINEX3.05](https://files.igs.org/pub/data/format/rinex305.pdf).
Galileo orbital/time/health context: [official OS SIS ICD2.2](https://www.gsc-europa.eu/sites/default/files/sites/all/files/Galileo_OS_SIS_ICD_v2.2.pdf).
The distinction between parsing, exchange and orbit evaluation below is part of the public contract.

| File version | Native read / same-version exchange | Verification provenance |
|---|---|---|
| 2.11 NAV | Existing `NavReader`: GPS only | Existing RTKLIB-derived contracts; unchanged |
| 3.00 | Traditional G/R/E/S layouts | Controlled version and framing cases |
| 3.01 | Traditional G/R/E/S layouts | Controlled version and framing cases |
| 3.02 | Traditional G/R/E/S, C/J layouts | Controlled version and framing cases |
| 3.03 | Traditional G/R/E/S/C/J/I layouts | Existing G/C and controlled R/E cases |
| 3.04 | Traditional G/R/E/S/C/J/I layouts; GLO four payload lines | Real DLR whole file, 17,152 records |
| 3.05 | Same traditional families; GLO five payload lines | Controlled five-line GLO and legacy regressions |
| 4.00 | Descriptors; EPH/STO/EOP/ION baseline families below | Controlled core records; no claim of a captured4.00 file |
| 4.01 | Same NAV core layouts as4.00 | Controlled core records; no claim of a captured4.01 file |
| 4.02 | Core plus new CDMA/NavIC layouts, optional flags and subtypes | Real DLR whole file,20,355 records; independent genuine4.02 reader; controlled rare families |

Version/date bounds are explicit:1980–2100 calendars, integer R3/R4 NAV seconds,
80 ASCII columns,4,096 header lines,512MiB logical input. Every header line and
record line is retained. A known record has its table length checked; truncation,
satellite mismatch and malformed numbers poison the reader. `finish()` is mandatory.
Returned data before successful finish is provisional. Empty NAV bodies are allowed.

| EPH system / family | Versions on the new path | Clock / orbit fields and time | Position evaluator |
|---|---|---|---|
| G LNAV | 3.00–3.05,4.00–4.02 | GPST; IODE/IODC, continuous GPS week, Toe, fit, health,TGD | WGS84 Kepler + relativity; old fit/age policy |
| G CNAV | 4.00–4.02 | GPST; A-dot, Δn-dot, t_op, URA indices,ISC,TGD,wn_op; Toe=Toc | Typed parameters/exchange; no CNAV orbit evaluator |
| G CNV2 | 4.00–4.02 | CNAV fields plus ISC_L1Cd/ISC_L1Cp; Toe=Toc | Typed parameters/exchange |
| R FDMA | 3.00–3.05,4.00–4.02 | UTC calendar; -τn,+γn,frame week seconds; XYZ km,km/s,km/s²; signed frequency -7..13 | PZ-90 rotating-frame J2 + broadcast acceleration, RK4 ≤60s steps; ±1800s |
| R L1OC | 4.02 | UTC; β, validity, source/attitude/yaw/antenna offsets, URAI; TGD_L2OCp | Typed parameters/exchange; no CDMA orbit model |
| R L3OC | 4.02 | Same CDMA layout; ISC_L3OCp instead of L1OC's TGD | Typed parameters/exchange |
| E INAV/FNAV | 3.00–3.05 implicit source bits,4.00–4.02 explicit descriptor | GST calendar; GPS-aligned continuous RINEX week; IODnav,SISA,source/health bits,both BGDs | GTRF Kepler + relativity; signal-aware health |
| C D1/D2 | 3.02–3.05 implicit D1D2,4.00–4.02 explicit | BDT; AODE/AODC,BDT week,Toe,SatH1,TGD_B1/B3,TGD_B2/B3 | CGCS2000; prior explicit MEO/IGSO/GEO policy and ≤2h retained |
| C CNV1 | 4.00–4.02 | BDT; A-dot/Δn-dot,Toe,SatType,t_op,SISAI/SISMAI,health/integrity,ISC_B1Cd,TGDs,IODC/IODE | Typed parameters/exchange |
| C CNV2 | 4.00–4.02 | CNV1 layout with ISC_B2ad in its distinct slot | Typed parameters/exchange |
| C CNV3 | 4.00–4.02 | Distinct shorter layout, B2b integrity/TGD, no invented IODC/IODE | Typed parameters/exchange |
| J LNAV | 3.02–3.05,4.00–4.02 | QZSST, GPS-aligned week; LNAV fields | Typed parameters/exchange |
| J CNAV/CNV2 | 4.00–4.02 | QZSST; respective modern layouts/ISCs | Typed parameters/exchange |
| S SBAS | 3.00–3.05,4.00–4.02 | GPST, clock/frame time, XYZ km,km/s,km/s²,health,URA,IODN | Typed Cartesian parameters/exchange |
| I LNAV | 3.03–3.05,4.00–4.02 | NavIC/IRNSST calendar, GPS-aligned week,IODEC,health/TGD | Typed parameters/exchange |
| I L1NV | 4.02 | NavIC/IRNSST, A-dot/Δn-dot,IODEC,RSF and signal-specific blank/filled delay slots | Typed parameters/exchange |

“Typed parameters/exchange” is implemented consumption through named, unit-tagged
values and NDJSON recipients, not an orbital solver. Modern fields are never
forced into the old LNAV propagation formula. Optional4.02 GPS/QZSS flags occupy
their actual final slots; those columns remain spare on4.00/4.01.

| Other record / source families | Versions | Native semantic consumption |
|---|---|---|
| STO G/J LNAV,CNVX; R FDMA; E IFNV; C D1D2,CNVX; I LNAV; S SBAS | 4.00–4.02 | Source→target two-letter pair,SBAS ID and UTC realization retained; reference calendar follows source scale. Evaluate A0+A1·dt+A2·dt² in SI seconds, excluding leap-second component |
| STO R LXOC; I L1NV | 4.02 | Same STO layout and explicit origin |
| EOP G/C/J CNVX; I LNAV | 4.00–4.02 | Xp/Yp arcsec, first/second derivatives per day/day²; ΔUT1 seconds and derivatives. Taylor evaluation uses ½ for second derivatives; ΔUT1's UTC/GPST reference remains ICD-dependent |
| EOP R LXOC; I L1NV | 4.02 | Same EOP layout |
| ION G LNAV/CNVX; C D1D2; I LNAV; J LNAV | 4.00–4.02 | Klobuchar α/β, respective semi-circle units; no invented atmospheric-delay result |
| ION J CNVX WIDE/JAPN | 4.02 (prior versions untagged) | Both regions kept distinct; raw subtype retained |
| ION J LNAV WIDE/JAPN | 4.02 | Accepted observed DLR spelling, also described by §5.4.11 for LNAV. Table25 lists tags under CNVX only; do not erase the LNAV region or claim universal producer spelling |
| ION E IFNV | 4.00–4.02 | NeQuick-G ai0/ai1/ai2 in sfu/deg and five disturbance bits |
| ION C CNVX | 4.00–4.02 | BDGIM α1..α9 in TECu |
| ION I L1NV KLOB/NEQN | 4.02 | IOD and regional Klobuchar / three NeQuick-N regions, including coordinate limits and flags |
| ION R LXOC | 4.02 | GLONASS CDMA c_A,c_F10.7,c_Ap |

The controlled file has34 complete records covering all EPH layouts and ION
models above. The real4.02 file has38 distinct category/system/family/subtype
groups, including all four categories, R FDMA,E INAV/FNAV,G CNAV,C CNV1/2/3.
Rare G CNV2,R CDMA,I L1NV are controlled cases, not described as captured broadcasts.

`NavigationMessage` exposes `category/system/satellite/family/subtype/model/known`,
a scale-tagged `NavigationEpoch`, copied `parameters()` and `raw_lines()`,
`text(name)` and `value(name)`. Each field includes name, unit, physical payload
row/column (zero-based), original text, and optional finite number. Blank stays
missing, zero stays zero; spare text is preserved without assigning a meaning.
`availability` distinguishes present/blank/spare and specified unknown sentinels
(transmission/frame time, GLO Δτ/URAI, Galileo SISA). `value()` remains the raw
wire number even for a sentinel; it is not a claim of physical availability.
The JSON has the same fields plus all raw lines and one-based source spans.

GST is not silently converted to GPST. Galileo's RINEX week already aligns to
GPS week and must not have1024 added again. The new epoch calendar coordinate
has the old100ns/1980-01-01 origin **in its named scale**, not a shared time axis.
UTC23:59:60 keeps its exact spelling and leap flag; its normalized calendar tick
overlaps the next midnight, so the flag/calendar must be retained. Query input is
elapsed SI seconds from the record's clock epoch. No leap table, UTC absolute
query, GGTO application or automatic cross-scale conversion is claimed.

Galileo `signal` must be E1B/E5b with INAV E5b/E1 clock source, or E5a with FNAV
E5a/E1 clock source. Only the selected signal's DVS/HS bits determine health;
unrelated bits are not flattened to a global rejection. Both raw BGDs remain
unapplied. GLO uses -τn+γn·dt, not a negated-again clock. Its extra3.05/4.x status,
Δτ,URAI and almanac-health flags remain distinct. Frames are reported, not transformed.
GLO l(3) is checked only with the M/K type indication; C is ignored when AC=0,
as required by the extra-line flags, rather than treating every set bit as bad.

Unknown R4 categories/families/subtypes are bounded opaque records with an
explicit diagnostic and complete raw text. They increment `unsupported_records`,
deny `allSupported`/`qualified`, and yield CLI exit2; they are not silently skipped.
`finish()` may return the last opaque record at EOF. Callers must consume it.
Malformed/truncated input is a failure, not an opaque success. Unknown R3
constellations cannot be framed reliably and fail explicitly.

File exchange creates a new directory with `navigation.rnx`, `messages.ndjson`,
and final `manifest.json`. Headers and records are emitted from native snapshots;
only LF separators/final LF normalize. SHA256 covers actual source and outputs.
Failures retain unqualified `.part` files and a failure manifest. A rename alone
is not completion. `complete` proves finished reading; `allSupported` proves
known layouts; neither certifies physical accuracy, producer authenticity or full ICD compliance.

Independent evidence: Python fixed-column Decimal/calendar recipient checks all
492,642 real4.02 and376,736 real3.04 slots and exact source/output text;18 actual
RTKLIB routine states cover R FDMA/E INAV/FNAV at negative/positive offsets.
The independent nav-solutions/rinex0.24.0 commit4871949d06554e0be75fe96b1b045210137e0334
actually reads all38 selected real groups and34 controlled records, and consumes
the physically exchanged4.02 file. Its map collapses12 repeated GLO identities
(seven groups have differing raw payloads); this project preserves all20,355
physical records rather than adopting the reference map's20,343 entry count.
Reference comparison is bounded by these known representation differences.

See [NAVIGATION-REFERENCE.md](NAVIGATION-REFERENCE.md) for commands, reference
differences and licensing. No receiver positioning, PPP, light-time/Sagnac,
atmospheric delay engine, precision-orbit/SP3 or modern-message propagation is implied.
