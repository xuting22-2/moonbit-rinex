# 有界批量导航查询

为同一份 BRDC 文件查询多个卫星/时刻时，使用批量入口可共用一次完整加载。它复用现有 MoonBit 目录、健康/有效期/轨道类型检查、冲突规则和来源信息。MoonBit bridge 同时构造批次结果、计数及全选中标志；Node 只整理参数和进行有界文件 IO。

## 运行与请求格式

```sh
moon build cmd/bridge --target js --release --deny-warn
node examples/nav-query-batch.mjs
node tools/nav-query-batch.mjs examples/catalog-synthetic.nav examples/catalog-queries.json
```

程序化示例先断言结果再打印。CLI 示例的 4 项请求按顺序为两项可用状态、一项不存在的卫星、一项过期时刻，预期退出码为 2。

请求文件是 1–256 项对象组成的 UTF-8 JSON 数组，最大 1 MiB（包含恰好 1048576 字节的输入），可带 UTF-8 BOM。例如：

```json
[
  {"satellite":"G01","week":2442,"sow":50500},
  {"satellite":"C06","week":1086,"sow":0,"bdt":true,"orbit":2}
]
```

| 字段 | 含义 |
|---|---|
| satellite | 现有目录支持的 GPS/BDS 标识，如 G01、C06 |
| week / sow | 周秒形式的连续周整数 / 周内秒数，默认 GPST；100ns 量化规则与点查询一致 |
| bdt | 仅用于周秒形式，可选布尔值、默认 false；true 使用 BDT 原点与现有 14 秒转换 |
| gps_ticks | 替代周秒形式的 1–17 位无符号十进制字符串；已按 GPST 日历表达的 100ns tick，自 1980-01-01 起算 |
| orbit | 可选整数，0 默认、1 GEO、2 MEO/IGSO；C06 示例需明确为 2 |
| maxAge | 可选秒数，默认 7200；不能绕过现有 fit/健康/BDS 年龄上限 |

每项只接受这些字段；未知字段明确失败。`--capacity N`（默认 4096，上限 32768）与 `--skip-unsupported` 控制同一次文件加载，不能放在单项请求中。导航输入仍遵守原有 ASCII、每行 8192 字符和 512 MiB 限制。只保存容量内的受支持记录，满时失败，不淘汰已有记录。请求文件和导航文件均完成字节数/文件身份检查。

`gps_ticks` 与 `week/sow/bdt` 二选一；即使 bdt=false 也不与 tick 形式混用。它必须是字符串，不接收 Number、科学计数法或带小数点的文本。MoonBit复用既有精确字符串解析和 `NavTime::from_gps_ticks` 的 OBS 日历范围校验，不推断或转换输入时标。其他字段、上限、完成规则和旧周秒形式保持兼容。示例：

```json
[
  {"satellite":"G01","gps_ticks":"14774005000000000"},
  {"satellite":"C01","gps_ticks":"14773536140000000"},
  {"satellite":"G99","week":2442,"sow":46900}
]
```

该示例保存于 `examples/catalog-gps-ticks-queries.json`，与合成导航输入搭配时返回两项 selected、一项 unavailable，CLI 退出2。C01 的值已经是 GPST 坐标；不能把尚未转换的 BDT 日历 tick 直接放入此字段。普通点查询继续使用原有周秒参数。

## 输出与完成边界

stdout 在全部成功后只打印一个 `{ "results": [...] }` JSON 对象。每项为 `{ "query_index": 1, "result": ... }`，索引从 1 开始并保持请求顺序。result 保留点查询的 selected/unavailable/ambiguous 结构、原始记录索引/物理行号及最多 128 项的诊断/冲突样例。

stderr 回执包含一次加载的 complete、stored_records、skipped_unsupported、lines、bytes，以及 queries、selected、unavailable、ambiguous、all_selected。三个状态计数之和等于 queries。单项 unavailable 或 ambiguous 是有效查询结果，继续处理后续请求。

| 退出码 | 结果 |
|---|---|
| 0 | 全部 selected，all_selected=true |
| 2 | 至少一项 unavailable/ambiguous，批次仍完整交付 |
| 1 | 请求/导航输入、容量、IO 或任一查询参数失败，stdout 为空 |

例如第 1 项可用、第 2 项周数非法时，整个调用失败，不交付第 1 项的部分结果。错误标明有问题的 query 索引。成功加载不能保证所有请求可用；显式跳过的其他星座记录只按已知长度消费和计数，不能解释为它们的数值已获验证。

## Node API

```js
import {queryNavigationBatch} from './tools/nav-query.mjs';
const {results, receipt} = await queryNavigationBatch(
  'examples/catalog-synthetic.nav',
  [{satellite:'G01', week:2442, sow:50500}],
  {capacity:4096, skip:false},
);
console.log(results, receipt);
```

