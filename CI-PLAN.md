# 当前源码的必要CI计划

工作流为`.github/workflows/ci.yml`中的`linux-js-wasm-consumers`。配置本身不是成功证据；最终提交、run、job及每个必要步骤终态需在交付报告单独核对。

保留固定SDK/Node/Python版本、格式和生成接口差异、全部声明目标check、JS/Wasm-GC原生测试、JS release构建、十二条既有host合同、恢复文件、NAV来源重放、四组双后端公共消费者，以及ROB字段独立比较和双冷启动模块。

既有CSV步骤：`Run raw OBS CSV export and Decimal file recipient`，命令`node tools/test-observation-csv.mjs`。它运行完整导出及实际Python CSV/Decimal消费者，比较冻结的完整CSV行/字节，检查空历元、值文本、LLI/SSI、质量拒绝、截断/坏值、占用目录和CSV实际读取/上下文错误。原生CSV合同保留在双后端测试中。

既有gzip步骤：`Run gzip OBS ingestion and existing file recipients`，命令`node tools/test-gzip-observations.mjs`。独立Python容器检查和固定列/整数时间/Decimal完整对象先于实现冻结；核对同次压缩/解压身份、真实旧文件接收、完整成员/CRC/ISIZE/截断/垃圾尾及原生结束门。已正确输出的首历元遇到坏CRC仍不合格。旧未压缩完整四文件/CLI字节也比较。

本轮新增：`Run raw OBS time-window RINEX file clipping and recipients`，命令`node tools/test-observation-clip.mjs`。冻结完整源/预期RNX/逐槽精确时间对象，检查已有首末头适配、过时可选汇总移除、原头/测量字符保留、源质量与末尾错误门，以及实际普通文件Checker/Reader和独立接收方。原生新增裁剪组进入双后端合同。

本轮新增原生裁剪API，旧Reader/Checker/格式/时标/科学模型不改；本地和云端均从本轮源码构建。相关本地验证：

```sh
moon fmt --check
moon info
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --release --deny-warn
node tools/test-observation-clip.mjs
node tools/test-public-contract.mjs
```

本轮本地不重复与未改旧行为无关的旧host门；最终同head云端仍运行全部必要门。已验收的真实512MiB恢复预算继续明确跳过，当前恢复步骤运行其余15项，沿用R06-r01提交a1bff90c7a7251b69b078cdc4438ff535540ed2c、run40795883416的冻结预算证据。完整默认恢复测试仍有16项。无旧RTKLIB/GSI生成器重跑，无全局工具链/依赖变更。

CSV/gzip/裁剪适配器使用原生Reader，未扩展GNSS格式、时标或科学模型。自编真实接收方不等于第三方采纳；云端成功元数据不等于下载二进制或本地/云端二进制一致性。
