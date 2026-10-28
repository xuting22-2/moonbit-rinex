# 既有实现与本地定位（2026-09-27）

旧NTP的重复对象无法确定；增加其监控规则不能消除重复风险，因此本地另起RINEX接收检查候选。它不是改名继续提交NTP。

| 已有实现 | 已有能力 | 本项目关系 |
|---|---|---|
| GeoRust rinex0.22 / rinex_qc | 多版本/压缩、观测和导航、QC/时间分析 | 成熟参考；0.1.1 已实际运行固定 Rust rinex0.22.0 解析原 BRUX4.01，核对 90 组信号/22 组 LLI；不宣称超越其QC |
| gnss-js | JS浏览器/Node流式RINEX及质量分析 | 浏览器运行不构成差异；本项目提供MoonBit直接类型API |
| EPN/ROB数据中心 | 公开交付指南和站点/数据质量检查 | 本项目的日/小时策略是有限接收检查，不获其授权/认证 |
| GSI RNXCMP4.2.0 | CompactRINEX解码 | 外部开发流程工具，不冒充本库实现、不随源码打包 |

2026-09-27以RINEX、MoonBit RINEX observation QC等词核查Mooncakes公开索引和GitHub，未定位直接同范围MoonBit包；检索不覆盖所有未公开报名/私有仓库，不能证明零重复。已有HTTPcache、NIfTI替换候选因MoonBit直接近邻被否决后，才选择本方向；没有用零检索结果发明用户需求。

本项目的基础作用是让MoonBit消费端在解算前有一个不保存整文件、失败可定位的接收环节。它是标准任务的语言实现，不是原创算法。若调用方已可直接使用成熟Python/Rust/JS全功能QC，不建议仅为了名称换用本库。没有现存客户，适合性须由接入方评估。

一手来源：[RINEX4.01](https://files.igs.org/pub/data/format/rinex_4.01.pdf)、[EPN站点运行指南](https://epncb.oma.be/_documentation/guidelines/guidelines_EPN_stations.pdf)、[GeoRust](https://docs.rs/rinex/0.22.0/rinex/)、[gnss-js](https://github.com/MiguelPuntoEs/gnss-js)、[GSI RNXCMP](https://terras.gsi.go.jp/ja/crx2rnx.html)。范围检查不是赛事资格结论。
