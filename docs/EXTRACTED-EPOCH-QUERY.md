# 复用已完成提取目录查询单个历元

已经用 `tools/extract-observations.mjs` 得到观测目录后，可以复用其中一个历元的 GPST 标签，为指定卫星查询广播状态，无需再次提取原始 OBS。

```sh
moon build cmd/bridge --target js --release --deny-warn
node tools/extract-observations.mjs examples/obs-query-time.rnx NEW_DIRECTORY
node tools/query-extracted-epoch.mjs NEW_DIRECTORY examples/catalog-synthetic.nav 1 G01
```

示例提取成功后，最后一条命令返回一项 selected，退出0。目录必须已经存在；查询只读取 `manifest.json`、`report.json`、`header.json`、`epochs.ndjson`，不修复或写入目录。

## 独立读取原始历元

下游只需已保存的测量值时，使用同一个有界读取器，不需要 NAV 或编译桥：

```sh
# 提取阶段仍使用 MoonBit 编译桥；读取阶段只需 Node24和四文件目录。
node tools/extract-observations.mjs examples/obs-raw-values.rnx NEW_RAW_DIRECTORY
node tools/read-extracted-epoch.mjs NEW_RAW_DIRECTORY 1
node examples/read-extracted-epoch.mjs NEW_RAW_DIRECTORY
```

```js
import {readExtractedEpoch} from './tools/extracted-epoch.mjs';
const {observation, epoch} = await readExtractedEpoch('EXISTING_DIRECTORY', 1);
for (const satellite of epoch.satellites) {
  console.log(satellite.satellite, satellite.observations);
}
```

返回的 `epoch` 是选中行的原生 JSON：包含全部卫星及槽的 code、源列、raw_field、value、LLI/SSI，以及原始记录、源行和精确 GPST 字符串。0与null、负相位、缺少尾字符的空槽分别保留；0仍可能表示缺测。读取器不按 NAV 支持范围过滤卫星，不做缩放、钟差/相位改正或质量重判。自编示例含G01/C06/E25，G01含0、负相位和空槽；参考预期在 `examples/EXTRACTED-RAW-REFERENCE.json`。

独立读取与下面的查询入口共享完整/合格、GPS、来源和整份NDJSON身份校验，严格要求原生质量合格，可接受warning原样保留。默认CLI接收目录和序列化历元索引，成功退出0并打印完整`{observation, epoch}`；可选头上下文见下文。失败退出1、stdout为空，API抛出错误，不交付暂定历元。原查询函数继续返回`{observation, results, receipt}`，签名/格式/状态码不变。

### 零卫星历元

合法零卫星历元仍是一行已保存的历元：保留精确GPST、原始历元行和`satellites:[]`，不会变成“没有这个历元”。普通Reader结构检查剖面中的`empty-epoch`为可接受warning，读取和查询会原样保留；提取的GPS范围只筛选返回历元，不启用日文件质量窗口。

观测可接受与导航状态可用分别判断。用该标签查询目录中不存在的G99，NAV完整加载一次后返回unavailable，查询CLI退出2；这不代表观测读取失败，也不声称有测量值。若头声明1颗卫星而实际0颗，原生报告保留`header-satellite-total`错误及`empty-epoch`warning：提取仍完整但不合格，退出2；原始读取和耦合查询都退出1且stdout为空，打开NAV前停止。完整产物不是绕过质量门禁的理由。

`node tools/test-saved-empty-epoch-chain.mjs`以自编固定列OBS和独立整数日历预期验证这条链：奇数100ns标签、1历元/0记录、无编译桥的独立读取、NAV前全文校验，以及真实质量错误和同长度损坏的拒绝。输入、原始质量诊断和产物均保持原状；不增加格式、算法或质量认证范围。

### 可选头部上下文

`readExtractedEpoch(directory,index,{includeHeader:true})` 或 CLI `DIRECTORY INDEX --header` 会额外返回 `header:{parsed,raw_lines}`；选项默认false且只接受布尔值，原两参数调用及默认CLI JSON不变。返回的是读取到的 `header.json` 快照，`parsed`为原生已解释字段，`raw_lines`保留scale/phase/clock等未解释记录。它仍在整份NDJSON校验成功后才与历元一起交付；没有只读头而跳过完整性/质量门禁的路径。

