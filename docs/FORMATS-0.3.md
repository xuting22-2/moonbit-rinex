# Additive0.3 API contract
Lines excludeLF/CRLF. Exceptions poison objects. Call finish once; all outputs are provisional until it succeeds.

## LegacyReader
feed_line returns LegacyItem?: Epoch, Event, or CycleSlip. Flag6 raw values are not ordinary measurements.
LegacyEpoch contains GPS100ns ticks, source bounds, stored clock and satellites. LegacyValue keeps raw_code/mapping and original ObservationValue (column/raw_field/value/LLI/SSI). For continuation slots, index/5 identifies the physical observation row from the satellite's starting line.
OnlyOBS2.11/GPS time is supported; pure-G blank TIME OF FIRST OBS time defaultsGPS. Events3/4 update recognized system/type/time declarations. A RINEX VERSION/TYPE update must remain2.11OBS with a supported system; following blank satellite-system IDs and time defaults use the current system. Blank satellite-system IDs are permitted only in pureGPS files, never inferred asR/E/S. header() is the initial snapshot; event payload is separate. Two-digit-year pivot is80.
Override keys are G:L1 etc. Target kind/band/tracking are checked; caller correctness is not independently proven. RuleMapped only applies to unambiguous C1 C/A combinations. Receiver model is not used.

## CrinexDecoder
feed_line returns Array[String] restored RINEX lines. Buffers at most one epoch/event, plus bounded headers and per-slot difference states. Observations are emitted only when the whole epoch succeeds.
Type declarations count actual named slots across nine-code legacy/thirteen-code modern continuation rows. Incomplete declarations cannot cross another header label/declaration or the end of a flag3/4 update. Orphan/excess slots fail explicitly. These header failures poison the decoder even with recover=true; observation-only recovery requires trustworthy type metadata. This is targeted declaration completeness, not full RINEX header/physical validation.
Normal epoch descriptors require valid satellite IDs, with unique satellite identities. Modern IDs use a supported system plus two digits/nonzero PRN; legacy2.11 IDs allow G/R/E/S and I2 spacing, with a blank system only in a pure GPS file. For duplicate detection only, legacy spellings such as G01/G 1/blank01 resolve to the same identity; restored output and differential arc keys keep the original text. Descriptors skipped during recovery use the same checks, including list length/type declarations; malformed descriptors poison rather than being guessed through. Raw special-event payload semantics remain the consumer's responsibility.
Checked Int64 differences, orders0..5; overflow is explicit. Clock units1e9 for1.0 and1e12 for3.0, observations1e3. Version3 flags are text differences independent of missing numeric fields;1.0 blanks flags when numeric data is missing.
Events2moving,3newsite,4headerupdate,5external,6cycleslip are restored; type updates affect subsequent data. Consumers interpret event semantics separately.
Events2..5 use an I3 special-record count (up to999), not a satellite count. RINEX2 flag6 instead counts satellites: preserve the satellite-list continuations and ceil(types/5) raw rows per satellite, as required by RINEX2.11 TableA2. GSI4.2.0 reads only n physical event rows here and fails on multirow flag6; these cases use normative expected records rather than claiming GSI equality.
Zero-satellite epochs may have a short descriptor and still contain a clock record. RINEX3 clock output retains all six reserved columns before F15.12 (TableA3), including the first zero-satellite epoch; GSI4.2.0 omits that padding for this short descriptor.
Default recover=false fails on malformed values/flags/descriptor/order, overflow/truncation or unsupported versions.
recover=true only permits recovery after a known observation-record error: discard the incomplete epoch and its known remaining satellite rows, then known subsequent epochs until initialized. A malformed/unknown event or descriptor during recovery stops. Full numeric/clock initialization and trustworthy header are required. It does not guess missing header changes or sync on arbitrary&.
Report includes epochs/recovered_epochs and up to128 finding examples. Any loss leaves complete=false/acceptable=false even after successful later recovery.

## NavReader / NavRecord
Navigation2.11GPS;3.03/3.04/3.05G/C eight-line traditional parameters. Default unsupported constellation error; explicit skip consumes known record sizes and reports skipped_records (including3.05GLONASS5lines), without validating their values.
NavTime.calendar accepts1980..2100 and decimal second up to7digits. week accepts continuous0..7000 and sow[0,604800), rounded to the nearest100ns using math.round rather than truncated; no RF truncated-week or UTC/leap conversion. BDT's2006origin andGPST's1980-01-06origin differ by1356weeks and14seconds. Do not blindly add14 to seconds since different origins.
NavRecord exposes satellite/message/toc/toe/toe_sow/health. B1I-D1/D2 is the traditional parameter family, not RF message decoding. Model arrays are private.
satellite_position(time,bds_orbit?,max_age_seconds=7200) returns{x,y,z,clock_seconds,group_delay_seconds,frame,iterations}.
GPSmu3.986005e14,omega7.2921151467e-5,WGS84. BDSmu3.986004418e14,omega7.292115e-5,CGCS2000. Full epochs are subtracted; stale epochs are never repeatedly folded into a valid half-week.
Default cap7200sec; GPSpositivefit further limits to declared half-interval. BDS7200sec is conservative application policy. Explicit max_age cannot exceed14400 or bypass fit/health.
LegacyBDS PRN1..5 defaultsGEO, all otherBDS require caller typeGEO/MEO_IGSO. GEO uses complete rotated-frame model with Earth rotation; wrong caller type is not automatically corrected.
Clock is satellite-minus-system with polynomial+relativity, excludingTGD/codebias; stored firstTGD is returned separately. Ionosphere,TGD2,TIME SYSTEM CORR header terms are not applied. No light-time,Sagnac,frame conversion or receiver positioning.
Newton E0=normalizedM;3..15 iterations;abs(deltaE)<=1e-12radian. Finite0<=e<1 andpositive sqrtA required. Divergence/nonfinite/health/expiry errors never yield a valid state.
B1I3.0official document remains unverified. Scope is the traditional parameter/model contract with measured RTKLIB comparison, not allICD or modernNAV4 support.
