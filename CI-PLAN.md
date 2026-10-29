# 当前源码的必要CI计划

当前模块为`xuting22-2/rinex`，维护与申报账号为`xuting22-2`，仓库为`xuting22-2/moonbit-rinex`。原始版权、作者来源、旧证据与历史申报快照保持原义，不作为当前模块或当前申报账号。

工作流为`.github/workflows/ci.yml`中的`linux-js-wasm-consumers`。保留固定SDK/Node/Python版本、格式和生成接口差异、全部声明目标check、JS/Wasm-GC原生测试、JS release构建、十二条既有host合同、恢复文件、NAV来源重放、CSV、gzip、原始OBS裁剪、四组双后端公共消费者，以及ROB字段独立比较和双冷启动模块。配置存在不等于通过；结果按同一提交的真实run/job/步骤终态核对。

命名空间调整的本地验证使用私有固定SDK和现有测试，不改变算法、格式或输入契约：

```sh
moon fmt --check
moon info
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --release --deny-warn
node tools/test-public-contract.mjs
node tools/test-observation-clip.mjs
```

四个公共示例`examples/consumer`、`examples/formats-consumer`、`examples/nav-query`、`examples/obs-nav-query`分别以`moon run PATH --target js/wasm-gc --deny-warn`运行。生成接口仅应改变所属命名空间。Node适配器的`_build/js/release/build/cmd/bridge/bridge.js`路径不含账号，必须用新模块实际构建并执行。

`tools/run-observation-consumer.py`为每个后端创建新的独立workspace，复制本项目源码和消费者，使用`examples/observation-consumer/moon.mod`中的`xuting22-2/rinex@0.4.0`依赖解析本地模块。其完整输出与原始BRUX前缀的实际提取目录比较，并保留原头的质量拒绝，不进行注册表安装或包发布。具体命令及预期退出2见产品workflow。

裁剪门`Run raw OBS time-window RINEX file clipping and recipients`使用既有实现前冻结的完整原文/期望RNX、整数日期/Decimal对象；新模块必须保持跨午夜、半开边界、空历元/空选择、整源质量与晚截断门及真实Checker/Reader接收结果。无新字符串替换镜像测试。

已验收的真实512MiB恢复预算显式跳过，恢复门执行其余15项，沿用R06-r01提交a1bff90c7a7251b69b078cdc4438ff535540ed2c、run40795883416的冻结证明；默认完整测试仍有16项。无旧RTKLIB/GSI生成器重跑，无全局工具链/网络/账号变更。

自编实际接收方不等于第三方采用，数值参照不等于物理精度/全格式认证；云端success元数据不表示已下载云端二进制或与本地编译字节相同。未发布Mooncakes或提交比赛。
