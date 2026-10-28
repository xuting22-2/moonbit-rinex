# 0.2.0 原始观测数据接口

持续维护补充实际数据消费接口；已提交的 0.1.2 申报材料保持原样。`Reader` 与 `Checker` 共用 MoonBit 的定宽字段解析、错误状态与统计，不在 Node/Python 复制产品语法。

## 公共接口

`Reader::new(gps_range? : (Int64, Int64))` 可选择半开范围 `[start, stop)`。参数采用自 1980-01-01 00:00:00 GPS 起算的 100ns 日历 ticks，范围必须非负、递增并在 1980..2100 之内。`Reader::feed_line(String)` 返回 `ObservationEpoch?`：只有当该时刻声明的全部卫星记录均通过检查，才返回完整对象；0 条卫星的时刻即时返回。选择范围外的数据也完整验证，但不构造观测字段对象。

`Reader::header()` 返回独立快照，含原 `Header` 和全部原始头行；修改快照的数组不改变 Reader。`Reader::finish()` 返回整个输入的 `Report`，没有自动套用日/小时窗口；需要这种策略时继续使用 `Checker` 的显式窗口。完整读完与检查合格分开。失败后 Reader 不可复用，finish 后也不可再喂数据。

每个 `ObservationEpoch` 有精确 `gps_ticks`、flag、源行号范围、原时刻行、可选接收机钟差与该字段原字符、卫星记录。每个 `ObservationValue` 含 header 的 code、从 1 开始的源列号、原字段、`Double?` 值、`Int?` LLI 与 SSI。原字段仅含文件实际出现的字符，省略的尾列不人工补空格。JSON 的缺值明确为 `null`；数值 0、指示位 0 与缺值分别表示。

```moonbit
// 独立模块 examples/observation-consumer/main.mbt 的实际公共调用：
let range = @r.Window::epn_daily(2026, 9, 23)
let reader = @r.Reader::new(gps_range=(range.start, range.start + 600000000L))
for line in fixture() {
  if reader.feed_line(line) is Some(epoch) {
    // 这里可以暂存或处理字段；整个输入尚未完成。
    epochs.push(epoch)
  }
}
let report = reader.finish()
// 同时检查 report.complete 和 report.acceptable。
```

完整可编译程序和模块配置随源码保存。运行器将当前未发布库复制到一个新的 workspace，以独立模块导入公共库，不靠源码包的内部符号；在 JS 与 Wasm-GC 上比对完整 JSON，而不是只打印计数。该消费者由本项目编写，不构成外部用户。

## 文件入口与完成标志

`tools/extract-observations.mjs` 使用 64KiB 宿主字节块，限制输入和 NDJSON 输出各 512MiB，单行 8192 ASCII 字符，拒绝已存在的输出目录。仅 CRLF 的 CR 在拆行时删除；文件末尾孤立 CR 仍是错误。范围参数为精确字符串，避免 JS Number 损失 100ns 精度。

`epochs.ndjson` 的每个已提交时刻都完成整条写入后，才更新输出长度、SHA和时刻计数；低层写入只完成前缀时，完整写入操作会继续处理余下字节。`header.json` 保留原始头；`report.json` 报告整份文件；`manifest.json` 保存输入、输出 SHA-256、来源署名、选择范围及完成状态。写出一个完整时刻并不保证后续输入正常。写入异常可能留下末条前缀，留存NDJSON必须结合 `complete=false` 作为未完成数据看待，不能据此继续交付导航查询结果。退出 2 表示成功读完但检查不合格，不可忽略该区别。

`node tools/test-observation-output.mjs` 以受控正数短写入和部分写入后EIO验证此交付边界，独立回读实际文件的长度/SHA并检查失败时的完成标记、句柄关闭和导航停止。这些是故障注入场景，未制造真实磁盘耗尽或断电。

对已经完成且原生检查合格的目录，`node tools/read-extracted-epoch.mjs DIRECTORY INDEX` 可独立取出一个已序列化历元及来源/质量/输出身份。Node API为`readExtractedEpoch`，读取阶段不依赖原OBS、NAV或编译桥，先核对整份NDJSON再返回原始卫星/槽；同一读取器也供既有NAV查询使用。它保留0/null和原字符，不新增改正或准入规则。详见[保存目录读取与查询](docs/EXTRACTED-EPOCH-QUERY.md)。

