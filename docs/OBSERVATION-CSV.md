# 原始现代OBS到长表CSV

场景是把已支持的现代OBS原值交给CSV分析程序。调用方原本能用Reader或NDJSON自行转换；现在有完整有界导出与可运行接收方。[GSI RINGO的rnxcsv](https://terras.gsi.go.jp/software/ringo/en/document/#rnxcsv)也提供OBS表格工作流，本项目不声称生态空白或相同CSV布局。

```sh
node tools/export-observation-csv.mjs INPUT.rnx NEW_DIRECTORY
python examples/read-observation-csv.py NEW_DIRECTORY
```

`exportObservationCsv(input,directory)`程序化入口同上。目录必须不存在；输入是原有OBS3.03/3.04/3.05/4.00/4.01、GPS时标、flag0/1范围，未新增legacy/CRINEX语法。已恢复的普通现代RNX可作为输入。这里不查询导航或推断测量可用性。

## 原生投影与行

`ObservationCsvReader::new/feed_line/header/finish`组合既有Reader。MoonBit负责语法、质量、CSV字符串和历元/卫星记录/槽/行数；Node只做有界字节拆行和文件IO。原生增量CSV在成功finish前都是暂定输出。默认Reader、Checker及其原JSON不变。

CSV使用LF，每格及列名均加双引号，内含双引号按CSV转义。列顺序为：

`row_kind,epoch_index,gps_ticks,epoch_flag,source_line,satellite,observation_code,source_column,raw_field,value_text,lli,ssi,receiver_clock_raw`

- 每个历元先有`epoch`行：从1起的顺序、精确tick、原flag、源物理行和原始接收机钟差文本；零卫星历元仍存在。
- 随后按原卫星/槽序输出`observation`行：保留卫星、码、源行/列、原始最多16字符的槽和LLI/SSI。每个声明槽都输出，包括全空和末尾省略槽。
- `raw_field`不补齐源中省略的尾空格，`value_text`仅取原数字区的trim文本；D/E、负零和原小数位不通过Double重新格式化。空数字与`0.000`分开，LLI/SSI空与显式0分开。
- 钟差文本只放在历元行，观测行按epoch_index/tick/flag引用该上下文；不把钟差应用到数值或时间。

tick是自1980-01-01起的100ns GPST日历整数文本，不是UTC。CSV双引号不能阻止所有表格软件自动改成浮点；导入时须显式把tick列指定为文本。这里保证文件中的精确文本，不保证应用的自动类型推断。

## 保存与质量

导出先写`observations.csv.part`，完整输入原生finish及文件读取检查成功、文件关闭后，保存`report.json`、重命名为`observations.csv`并写最终`manifest.json`。`header.json`保留完整原始头和解析上下文（包括署名、许可、scale/phase等未应用项）。输入原始字节SHA与实际写入CSV的长度/行数/SHA分别记录；manifest的table计数来自原生CSV报告。

成功序列化的`complete=true`仍可能有`inputAcceptable=false`。CLI退出0表示原生输入可接受；2表示完整导出但原生质量不合格；1表示参数、解析或IO失败且无成功stdout。失败前CSV前缀留在part文件，不能用于完整分析。晚IO/元数据失败也可能留下未合格文件；没有事务回滚、fsync或断电持久性保证，文件名不是合格证明。

输入及CSV各最多512MiB，沿用8192字符ASCII行、既有头/历元/卫星容量，原生仅缓存一个历元。JSON接收元数据最多1MiB。没有重跑旧512MiB大样本来支持新CSV结果；新跨块场景仅1024历元。

## 实际Python接收方

`examples/read-observation-csv.py`仅需Python标准库和保存目录。它先核对原生完成/质量与头上下文；不合格输入退出2，`complete=false`、`acceptedStatistics=false`，不会声称已完成CSV读取。完整合格目录才进入csv/Decimal读取。

接收方从实际同次读取中计算CSV字节数/SHA，检查列、行类型、历元索引和上下文、原槽/数字文本/标志、原生计数与覆盖范围。全文身份核对完成后才返回逐卫星/码的原值行数、空/零计数、非零LLI及Decimal原值求和。原RNX可以已移走。数字统计不解释缺测含义、不加改正、不声称物理精度；示例使用Python标准Decimal的28位上下文，冻结小样本的和独立精确核对，不保证任意极端指数或巨大动态范围的任意精度总和。

SHA和元数据不是源真实性认证，也不保证抵御主动并发替换。接收方是项目自编的真实消费者，不是第三方采纳或完整RINEX再认证。

## 固定证据

`examples/observation-csv`的五份自编输入、完整预期CSV及REFERENCE在实现前冻结，由独立固定列、整数datetime、csv.writer和Decimal配方构造。四历元保留大于2^53的奇数tick、零/空/负零、D指数、空历元、钟差和缺省尾槽；1024历元输入跨宿主读取块、无末LF，全部3072行与完整CSV字节预期比较。没有复制外部实现或重跑旧科学参照生成器。
