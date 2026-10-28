# 原始 BRUX 4.01 的独立解析对照

0.1.1 仅补充验证工具与证据，MoonBit 运行时代码/API没有变化。2026-09-27实际运行 [nav-solutions/rinex 0.22.0](https://github.com/nav-solutions/rinex/tree/v0.22.0) 的 `Rinex::from_file` 与观测迭代器，读取原始 BRUX 4.01 文件成功；没有将头部改成 3.03 来适配参考。此前 GeoRinex 1.16.2 验证的是另一份 CEDA 3.03 文件，保留为单独的证据。

输入为 [PUBLIC-DATA](PUBLIC-DATA.md) 已署名的 ROB BRUX 2026-09-23 全日文件。转换后 41,314,394 字节，SHA-256 `0fe5e99ad02768434dc53b4c9d89603aa97e5ae924cf704e080b6c51279cd630`。本轮没有重做或独立验证 CRINEX 解压转换。

| 对照项目 | 当前 MoonBit 与 Rust 结果 |
|---|---:|
| 历元 | 2,880 |
| 首末 GPST | 00:00:00 — 23:59:30 |
| 不同卫星 | 127，按5个星座的数量也一致 |
| 历元/卫星记录 | 136,993，按星座数量一致 |
| 非空观测 | 2,373,196 |
| 星座/信号码 | 90组计数全部一致 |
| 星座/相位信号码 | 22组非零LLI及3个位的计数全部一致 |

MoonBit本轮重新构建、读取同一完整文件，并直接与Rust输出比较；返回退出2是预期，头部131颗与体中127颗的不一致仍报告为 `header-satellite-total`，另保留PRN细项告警。Rust“可解析”不是对这一QC结果或标准合规性的背书。

Rust观测迭代器省略空槽，因此442,622空槽仍由原独立Python定宽参考覆盖，不能声称由此Rust接口直接核实。参考运行还将首个C06行的24个声明槽中20个非空数值，与原始文本在3位小数精度下逐项核对；这是参考解析的局部检查，不是MoonBit保留或比对了整日全部原始数值。没有定位、物理观测质量、解算精度、完整RINEX/EPN合格结论。

## 复现

仓库附带原创最小适配器 `tools/reference/georust/` 和 `Cargo.lock`，固定rinex 0.22.0、仅开启obs。本次实跑Rust/Cargo1.85.1；第三方crate为MPL-2.0，通过Cargo获取，未将其源码或工具链打包成项目源码。适配器按当前BRUX五个星座输出计数，遇未知星座，比较工具拒绝通过。

先按PUBLIC-DATA准备**同一份未修改**的普通RNX，并核对上面的哈希。在独立输出目录保存报告，不覆盖仓库实跑证据：

```sh
moon build --target js --release
node tools/check-file.mjs INPUT.rnx 2026 9 23 -1 > product.json
# 上一条预期退出2，表示读完但QC不合格。
cargo run --locked --quiet --manifest-path tools/reference/georust/Cargo.toml -- INPUT.rnx > rust.txt
python tools/reference/compare-georust-brux.py product.json rust.txt --report comparison.json
```

Cargo命令应退出0，比较命令应退出0并返回passed:true。比较工具是两份报告的比较器，不替调用者证明Rust报告来自哪个输入；必须按以上命令对同一份固定哈希输入生成。首次Cargo获取依赖需要联网，已有完整缓存可追加`--offline`。Rust调试表示可能显示UTC，比GPST早18秒；比较使用输出的GPST日历标签。无需让整份日志字节在不同运行中完全一致。

当前直接对照在 `evidence/georust-20260927/product-comparison.json`，原始Rust输出、来源/工具散列、固定字段对照和本轮执行回执同目录保留。验证脚本开发时修正过跨星座代码聚合、声明空槽与非空迭代项混淆这两项比较器问题；最终按星座+代码配对，未修改产品或原文件去迎合结果。