需要保存的原始头时，可显式请求`--header`或API的`{includeHeader:true}`，在完整校验后同时取得`header.parsed/raw_lines`。默认输出不变；scale/phase/clock记录只作为上下文返回，调用方负责其语义，读取器不额外变换储存值。

## 储存值与标准语义

[RINEX 4.01 原规范](https://files.igs.org/pub/data/format/rinex_4.01.pdf) Table A3/§6.7 定义观测数值、LLI 和信号强度指示；空或零可表示缺测。§5.2.11 的缩放需要在使用数值前处理。本接口明确返回储存值，不应用缩放、相位和接收机钟差改正；原始头、单位与改正标签保留，供调用方按标准另行处理。`Double` 是解析后的数值表示，原始十进制精确文本保留在 `raw_field`。没有坐标解算、周跳诊断或物理质量结论。

## 本轮公开数据检查

原 ROB BRUX 全日 RNX 41,314,394 字节，SHA-256 `0fe5e99ad02768434dc53b4c9d89603aa97e5ae924cf704e080b6c51279cd630`；不改变 4.01 版本头。处理全部 2,880 时刻、136,993 卫星记录后，第一分钟返回 2 时刻、98 卫星记录。相同选择在离线原节选上的 NDJSON 逐字节一致。整日报告保留 `header-satellite-total` 与 `header-prn-details`；节选因保留全天头而同样不合格。

标准库 Python fixed-column/Decimal 参考独立读取源，核对全部 2,012 槽（1,660 数值、352 空）、LLI/SSI、41 行原始头、GPS 时刻、原字段和源行列位置。另运行固定 Rust rinex 0.22.0 的公开观测迭代器，逐项对照节选全部 1,660 个已填数值和相位 LLI。1,659 个数值精确一致；E25/L7Q 在 00:00:30 的原槽为  114931467.86314，F14 数值是 114931467.863、LLI 为 1、SSI 为 4，参考库返回 114931467.8631。其固定版本 parse_sig_v3 从 SVNN_SIZE + 1 开始数值切片，14 字节范围包含 LLI 字符；MoonBit 和 fixed-column/Decimal 按原 F14 字段读取。回执保留这个差异，不放宽容差、不修改原数据或第三方解析器；未知差异仍使比较器失败。全部相位 LLI 一致。Rust 迭代器不覆盖空槽、SSI 和原字符；这些由固定列参考检查。回执、实际输出和依赖锁文件均随源码提供。

复现时先按 [PUBLIC-DATA](PUBLIC-DATA.md) 取得并验证同一完整文件，然后：

```sh
node tools/extract-observations.mjs INPUT.rnx NEW_FULL_OUTPUT 14745888000000000 14745888600000000
# 预期退出 2。
cargo run --locked --quiet --manifest-path tools/reference/georust-observations/Cargo.toml -- examples/brux-first-two-epochs.rnx > rust-values.tsv
python tools/reference/compare-observations.py INPUT.rnx NEW_FULL_OUTPUT --rust rust-values.tsv --report comparison.json
python tools/run-observation-consumer.py NEW_JS_WORKSPACE --target js --expected PREFIX_OUTPUT
python tools/run-observation-consumer.py NEW_WASM_WORKSPACE --target wasm-gc --expected PREFIX_OUTPUT
```

`PREFIX_OUTPUT` 用相同范围对 `examples/brux-first-two-epochs.rnx` 提取；消费者只内嵌这份节选，其完整报告自然与整日报告不同，不混淆两者。执行目录须为不存在的新目录，消费者工作目录在源码仓库之外。首次 Cargo 安装依赖需要网络；本轮实跑固定 Rust/Cargo 1.85.1，原第三方解析器没有修改。

整日文件不重复打包；CC-BY-4.0 原节选、来源与署名保持原样。生成记录含原头、原数据及来源，不新增未知授权结论。该范围只证明字段消费与已声明接收检查，不证明赛事审核、外部采纳、定位精度或完整 RINEX/EPN 合规。
