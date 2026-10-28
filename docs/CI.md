# CI 与复现范围

[RINEX CI](https://github.com/xuting22-2/moonbit-rinex/actions/workflows/ci.yml)在每次 push / pull request 上运行。具体结果以同一提交的 run、job 和步骤终态为准；配置存在或本地通过均不代表远端运行通过。

工具链来自官方 MoonBit Unix 安装器，安装器 SHA256 固定于 workflow，编译器版本由 `.moonbit-version` 固定。GitHub 官方 checkout、setup-node、setup-python actions 固定到经核对的 commit SHA。运行器为普通 Ubuntu 24.04，Node 24.11.0、Python 3.14.0；实际版本写入每次日志。核心不依赖额外宿主包，Python仅使用标准库作独立比较和模块启动。

本地准备同样工具后，按 `.github/workflows/ci.yml` 的顺序执行：格式检查、公共接口差异、所有声明目标的严格 check、JS/Wasm-GC 两套严格测试、JS release 构建、十一个 Node 合同/错误路径测试，以及四个公共消费者在两个后端上的断言。导航测试使用已记录的独立 RTKLIB 数值预期；CRINEX 测试保留独立 GSI 恢复预期和已知分歧。

已存零卫星历元的持续消费者测试使用自编固定列输入和独立整数日历预期，检查精确标签、零记录、原生warning、无桥读取、一次NAV加载，以及质量不合格和同长度损坏时的失败封闭。它补充既有能力的完整链回归，不宣称修复已正确的实现或增加格式支持。

连续保存行读取测试以新的四历元合成OBS和独立固定字段/整数日历预期，核对一次全文验证后原子交付的窗口、精确标签/原始槽、可选头、无桥CLI、256条跨块和无末尾LF；真实原生质量错误、未选中尾部损坏及后续所选行无效时整批失败且无stdout。共享单历元/头/查询/零卫星消费者继续保留原合同验证。该能力只减少短序列消费者的重复文件核对，不新增GNSS质量或精度结论。

原始 ROB BRUX 前缀保留整日头声明，提取预期退出 2，CI 会精确检查这个状态。随后独立 fixed-column/Decimal Python 参考核对全部选中槽，再由两个冷启动的独立 MoonBit 模块分别在 JS / Wasm-GC 上核对完整公共结果。提取目录与独立模块目录均位于 runner 的临时目录；不下载或改造整日测站数据来隐藏质量问题。

`.gitattributes`为固定列 NAV/CRX、原始 RINEX、参考 JSON 和历史证据保留原始字节，避免 checkout 的换行归一化破坏既有来源散列。许可证、原始模块名 `xuting22/rinex` 和原作者来源保留；仅维护仓库地址按实际发布位置更新。

CI不执行第三方 SDK、Rust、GSI 或 RTKLIB 的在线安装，也不把历史参照运行冒充本次运行。它检查已提交实现、固定样本、独立预期与实际消费者，不能认证物理轨道精度、全部 RINEX/ICD、数据源真实性、Mooncakes 发布或赛事验收。临时构建、依赖缓存和认证 helper 不属于源码提交。
