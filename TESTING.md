Current repeatable GitHub checks and supported consumers: [CI说明](docs/CI.md). The sections below retain dated local evidence; they are not a receipt for a new GitHub run.

# 0.2.0 本地验证

固定 `.moonbit-version` 为 `0.10.14+7d59c7ec9`，严格检查使用 `--deny-warn`。JS/Wasm-GC 各 35 项核心测试：既有 31 项回归，新增 4 项检查完整时刻的返回边界、失败封闭、半开选择但全部输入验证、缺值/零与原字段/改正头保留。这些针对新增数据接口的语义，不复制实现逐句写测试。

```sh
moon fmt --check
moon info
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --release --deny-warn
node tools/test-public-contract.mjs
node tools/test-observation-host.mjs
moon run examples/consumer --target js --deny-warn
moon run examples/consumer --target wasm-gc --deny-warn
moon package --frozen
```

既有公开节选 15 项契约检查继续通过；新增 9 项宿主集成检查覆盖 CRLF、孤立 CR、精确范围类型、过滤范围外错误仍失败、截断后 provisional NDJSON、已有目录不覆盖及完整不合格的退出 2。容量核心测试不生成 512MB 无意义夹具。

本轮重新处理原 41MB BRUX 整日文件，并比对旧 Checker 的全部统计/findings；独立 fixed-column/Decimal 参考核对选择的全部原字段、数值/空值、LLI/SSI 与源位置；固定 Rust rinex 0.22.0 逐项对照所有已填数值和相位 LLI，1,659 个数值一致、1 个参考库字段切片差异明示；全部相位 LLI 一致。独立 MoonBit 模块在两个后端比对头、全部选择记录和整个节选报告。详细方法见 [RAW-OBSERVATIONS](RAW-OBSERVATIONS.md)，实际命令、源码指纹、比较器结果在 [当前回执](evidence/observations-20260930/LOCAL-CHECKS.json)。

CI 新增宿主与两个独立模块入口，仅代表配置；未执行远程 CI。0.2.0 尚未推送或发布。旧 0.1.2 的公开成功 CI、旧 Linux 归档验证只属于历史基线。依赖 Rust/GeoRinex 的旧证据继续保存在 `evidence/georust-20260927`、`evidence/georinex-20260927` 和 `evidence/public-20260927`，不覆盖为新回执。

没有定位、地学正确性、性能/内存测量、完整 RINEX 合规或外部组织采纳结论。Reader 的有界状态由结构与容量检查保证；调用方累计历史会自行占用内存。已提交的两份申报文件保持 0.1.2 快照逐字节相同。

## 0.3.0 local implementation (2026-10-28)
The new legacy/CRINEX/navigation paths have independent GSI4.2.0 and RTKLIB2.4.3b34 reference outputs embedded in formats_*_wbtest.mbt. Both JS and Wasm-GC passed the full58case suite and the separately added NAV2.11 case (1/1 each). The latter is an explicit field-preserving derived input, independently read by RTKLIB; it is not mislabeled as native2.11 station data.
The public examples/formats-consumer ran on both targets. Existing Node public contract15 and host integration9 passed once. Original compressed BRUX two-epoch prefix matched CRX2RNX byte-for-byte after LF normalization. GPS/BDS9state errors and source provenance are in evidence/formats-20261028.
Reproduce product tests with the README commands. To regenerate independent references, obtain GSI RNXCMP4.2.0 from its official page; run CRX2RNX - on the exampleCRX files. With pyrtklib0.2.7 (RTKLIB2.4.3b34), read each exampleNAV using readrnx, then call eph2pos at toe and toe±1800seconds, including relativity/excluding TGD. Use explicit GEO vsMEO_IGSO type. The original execution adapters, full commands, first failures, hashes and raw logs are retained in the implementation03 report alongside the delivered source archive.
This proves only local declared behavior, not remoteCI/publication/physical accuracy or official acceptance. Historical35case and whole-day evidence above is preserved as history; the unchanged whole-day suite was not repeated.
