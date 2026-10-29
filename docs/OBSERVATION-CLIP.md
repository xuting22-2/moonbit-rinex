# 原值时间窗到普通RINEX子文件

场景是把一段现代OBS交给读取普通RINEX的下游。现有Reader能筛出原值，调用者也可自行拼接；直接保留原头会留下不属于子文件的首末时刻和文件汇总。[GSI RINGO的clipping](https://terras.gsi.go.jp/software/ringo/en/document/#clipping)是已有同类工作流，本入口不宣称生态空白或相同格式化行为。

```sh
node tools/clip-observations.mjs INPUT.rnx NEW_DIRECTORY START_GPS100ns STOP_GPS100ns
node examples/consume-clipped-observations.mjs NEW_DIRECTORY
```

Node API为`clipObservationFile(input,directory,[start,stop])`。时间使用已有GPS日历100ns十进制字符串和半开区间，所有源输入仍须验证。只接收已有现代OBS3.03/3.04/3.05/4.00/4.01、GPS时标、flag0/1子集；不新增GNSS语法、时标转换、压缩入口或科学模型。原Reader/Checker/defaultAPI不变。

## 原生正文与头策略

`ObservationClipper::new(start,stop)`组合原Reader，`feed_line`返回已完成所选历元及卫星的原始文本行。包括零卫星历元、原flag、钟差、LLI/SSI、空值/0/负零及源中省略的尾字符；不以Double重新格式化测量值，不作额外scale/phase/clock改正。所有提前正文均暂定。

`header()`仍是原始来源头的复制快照。`finish()`先完成整个源Reader，返回`input_report`及原生选择计数。仅完整且可接受的源、并有至少一个所选历元时，才提出`output_header`：

- 必需TIME OF FIRST OBS改为实际首个所选历元。
- 原有TIME OF LAST OBS改为实际最后所选历元；源没有这个可选记录时不添加。
- 用已验证原历元的日历字段和整数100ns秒构造80列I6/F13.7 GPS头，不经浮点/UTC反算。
- 省略原`# OF SATELLITES`和全部`PRN / # OF OBS`，避免把原文件汇总当成子文件汇总；完整原头另存供来源追溯。
- 其他头行逐字符保留，包括版本、类型、INTERVAL、许可/署名、scale/phase/clock及未解释metadata。

[RINEX3.05 TableA2](https://files.igs.org/pub/data/format/rinex305.pdf)把末时刻、卫星总数和逐星观测汇总标为可选。这里不伪造未实现的逐星汇总，也不声称所有复制的自由文本或未解释metadata已被重新认证。没有添加可选末时刻，头行数不会因它越过原4096行界限。

## 实际文件与资格

新目录保存`source-header.json`、原生`report.json`和暂定`body.rnx.part`。完整源可接受且所选非空时，宿主按原生头流式拼接`clipped.rnx.part`，核对正文实际读回身份，关闭/重命名，再用已有`inspectFile`真正重新打开新RNX。新文件的原生完成/质量、所选计数/时刻与实际输入SHA均匹配后，才保存`output-report.json`并发布最终合格`manifest.json`。

源完整但质量不合格时，即使所选窗口看似正常，也不发布`clipped.rnx`；不能靠裁剪把源决定提升为通过。源在所选范围外晚截断同样失败。没有所选历元时不制造没有正文的成功RNX；选中一个零卫星历元则可输出真实文件，但报告仍明确measurement record数为0，原warning保留。

CLI退出0为已合格实际文件；2为源完整但质量不合格或没有所选历元（无合格RNX）；1为参数/解析/IO失败，stdout为空，stderr失败JSON。成功与非写出终态的清单JSON在stdout。所有旧接口的合法输入和输出合同不变。

输入/正文/最终RNX各有512MiB界限，原生只保留原头、一个历元及首末小字段。输出统一LF，其他测量/钟差/标志字符保留。晚IO或元数据失败可能留下重命名但未合格文件；文件名不是资格标记，没有fsync/断电事务或敌对并发快照承诺。本轮不执行大预算样本。

## 可运行接收者与证据边界

`consumeClippedObservations(directory)`及示例CLI先要求完整合格清单、原始源完成/质量和头上下文一致，再用已有检查器实际读新RNX，核对保存的原生报告/全文身份和选择时刻/计数后返回。原源文件已移走也可消费；这不是重新认证原源或第三方采用。

`examples/observation-clip`在实现前固定完整源和完整预期RNX、所有逐槽/日历对象。朴素保留原头的文件在accepted-base分别产生首/末/卫星总数错误；正确预期独立按固定列/整数datetime/Decimal构造。实际新文件还经原Reader重新提取，逐字段与独立对象比较。覆盖跨午夜、半开上界、空历元/空选择、可选末头缺省、其他四个版本标签、换行差异、源质量/晚截断、占用目录及修改后拒收。没有旧RTKLIB/GSI或512MiB生成器重跑，不宣称完整RINEX认证或物理精度。
