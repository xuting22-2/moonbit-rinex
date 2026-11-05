# Sources and rights for0.5.0 NAV remediation

All existing copyright, upstream authorship, Git history, root MIT license and
notices in THIRD-PARTY-0.3.md/THIRD-PARTY-0.4.md remain in force. The maintained
account/namespace is xuting22-2; original xuting22 attribution remains unchanged.
The new MoonBit reader/layouts/models, Node IO adapter, synthetic fixtures and
independent Python recipient are project-authored. No foreign parser or reference
binary is a runtime dependency or included in the source archive.

* [IGS RINEX4.02](https://files.igs.org/pub/data/format/rinex_4.02.pdf), editorial
  review1September2025, and [RINEX3.05](https://files.igs.org/pub/data/format/rinex305.pdf)
  define layouts/units. The source contains authored field transcriptions and
  standard equations, not copies of the standards' prose/PDFs.
* [Galileo OS SIS ICD2.2](https://www.gsc-europa.eu/sites/default/files/sites/all/files/Galileo_OS_SIS_ICD_v2.2.pdf)
  provides the official constellation context. Galileo/PZ-90/WGS84/CGCS2000
  labels do not assert certification or coordinate-frame conversion.
* `examples/navigation-core-4.02.rnx` and its expected manifest are original
  controlled data under MIT, not station captures or relabelled public data.
  Their header and documentation state this provenance.
* Real verification downloads are Montenbruck,O.; Steigenberger,P. (2022),
  **BRD400DLR: DLR's merged multi-GNSS broadcast ephemeris product**, DLR/GSOC,
  [DOI10.57677/BRD400DLR](https://doi.org/10.57677/BRD400DLR), supplied anonymously
  by [IGS/BKG](https://igs.bkg.bund.de/root_ftp/IGS/BRDC/2025/001/). BRDM00DLR is
  the related traditional-format product. Provider headers/credits are retained
  in every local exchange. The inspected DataCite metadata has no rights-list
  entry; no CC/MIT redistribution permission is invented. Full files and actual
  excerpts stay in task-local cache and are **not distributed in this source ZIP**.
  Fetch/checksum scripts, numeric reference facts and inventories are included.
* [nav-solutions/rinex](https://github.com/nav-solutions/rinex/tree/4871949d06554e0be75fe96b1b045210137e0334),
  Guillaume W.Bres and contributors, MPL2.0, was an executed independent4.02
  parser. Only the original thin verification wrapper and provenance are in this
  repository; upstream sources and Rust/Cargo runtimes stay private/external.
* [rtklibexplorer/RTKLIB](https://github.com/rtklibexplorer/RTKLIB/tree/965e94507b628e84597c73b3a3d6530ecb9df272),
  based on T.Takasu's RTKLIB with its upstream BSD-style notices, supplied actual
  independent orbital routine executions. The computed expected numbers and
  exact function/source hashes are included; RTKLIB C source/binaries are not.
  Its ordinary RINEX parser was not presented as a4.x parser.
* [GeoscienceAustralia/Ginan](https://github.com/GeoscienceAustralia/ginan/tree/5033996b279a4b128b70df9ecc6544cf0600248c)
  was inspected for modern-message schema context. No Ginan implementation,
  fixture or binary is distributed or used as a product dependency.

The optional Cargo verification tool fetches its separately licensed dependencies
only when explicitly run. Local Rust/Mingw/TinyCC acquisition and checksums are
evidence for building references, not bundled deliverables or global installations.
No package publication, contest submission or committee acceptance is implied.
