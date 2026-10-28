# 将精确观测时间接到导航查询

Reader 返回的 ObservationEpoch 和 LegacyReader 返回的 LegacyEpoch 都带有 `gps_ticks : Int64`。`NavTime::from_gps_ticks` 接收这个已按 GPST 日历表达的值，省去重组日期或周秒的步骤，全程不把整个 tick 值转成 Double。

```moonbit
let at = @r.NavTime::from_gps_ticks(epoch.gps_ticks)
let result = catalog.query("G01", at)
```

签名：`NavTime::from_gps_ticks(Int64) -> NavTime raise NavError`。单位是从 **1980-01-01** 起的 100ns，和本库 OBS Reader 的日历坐标一致；它不是 GPS 周零点、Unix 时间或 UTC。

## 输入约定

接受 `0 <= gps_ticks < 38184480000000000`，即现有 OBS Reader 支持的 1980..2100 年日历范围。起点 0 和 2100-12-31 23:59:59.9999999 可接受；负值、2101 年起点及以上明确抛出已有 InvalidNavigation。范围来自 OBS 输入约定；既有 calendar/week/offset_seconds 构造器及其范围保持不变。

整数本身不能证明时标。调用方必须确认它已经使用该 GPST 坐标；此方法不猜测 UTC/BDT、闰秒、周数或其他时间原点，不应用 receiver_clock。Reader 与 LegacyReader 当前支持的观测时标为 GPS，返回值可直接使用。其他来源的数值需由调用方先做正确的时标/单位转换。

转换一个已返回的历元不能证明文件完整。示例在 `Reader.finish()` / `LegacyReader.finish()` 和 `NavReader.finish()` 成功后才交付查询结果。流式调用中先得到的历元仍遵守原来的暂定/完成边界。

## 可运行消费者

```sh
moon run examples/obs-nav-query --target js --release --deny-warn
moon run examples/obs-nav-query --target wasm-gc --release --deny-warn
```

两个输入都是自编示例：一份现代 OBS3.05、一份 OBS2.11，时间标签同为 2026-10-25 14:01:40.0000001 GPST。导航输入复用 `catalog-synthetic.nav` 的第一条自编 GPS 记录。输入行嵌入 `examples/obs-nav-query/fixtures.mbt`，便于在两个后端直接运行；规范化行哈希和独立状态见 `examples/OBS-NAV-REFERENCE.json`。

消费者用同一个已完成的导航目录分别查询两个历元，打印选中记录索引 1 / 示例输入第 4 行，并保留：

```json
{"gps_ticks":"14774041000000001"}
```

该奇数大于 2^53；把整个值先转成 Double 再转回整数会得到 `14774041000000000`。新方法按 Int64 原样保存，JSON 仍以十进制字符串输出。正确的既有日历/周秒构造也可保留其支持的精度；这里补的是直接接收已有整数坐标的接口。

两份 OBS 的接收机钟差字段均为 0.0001234 秒，示例保留该字段且未从时间中扣除。返回的是所给标签时刻的广播轨道状态，未执行接收/发射时刻修正、光行时或接收机定位。

## 独立预期与兼容性

整数历元和上界由独立 Gregorian 日历天数及整数运算得到。外部 pyrtklib 0.2.7 / RTKLIB 2.4.3b34 读取相同自编 GPS 参数，在其 Toe 后 3700.0000001 秒评价，参考 XYZ 为 -15789254.26762028、-11845667.979850149、17454897.504236296 米，钟差为 0.00010998992248758549 秒。

现代与旧版公共消费者在 JS/Wasm-GC 都通过各坐标分量 1e-5 米、钟差 1e-13 秒的同模型核对；实际最大分量差约 3.73e-9 米。三个目标测试覆盖两种完整输入连接、奇数 tick/原始钟差和日历边界。可执行：

```sh
moon test examples/obs-nav-query --target js --deny-warn
moon test examples/obs-nav-query --target wasm-gc --deny-warn
```

本页介绍的根模块方法没有新增根类型、错误变体、格式或传播算法。Node 使用者可通过[批请求的 gps_ticks 字符串形式](NAV-BATCH-QUERY.md)复用这个已验证的转换；普通点查询参数保持原样。既有 API 保留；本地版本仍为未发布的 0.4.0。数值一致性不表示观测为实测数据、物理轨道精度或完整定位能力。
