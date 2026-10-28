# 原反馈处理清单 · rinex

仅核对原意见与已有修复。本轮未重跑构建、测试或独立参考，也未改评委材料。ID为本次追踪编号，并非原评审编号。

| ID | 原反馈 | 改动／已有处理 | 证据 | 结论 |
|---|---|---|---|---|
| RINEX-01 | 只是计数校验器、不能消费原始观测 | 0.2.0新增Reader、原始数值/LLI/SSI/钟差/行列位置及完整时刻；与Checker共享状态。 | [pkg.generated.mbti](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/pkg.generated.mbti)、[RAW-OBSERVATIONS.md](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/RAW-OBSERVATIONS.md)、[LOCAL-CHECKS.json](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/evidence/observations-20260930/LOCAL-CHECKS.json) | historically-fixed-and-verified |
| RINEX-02 | IGS已有4.02，不能写当前完整RINEX库 | 采用原意见明确允许的另一方案：标题和SCOPE锁定列明OBS版本至4.01/GPS/flag0/1，而非新增全4.02/NAV。 | [README.md](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/README.md)、[SCOPE.md](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/docs/SCOPE.md) | scope-response；未实现4.02不作为本轮漏修：原反馈给出锁定4.01或后续升级的选择。 |
| RINEX-03 | 计数不等于逐值，独立参考差异不可抹去 | 新增前两时刻全槽/F14/Decimal位置对照、JS/Wasm独立模块；Rust一处把LLI并入尾数的差异与负控均保留。 | [RAW-OBSERVATIONS.md](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/RAW-OBSERVATIONS.md)、[LOCAL-CHECKS.json](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/evidence/observations-20260930/LOCAL-CHECKS.json)、[all-selected-observations.json](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/evidence/observations-20260930/all-selected-observations.json)、[comparator-rejection.json](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/evidence/observations-20260930/comparator-rejection.json) | historically-fixed-and-verified；不声称全部Rust数值相同；原输入头131/实载127差异保持，完整不等于acceptable。 |
| RINEX-04 | 成熟GNSS工具、不得冒称定位/EPN认证或需求已证明 | 保留增量接收/原始消费的具体职责，明确非定位、无scale/phase/clock改正及外部采用。 | [README.md](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/README.md)、[SCOPE.md](D:/CodexLocal/ban/work/portfolio-progress-20261027/projects/moonbit-rinex/docs/SCOPE.md) | scope-response-with-residual-external-risk；0.2.0本地维护不代表已发布或正式认可；不改冻结申报书。 |

历史源归档逐成员读回、当前代码身份和原回执哈希见 [RECEIPT.json](RECEIPT.json)。本地处理完成不等于正式复审通过；没有新增外部采用证据。
