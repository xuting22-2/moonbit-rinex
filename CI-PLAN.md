# 当前源码的必要CI计划

当前模块`xuting22-2/rinex`，维护与申报账号`xuting22-2`，仓库`xuting22-2/moonbit-rinex`。版权、原始作者及历史证据保持原义。产品workflow为`.github/workflows/ci.yml`的`linux-js-wasm-consumers`，结果按同repo/同head真实run/job/步骤终态核对。

全部既有门保留：固定SDK/Node/Python、格式/公共接口、所有声明目标check、JS/Wasm-GC原生测试、JS release构建、十二条host合同、恢复文件、NAV来源、CSV/gzip/窗口RNX、四组双后端公共消费者、ROB固定列比较及两个冷独立模块消费者。新恢复门为`Check CRINEX recovery through initialized empty epochs`，命令`node tools/test-crinex-empty-recovery.mjs`。

该恢复门以CRINEX1/3的完整独立手写输入和RNX/Decimal/整数时间预期，检查坏观测后的初始化零卫星历元成功读完钟差后重同步，并保留随后两条有效差分观测。完整原生报告/原值对象及实际物理文件Reader/LegacyReader接收均核对；已有丢失仍complete=false/acceptable=false，CLI退出2。正常流/default fail-fast、未初始化空历元及坏/截断钟差保持原合同。无新格式、时标、科学模型或质量放宽。

相关本地验证在新导出的无缓存源码副本中进行，记录实际编译产物和完整文件输出：

```sh
moon fmt --check
moon info
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --release --deny-warn
node tools/test-crinex-empty-recovery.mjs
node tools/test-crinex-file-delivery.mjs NEW_DIRECTORY --skip-output-budget
moon run examples/formats-consumer --target js --deny-warn
moon run examples/formats-consumer --target wasm-gc --deny-warn
```

现有Native全部合同及三个恢复状态组覆盖两个后端。恢复文件门执行其余15项，显式跳过已验收512MiB预算，沿用a1bff90c7a7251b69b078cdc4438ff535540ed2c/run40795883416冻结证明；默认完整测试仍16项。未变旧RTKLIB/GSI参考生成器不重跑。最终同head云端执行全部必要产品门；本地不重跑与此次状态转换无关的旧消费者。

公共包仍通过当前命名空间解析；两个既有冷模块使用workspace/current0.4.0，不请求包发布。自编实际接收不代表外部采用，数值参照不代表物理精度/全格式认证；云端success元数据不表示下载云端二进制或本地/云端编译字节相同。无全局SDK/网络/账号变更，无Mooncakes发布或赛事提交。