```sh
node tools/extract-observations.mjs examples/obs-header-context.rnx NEW_CONTEXT_DIRECTORY
node tools/read-extracted-epoch.mjs NEW_CONTEXT_DIRECTORY 1 --header
node examples/read-extracted-context.mjs NEW_CONTEXT_DIRECTORY
```

示例保留scale/phase/clock头记录，测量值1000/200仍按储存值返回。读取器不解析或额外应用这些变换；头上下文可见不代表新增头语义认证或原OBS真实性证明，原有来源对照和质量决定含义不变。NAV查询不启用此选项，原结果格式保持不变。

## 参数与完成边界

CLI 参数为 `DIRECTORY NAV_FILE EPOCH_INDEX SATELLITE...`。历元索引从1开始，指 NDJSON 内已选出并序列化的行号；如果提取时使用时间范围，它不代表原文件第几个历元。指定1–256颗卫星，卫星不必在该历元的观测记录中出现。结果表示这些卫星在该标签时刻的状态可用性。

可选 `--capacity N`、`--skip-unsupported`、`--max-age SECONDS` 与互斥的 `--geo` / `--meo-igso` 沿用导航查询规则。不会自动筛选卫星或推断未知 BDS 轨道类型。

读取导航文件之前，入口要求清单的 `complete/inputAcceptable` 和原生报告的 `complete/acceptable` 均为布尔值 true，原生头及报告均声明 GPS 时间，marker/license/doi 元数据一致；可接受的 warning 会原样保留。然后完整流式读取 NDJSON，核对实际字节数、SHA256、历元行数及读取期间的文件大小/修改时间，只保留所选行供查询。JSON 元数据各限1MiB，NDJSON限512MiB，历元索引上限100万；其余导航限制不变。

这只核对已有原生决定和产物字节一致性，不重新运行 GNSS 质量检查。哈希不证明真实性，`reported_input` 只是清单记载的原始输入身份，原 OBS 未在此重新验证。GPST tick 以字符串传给既有 MoonBit 时间解析和批量查询，不做 UTC/BDT 推断、接收机钟差改正或定位。

## API、结果与退出码

```js
import {queryExtractedEpoch} from './tools/query-extracted-epoch.mjs';
const output = await queryExtractedEpoch(
  'EXISTING_DIRECTORY', 'examples/catalog-synthetic.nav', 1, ['G01', 'G99'],
  {orbit:0, maxAge:7200, capacity:4096, skip:false},
);
console.log(output.observation, output.results, output.receipt);
```

可省略末项 options。卫星数组在异步读取前保存副本。`observation` 包含原生完成/质量标记、原始 findings、来源、`reported_input`、实际核对的 `verified_output` 与所选历元的索引、精确 tick、源行、flag和未应用的接收机钟差。`results/receipt` 沿用有序批量查询结构，分别保留导航完成状态、逐项状态、来源和诊断。

CLI 成功交付时，stdout 为完整的 `{observation, results, receipt}` JSON；全部 selected 退出0，出现普通 unavailable/ambiguous 退出2。产物、参数或输入失败时退出1，stdout 为空，stderr 为错误 JSON。API 对应抛出异常，不交付部分结果。产物质量、完整性或缺失历元错误均在打开 NAV 前停止。

`node tools/test-query-extracted-epoch.mjs` 验证实际双历元提取、跨块选择第二行、可接受 warning 保留、独立 RTKLIB 状态、质量/时间/来源与长度/SHA/行数拒绝、只读性及三种 CLI 退出码。独立参考见 `examples/EXTRACTED-EPOCH-REFERENCE.json`。这是单历元、显式卫星的有界适配，不是全观测联算或轨道精度认证。

`node tools/test-read-extracted-epoch.mjs` 验证新原始值消费者：独立固定字段预期的5槽、混合卫星不被过滤、空/0/负值与LLI/SSI、原生warning、无编译桥的读取CLI、共享读取后的查询兼容、质量/SHA失败及索引界限。它不重新计算原始OBS质量或轨道状态。

`node tools/test-extracted-header.mjs` 核对可选上下文的9条独立原始头预期、测量值不变、默认API/CLI兼容、全文校验前不交付头和错误选项；不重跑前述原始值/NAV参考集合。
