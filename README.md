# MoonBit RINEX：观测接收、CRINEX恢复与广播星历
模块 `xuting22-2/rinex`，MIT。[仓库](https://github.com/xuting22-2/moonbit-rinex)。**0.4.0源码版本**；[GitHub CI](https://github.com/xuting22-2/moonbit-rinex/actions/workflows/ci.yml)的结果以对应提交为准，复现与范围见[CI说明](docs/CI.md)。尚未发布Mooncakes或提交比赛。历史 `xuting22-rinex-申报书.md` 保留旧快照，当前功能见PROPOSAL.md。SUBMISSION.json、REVIEW-RESPONSE.md和docs/SCOPE.md记录旧快照，不作为当前版本的新完成证明。

当前维护与申报账号为 `xuting22-2`。原始代码来源保留 `xuting22` 署名与Git历史；账号归属调整不改变既有版权、外部数据许可或上游来源。

定宽语法、精确100ns日历时间、原始槽、数字/文本差分和轨道传播均在MoonBit，Node只做有界文件IO；不是接收机定位/PPP引擎。

## 运行
工具链固定moonc0.10.14+7d59c7ec9，详见TOOLCHAIN.md，Node24：
```sh
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --release --deny-warn
node tools/formats.mjs legacy examples/legacy-continued.rnx
node tools/formats.mjs crx examples/modern-changes.crx
node tools/formats.mjs nav examples/gps-lnav.nav
node tools/formats.mjs nav examples/bds-geo.nav --geo
node tools/formats.mjs nav examples/bds-meo-igso.nav --meo-igso
moon run examples/formats-consumer --target wasm-gc
moon run examples/nav-query --target wasm-gc
moon run examples/obs-nav-query --target wasm-gc
node tools/nav-query.mjs examples/catalog-synthetic.nav G01 2442 50500
node tools/nav-query.mjs examples/catalog-synthetic.nav C06 1086 0 --bdt --meo-igso
node examples/nav-query-batch.mjs
```
crx的stdout为普通RNX，legacy/nav为NDJSON，stderr为完成回执。退出0成功、1解析/不支持/IO失败、2恢复中有丢失。提前stdout均须等待finish成功。NAV示例输出toe及±1800秒；库API可评价其他有效时刻。

需要可保存并重新打开的恢复文件时，可使用有界文件交付入口：

```sh
node tools/restore-crinex.mjs examples/restoration/modern.crx NEW_RESTORED_DIRECTORY
node examples/consume-restored-file.mjs NEW_RESTORED_DIRECTORY --consumer modern-check
```

`restoreCrinexFile` API/CLI保存原生RNX、原样恢复报告及输入/实际输出身份。**最终complete清单才是资格标记**；RNX重命名后元数据失败仍可能留下未合格文件。原CRX移走后，显式legacy或modern-check接收方会用本次实际读取的SHA核对再交付结果，恢复成功与OBS质量分开。详见[恢复文件交付合同](docs/RESTORED-FILE-DELIVERY.md)；原同步暂定stdout流程不变。

## 公共接口与范围

需要交给CSV分析工具时，可直接导出现有范围的现代OBS：

```sh
node tools/export-observation-csv.mjs examples/observation-csv/raw-obs.rnx NEW_TABLE_DIRECTORY
python examples/read-observation-csv.py NEW_TABLE_DIRECTORY
```

MoonBit生成长表，始终保留历元标记行（含零卫星历元），再按源顺序保存每个声明槽；`value_text`和`raw_field`保留D/E、负零、末尾省略与LLI/SSI，未作缩放/相位/钟差改正。`gps_ticks`为精确字符串，表格软件导入时须指定文本。导出完成与原生质量分开；Python接收方实际读取CSV及其同次SHA后才交付逐星/码原值统计。详见[CSV完整合同](docs/OBSERVATION-CSV.md)，不宣称与其他CSV工具同schema或物理测量可用性。

| 接口 | 本期能力 |
|---|---|
| 旧Reader/Checker | 原3.03/3.04/3.05/4.00/4.01 OBS、GPS时标、flag0/1；旧API保留 |
| LegacyReader.feed_line/finish | OBS2.11、GPS时标；9码头续行、12星续行、5槽续行；原码与事件2–5、独立CycleSlip(flag6) |
| map_legacy_code | raw码、Unknown/Ambiguous/有rule-id的RuleMapped/ExplicitOverride；不据接收机型号猜身份 |
| CrinexDecoder.feed_line/finish | 原生CRINEX1.0→OBS2.11、3.0→列明3/4 OBS；0–5阶、钟/数值/文本、LLI/SSI、缺测、换星及头更新 |
| NavReader.feed_line/finish | NAV2.11GPS及NAV3.03/3.04/3.05GPS/BDS传统LNAV/B1I D1/D2参数；不含NAV4新消息 |
| NavRecord.satellite_position | GPS/BDS MEO/IGSO/GEO，米坐标、含相对论钟差秒，另返未应用的TGD，框架WGS84/CGCS2000 |
| NavTime.from_gps_ticks/calendar/week/offset_seconds | GPS日历100ns ticks，直接接收OBS整数时间；既有GPST/BDT原点、连续周及14秒转换；不是UTC |
| NavCatalog.add/query/record | 显式容量内保存广播记录；按卫星/时刻筛选可用状态，返回来源、淘汰原因与同优先级冲突 |
| ObservationCsvReader.feed_line/header/finish | 在既有Reader上生成含空历元标记的原值CSV，原生统计行数并保留完整输入报告 |
| ObservationClipper.feed_line/header/finish | 按已有半开时间窗保存原始RINEX正文，完整源检查后生成适配子文件的已有首末头，移除旧可选汇总 |

LegacyValue保留raw_code/mapping及原ObservationValue字段；空与0分开，不应用scale/phase/接收机钟差改正。旧码默认规则只有标准明确的系统/码组合，其他未知或多义。详见 [接口合同](docs/FORMATS-0.3.md)、pkg.generated.mbti。

BDS非旧GEO PRN1–5需显式提供GEO或MEO_IGSO，不凭PRN猜全部BDS-3轨道。默认拒绝其他星座；显式skip_unsupported仅按已知长度跳过并计数，不宣称已解析。GLONASS3.05跳过五行。

`NavTime::from_gps_ticks(epoch.gps_ticks)`将Reader/LegacyReader返回的GPST整数时间直接接到导航查询，范围对应OBS支持的1980..2100年。超过2^53的奇数100ns tick原样保留，不推断时标、不应用接收机钟差；调用者仍须完成两个输入的finish。可运行的现代/旧版OBS→目录查询及独立参考见[精确时间连接示例](docs/OBS-NAV-TIME.md)。

牛顿最少3次、最多15次、步长≤1e-12弧度；失败明确KeplerDivergence。健康非0或过期拒绝。默认±7200秒，还受GPS声明fit半区间约束；调用方可收紧，上限14400秒。评价时刻为发射/轨道时刻，不做定位、光行时、Sagnac或跨框架转换。B1I3.0官方原文仍未取得，不声称完整ICD认证；传统参数/公式按IGS与RTKLIB实际核对。

## 状态与完成边界
CRINEX1行首&、CRINEX3行首>、数值n&value及文本&含义不同；负相位合法。flag4更新头，其他事件恢复原记录；恢复文本不表示旧Reader支持其物理语义。默认错误即封存失败。recover=true只在已知观测行边界错误时丢弃整历元，在可信头和完整初始化后恢复；不扫描未知乱码中的&猜同步。初始化的零卫星历元在钟差记录成功读完后也建立同步，后续合法差分历元正常恢复；未初始化空历元或坏/截断钟差不建立同步。任何丢失都保留finding且complete/acceptable不转成功。CRX complete指无丢失恢复；旧Checker complete指完成输入检查。

每行8192 ASCII字符、逻辑输入512MiB、头4096行、96类型/系统、有限卫星空间。流式Reader/Checker/CrinexDecoder仅保存头、计数、当前历元及差分状态，不累计历史；NavCatalog另保存显式容量内的广播记录，默认4096、上限32768，满时失败且不淘汰旧记录。调用者累计输出的内存另计；gzip仅由显式现代OBS文件入口解压，不提供其他压缩容器、CRINEX3.1、OBS4.02、SP3或GLONASS/Galileo传播。

已有`.rnx.gz`时可直接完整接收为原保存目录：

```sh
node tools/extract-gzip-observations.mjs examples/gzip-observations/valid.rnx.gz NEW_GZIP_DIRECTORY
node tools/read-extracted-epochs.mjs NEW_GZIP_DIRECTORY 1 3 --header
```

`extractGzipObservations`使用Node标准gzip流，压缩与解压后输入分别计数/SHA，所有成员及尾部校验完成后才调用原生finish；仅选早期历元也不能略过坏尾部。`manifest.input`是解压后OBS身份/行号，`compressedInput`另记物理gzip身份；原生质量与完成仍分开，旧未压缩入口字节保持兼容。详见[gzip完整接收合同](docs/GZIP-OBSERVATIONS.md)。

要把时间窗交给普通RINEX文件工具，可运行完整原值裁剪流程：

```sh
node tools/clip-observations.mjs examples/observation-clip/source.rnx NEW_CLIP_DIRECTORY 14779584000000007 14779584900000007
node examples/consume-clipped-observations.mjs NEW_CLIP_DIRECTORY
```

`clipObservationFile`使用原生半开窗口，保留所选全部历元/卫星原文和空历元，不作额外测量改正；只校准已有首末时刻头，移除已不属于子文件的可选卫星/PRN计数，保留完整原头作来源。完整源必须合格，实际新RNX重读通过后才写合格清单；无所选历元不会制造空正文成功文件。详见[时间窗RINEX文件合同](docs/OBSERVATION-CLIP.md)。

OBS文件提取在每条NDJSON完整写入后才更新输出长度/SHA；低层短写入不会被当成整条成功。写入异常保留complete=false的暂定文件，末条可能不完整；文件例程会在此停止，不能用暂定数据继续当作已完成输入查询导航。详见[原始观测文件交付约定](RAW-OBSERVATIONS.md)。

程序化`extractObservations(file,directory,gpsRange)`在调用开始时保存与原生Reader实际接收参数一致的范围快照。异步读取期间或完成后复用、修改调用方数组，不会改写返回及磁盘清单的`gpsRange`；半开区间、精确字符串、原生验证与完整/合格判断不变。

## 为指定卫星和时刻查询广播星历
0.4新增有界目录，适合从一份BRDC文件为观测时刻选择广播状态。复用健康、有效期、fit和GEO检查；可用记录先按完整100ns的Toe距离，再按较新Toc排序。同优先级相同记录保留最早来源并计数；不同记录返回ambiguous，调用方据来源检查，不按文件顺序猜选。

`tools/nav-query.mjs INPUT SATELLITE WEEK SOW`默认GPST，`--bdt`改用BDT连续周；支持`--geo/--meo-igso`、`--max-age`、`--capacity`、`--skip-unsupported`。退出0表示selected，2表示unavailable/ambiguous，1表示参数/输入失败。整份输入成功结束、文件身份核对后才输出单条JSON；stderr记录加载计数与查询状态。返回米坐标、钟差、来源记录索引/起始行和精确淘汰计数；诊断及冲突样例最多128条，截断数明确。selected表示本次状态可用，不是整文件或物理轨道认证。

示例文件是项目自编的5条合成记录：最近GPS记录不健康，查询选择另一条可用记录；C06需明确轨道类型。独立RTKLIB参照使用列明的健康候选子集，不能解释为RTKLIB本身采用本库健康/冲突策略。目录是离线/调用者供数策略，不重建RF消息接收时间。详见[完整契约与MoonBit用法](docs/NAV-CATALOG-0.4.md)、examples/CATALOG-SOURCE.json和examples/CATALOG-REFERENCE.json。

[真实BRDC查询示例](docs/REAL-NAV-QUERY.md)核对一份缓存的BKG/IGS混合星座文件：完整读取120505行，保存1461条GPS/BDS记录，显式跳过20134条其他星座记录。G01/C06查询的来源索引、物理行号和原始八行载荷独立核对，状态与相同记录的既有RTKLIB参照一致；同时保留全部过期的负例。未增加格式或传播范围。

完整加载与选中状态分开：仅有合法头或显式跳过记录时，目录为空，返回unavailable及精确计数；受支持记录之后的跳过记录若在末尾截断，仍以输入失败结束，不输出部分查询。NAV2多卫星记录的来源索引/行号也通过实际CLI及独立RTKLIB状态核对，详见同一示例说明。

需要把选中的广播记录交给文件接收方时，点查询追加`--source`，或导入`queryNavigationWithSource`。同一次原生解析保存完整原始头、所选八行和物理行号，整份读取成功后才交付；unavailable/ambiguous的`source`为null。默认查询JSON和回执不变。

```sh
node tools/nav-query.mjs examples/catalog-synthetic.nav G01 2442 50500 --source
node examples/nav-source-replay.mjs examples/catalog-synthetic.nav NEW_SELECTED.nav examples/nav-source-query.json
```

实际接收方独占创建NAV子文件，保留全部头与记录字符（含末尾空格，仅换行转LF），关闭后用原查询入口重新读取并核对同一状态。子文件内记录重新编号，原目录的淘汰/等价记录计数不复制为子文件判断。它是可复现来源文本，不认证数据源或物理轨道；详见[选中来源与文件重放合同](docs/NAV-SOURCE-REPLAY.md)。

## 一次加载，批量查询
`node tools/nav-query-batch.mjs INPUT REQUESTS.json [--capacity N] [--skip-unsupported]`一次完整加载后处理1–256项卫星/时刻请求，按输入顺序保留逐项selected/unavailable/ambiguous、原始来源与诊断。MoonBit负责查询、批次计数和完整结果构造；Node负责有界文件IO与参数整理。输入或任一查询参数失败时，整批不输出部分结果。

批请求也可直接使用OBS JSON中的`gps_ticks`十进制字符串，省去手写周秒转换；它与`week/sow/bdt`二选一，时标必须已经是本库GPST日历坐标。`node examples/obs-tick-query.mjs NEW_EXTRACTION_DIRECTORY`演示完整、合格的自编OBS文件先由既有提取器输出历元，再直接查询导航；原始头、清单和上游质量标记保留。可用`examples/catalog-gps-ticks-queries.json`运行新旧时间格式混合请求。

已有提取目录可运行`node tools/query-extracted-epoch.mjs DIRECTORY examples/catalog-synthetic.nav 1 G01`。入口先核对原生完成/合格标记、GPS头与来源、整份NDJSON的字节数/SHA/行数，再用所选历元的GPST标签查询指定卫星；可接受的warning保留，目录只读。索引指已序列化的历元行，哈希核对不重新认证原OBS。详见[复用目录契约与API](docs/EXTRACTED-EPOCH-QUERY.md)。

只需原始测量值时，可运行`node tools/read-extracted-epoch.mjs DIRECTORY 1`，或导入`tools/extracted-epoch.mjs`的`readExtractedEpoch`，得到同样校验后的`{observation, epoch}`。此读取器不依赖NAV或编译桥，保留全部观测卫星、原始槽、0/null、LLI/SSI和精确GPST字符串；不做改正或物理质量重判。用`examples/obs-raw-values.rnx`提取到新目录后，`node examples/read-extracted-epoch.mjs DIRECTORY`展示带断言的原始值消费者。

需要连续几条已保存的原始历元时，使用`readExtractedEpochs(directory,startIndex,count,{includeHeader:false})`或`node tools/read-extracted-epochs.mjs DIRECTORY START COUNT [--header]`。一次完整核对NDJSON后，按保存行序原子交付1–256条`epochs`及`observation.selected_epochs`；起点从1开始，末行不得超过已保存数量或100万。它选择保存行，不按时间间隔补点，也不计算GNSS统计。单历元入口及默认JSON保持兼容。

```sh
node tools/extract-observations.mjs examples/obs-series.rnx NEW_SERIES_DIRECTORY
node tools/read-extracted-epochs.mjs NEW_SERIES_DIRECTORY 2 2 --header
node examples/read-extracted-epochs.mjs NEW_SERIES_DIRECTORY
```

自编四历元样例保留奇数100ns标签、0值/LLI/SSI、flag1零卫星和负值，独立固定字段与整数日历预期见`examples/EXTRACTED-SERIES-REFERENCE.json`。读取阶段只需Node与四文件目录；任一所选行无效、尾部损坏或原生质量不合格时，整批失败且CLI stdout为空。详细返回结构和验证范围见[连续历元读取](docs/EXTRACTED-EPOCH-QUERY.md#连续读取已保存的原始历元)。

零卫星历元仍保存为一条带精确GPST的`satellites:[]`记录，保留原生`empty-epoch`诊断。默认提取剖面的可接受warning不等于取得测量值或NAV状态；普通unavailable仍退出2，原生质量不合格的目录则在读取NAV前拒绝。完整消费链及独立回归见[零卫星说明](docs/EXTRACTED-EPOCH-QUERY.md#零卫星历元)。

需要解释测量值的头部上下文时，CLI追加`--header`，或API传`{includeHeader:true}`，可在同样的全文校验后取得保存的`header:{parsed,raw_lines}`。默认JSON不变；原始scale/phase/clock记录供调用方使用，读取器不额外应用改正。`examples/obs-header-context.rnx`与`examples/read-extracted-context.mjs`提供可运行的头信息消费者。

运行`node examples/nav-query-batch.mjs`查看经过断言的程序化消费者；也可将`examples/catalog-synthetic.nav examples/catalog-queries.json`作为批量CLI参数。该CLI示例含2项selected和2项unavailable，预期退出2；全部selected退出0，输入/参数失败退出1。Node API新增`queryNavigationBatch`，现有点查询和原生目录API保持兼容。详见[批量请求格式、上限与回执](docs/NAV-BATCH-QUERY.md)。

补充边界核对：批量JSON传递保留前后1 tick的100ns选择边界；三路独立API调用的持续回归使用两份不同合法NAV与一路真实截断输入，同时发起并核对独立状态、各自来源/回执及全部句柄关闭，加载失败不串扰另两路；恰好1048576字节的合法请求文件可接受。上限按原始UTF-8字节计，包含BOM与JSON空白；持续回归以无BOM/带BOM的合法请求成对核对上限与多1字节，验证独立状态/来源、超限空stdout及输入不改写。这些是有限场景验证，不增加格式或并发吞吐承诺。

## 独立证据与来源
深入修复08：LegacyReader在flag3/4版本/系统头更新后刷新当前系统，后续GPS空标识和默认GPS时间按新头解释；非GPS文件不再把空标识猜成该星座。更新后的不支持版本/系统明确失败。4份合成头更新输入由GSI独立恢复，相关8项回归在JS/Wasm-GC各通过；实际JSON出口保留超过2^53的奇数100ns tick字符串。

深入修复07：普通CRINEX历元校验完整卫星标识，拒绝零号/非数字PRN及同一颗星的不同旧格式写法重复；恢复时跳过的描述符也必须有效。合法OBS2空系统/空格填充写法保持原样，差分弧仍按原始文本匹配。新增4项回归，相关40项用例在JS/Wasm-GC各通过；合法混合星座与4.01控制输入对照GSI输出。

深入修复06：补上CRINEX类型声明的续行计数。初始头或flag3/4更新未提供完整类型名时明确失败，recover=true也不能绕过；孤立续行、超量类型和未完成前重新声明同样拒绝。完整多行/多系统输入保持GSI恢复结果。6项新增用例与30项相关旧回归在JS/Wasm-GC各通过，未重跑不受影响的NAV/整日数据集合。

深入修复05：修复周内秒100ns量化少一tick、首个零卫星CRINEX历元误拒绝、事件2–5误用卫星数上限、OBS2 flag6多重续行截断。新增21项回归及相关旧用例，共42项在JS与Wasm-GC各通过；包含两版0–5阶钟差缺测/重启和GPS/BDT跨周RTKLIB参照。周内秒按最近100ns量化。

GSI4.2.0在OBS2 flag6多行载荷、首个零卫星历元带钟差的保留列上与规范有分歧；这两处按RINEX2.11表A2／3.04表A3保留规范行为，不能称为GSI逐字符一致。其余新增合法钟差输入使用独立GSI输出。初始手工CRX3未写初始化空标志的输入错误已单独保留，不计作产品缺陷。

GSI RNXCMP4.2.0历史参照覆盖OBS2多重续行、负/空/零、换星、LLI/SSI、flag2–6、头更新、0–5阶及钟差爬升/稳态。真实ROB BRUX原始CRX前两历元98条卫星记录，原生输出与官方CRX2RNX在LF统一后逐字符一致。

BKG/IGS BRDC三个真实参数记录（GPS、BDS GEO、BDS IGSO），toe及±1800秒9个状态，与pyrtklib0.2.7所带RTKLIB2.4.3b34比较：最大三维位置差4.16500117164066e-9米，钟差最大差0秒。回归阈值1e-5米及1e-13秒只针对同参数/同模型的数值一致性，**不是物理轨道精度或全域/BDS-3完整验证**。

旧0.2.0证据保留且未重跑：BRUX4.01整日2880历元/136993记录；首分钟2012槽/1660数值，Rust1659一致及1处差异，见RAW-OBSERVATIONS.md与GEORUST-REFERENCE.md。旧公开0.1.2/CI不能证明0.3.0已发布。

[第三方说明0.4](THIRD-PARTY-0.4.md)继承0.3说明；examples/FORMAT-SOURCES.json列历史数据提供者、哈希、署名及变换，CATALOG-SOURCE.json另标明新增自编合成输入。ROB CC-BY4.0，BRDC依IGS提供者署名条款，外部数据不默认MIT；GSI/RTKLIB工具及依赖未打包进核心。