第三个参数可省略。调用在异步读取前保存规范化的基本类型请求快照，之后修改调用方数组/对象不会改变该批次。拒绝时抛出错误且不返回部分 results。原 `queryNavigation` 的签名、结果和 CLI 保持兼容，原生 MoonBit 使用者仍可直接重复调用同一个 NavCatalog。新批量 bridge/CLI 是 JS/Node 适配；没有新增原生目录算法或 Wasm 专用批量接口。

若已有 Reader JSON，可直接构造 `epoch.satellites.map(({satellite}) => ({satellite, gps_ticks:epoch.gps_ticks}))`。调用方仍负责选择受支持的卫星、明确 BDS 轨道类型及检查上游完成/质量信息。转换成请求不能认证 OBS 输入。

`node examples/obs-tick-query.mjs NEW_EXTRACTION_DIRECTORY` 是一个有界、固定自编输入的文件例程：复用原提取器，先完成 OBS 并检查 inputAcceptable，再读取真实产生的历元 JSON；将其中 GPS 时刻和卫星标识传给批查询。新目录保留 header/report/manifest/epochs 文件，输出将 OBS complete/inputAcceptable 与 NAV 回执分别展示。例程只针对随包的单历元示例，不是任意全量 OBS 联算器。

若目录已经提取完成，使用 `tools/query-extracted-epoch.mjs DIRECTORY NAV_FILE EPOCH_INDEX SATELLITE...` 可先核对原生完成/合格标记及实际 NDJSON 身份，再查询其中一个已序列化历元的指定卫星。它保留可接受 warning 和来源，只读目录，不重新验证原始 OBS。API 与完整返回格式见[复用目录查询](EXTRACTED-EPOCH-QUERY.md)。

## 时刻边界与独立调用

批量 JSON 传递保留现有 100ns 时间语义。在自编 GPS 示例的两个健康候选 Toe 中点，GPST 第 2442 周的 `50399.9999999`、`50400.0`、`50400.0000001` 秒分别得到整数 tick `14774039999999999`、`14774040000000000`、`14774040000000001`，选中记录索引为 1、3、3。中点两侧先按 Toe 距离选择；恰好中点按较新 Toc 选择。三项批量结果与对应点查询完全一致。这里的精确时间/选择核对不是实际轨道精度承诺。

每次 API 调用创建独立目录。一次受控三路并行核对中，两份不同输入分别返回自己的记录计数、来源和独立参考状态；第三路截断输入只使自身调用失败。三个导航句柄均关闭。该有限检查不承诺任意并发量或吞吐率。

请求文件上限按原始字节计：一项合法 JSON 请求加标准 JSON 空白，补足到恰好 1048576 字节时仍成功，返回一项 selected。回执的 bytes/lines 仍只统计导航输入，不统计请求 JSON。

## 证据与限制

新增批量检查覆盖 8 个既有独立 RTKLIB 参考状态、输入顺序与来源、一次导航文件打开、256 项边界、调用方修改、混合状态、冲突、后续非法查询不交付部分结果、文件/容量/截断及请求文件限制。点查询共享加载部分改变后，其 29 项 CLI 回归也通过。可执行 `node tools/test-nav-query-batch.mjs` 与 `node tools/test-nav-query.mjs`。

新增 tick 请求适配检查为 `node tools/test-nav-query-ticks.mjs`：覆盖新旧时间形式混合、两个不同独立状态、C01 的旧周秒点查询与 GPST tick 结果相等、Number/混合字段/科学计数文本拒绝及不交付部分结果。文件例程与独立参考一致。真实 BRUX 节选时刻送入另一日期的缓存 BRDC 时，三颗 GPS 卫星全部过期；OBS 节选 complete=true/inputAcceptable=false 的上游标记保留，NAV complete 或查询状态不能将其改成合格。

同一缓存真实 BRDC 文件的一批 3 项请求只由查询 API 打开导航文件一次：保存 1461 条 GPS/BDS、显式跳过 20134 条其他记录，读取 9760898 字节 / 120505 行。G01 GPST 2442/50400 与 C06 BDT 1086/72000 选中原记录 1036/第 59623 行和 102/第 879 行；C06 BDT 1086/0 返回 27 条全部过期。前两项与哈希匹配的既有独立参考一致。原始来源和精度边界见[真实文件说明](REAL-NAV-QUERY.md)。独立预期另有读取原始字节的步骤，一次打开指查询 API 本身，未宣称测试程序只进行一次磁盘 IO。

批量入口减少重复加载，不承诺延迟或物理轨道精度，不做接收机定位、RF 接收时间推断或新格式传播。实现继续为本地未发布的 0.4.0。
