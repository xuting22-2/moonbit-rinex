# CI 与复现范围

[RINEX CI](https://github.com/xuting22-2/moonbit-rinex/actions/workflows/ci.yml)在每次 push / pull request 上运行。具体结果以同一提交的 run、job 和步骤终态为准；配置存在或本地通过均不代表远端运行通过。

工具链来自官方 MoonBit Unix 安装器，安装器 SHA256 固定于 workflow，编译器版本由 `.moonbit-version` 固定。GitHub 官方 checkout、setup-node、setup-python actions 固定到经核对的 commit SHA。运行器为普通 Ubuntu 24.04，Node 24.11.0、Python 3.14.0；实际版本写入每次日志。核心不依赖额外宿主包，Python仅使用标准库作独立比较和模块启动。

本地准备同样工具后，按 `.github/workflows/ci.yml` 的顺序执行：格式检查、公共接口差异、所有声明目标的严格 check、JS/Wasm-GC 两套严格测试、JS release 构建、十二个 Node 合同/错误路径测试，以及四个公共消费者在两个后端上的断言。导航测试使用已记录的独立 RTKLIB 数值预期；CRINEX 测试保留独立 GSI 恢复预期和已知分歧。

已存零卫星历元的持续消费者测试使用自编固定列输入和独立整数日历预期，检查精确标签、零记录、原生warning、无桥读取、一次NAV加载，以及质量不合格和同长度损坏时的失败封闭。它补充既有能力的完整链回归，不宣称修复已正确的实现或增加格式支持。

连续保存行读取测试以新的四历元合成OBS和独立固定字段/整数日历预期，核对一次全文验证后原子交付的窗口、精确标签/原始槽、可选头、无桥CLI、256条跨块和无末尾LF；真实原生质量错误、未选中尾部损坏及后续所选行无效时整批失败且无stdout。共享单历元/头/查询/零卫星消费者继续保留原合同验证。该能力只减少短序列消费者的重复文件核对，不新增GNSS质量或精度结论。

提取范围快照测试在真实异步文件API中修改调用方数组，要求原生输出、返回及保存清单仍使用调用时范围；独立字段/整数日历预期、冻结数组、CLI、默认全选和原非法参数拒绝同时核对。既有host和部分写入错误测试保留。它防止清单记错实际应用的参数，不改半开时间语义、原生质量政策或完成边界。

原始 ROB BRUX 前缀保留整日头声明，提取预期退出 2，CI 会精确检查这个状态。随后独立 fixed-column/Decimal Python 参考核对全部选中槽，再由两个冷启动的独立 MoonBit 模块分别在 JS / Wasm-GC 上核对完整公共结果。提取目录与独立模块目录均位于 runner 的临时目录；不下载或改造整日测站数据来隐藏质量问题。

`.gitattributes`为固定列 NAV/CRX、原始 RINEX、参考 JSON 和历史证据保留原始字节，避免 checkout 的换行归一化破坏既有来源散列。许可证、原始模块名 `xuting22/rinex` 和原作者来源保留；仅维护仓库地址按实际发布位置更新。

CI不执行第三方 SDK、Rust、GSI 或 RTKLIB 的在线安装，也不把历史参照运行冒充本次运行。它检查已提交实现、固定样本、独立预期与实际消费者，不能认证物理轨道精度、全部 RINEX/ICD、数据源真实性、Mooncakes 发布或赛事验收。临时构建、依赖缓存和认证 helper 不属于源码提交。

独立步骤`Run restored-file delivery and physical consumers`核对两版修改前手写CRX/RNX、保存包及原CRX移走后的实际接收、恢复/OBS质量分离、截断/丢失、真实短写/EIO、输入变化、回读不匹配及重命名后元数据失败。错误清单也可能无法持久化，文件名存在不等于合格。

输出预算曾以真实约38MiB合成CRX生成超过512MiB的原生RNX流，核对实际预算前缀长度/行数及固定基线字节身份。输入由独立Python配方生成；零值`.000`拼写是旧原生字节复制预期，数值/字段宽度和预算独立核对。按本轮明确限制，当前CI以`NEW_DIRECTORY --skip-output-budget`运行其余15项，沿用R06-r01提交a1bff90c7a7251b69b078cdc4438ff535540ed2c、run40795883416的预算通过证据；不声称本轮重跑该大样本。省略选择参数仍运行原完整16项。原十二条合同脚本、原生双后端及全部公共消费者门保留。

新增必要步骤`Run selected NAV source and physical replay consumer`运行`node tools/test-nav-source-replay.mjs`。冻结的自编NAV2/3原始头/八行预期和既有独立RTKLIB状态参照，核对原始选择与真实子文件接收；覆盖GPS/BDS显式轨道和GPST/BDT、等价记录的最早词法来源、冲突无来源、跳过后的物理行号、CRLF/无末LF、晚截断/容量失败、独占输出、原生完成门与旧默认完整JSON字节。双后端原生测试另核对公开来源快照的数组所有权。自编接收方不等于第三方采纳，原始换行字节与数据真实性不在结论内。

R08新增`Run raw OBS CSV export and Decimal file recipient`，运行`node tools/test-observation-csv.mjs`。原始OBS/完整CSV/Decimal预期先于实现冻结，真实Python进程重读CSV后核对精确tick文本、逐槽原文、空历元、原生质量与完整性。另用1024历元的小样本跨宿主读取块，无末LF，并核对全部CSV字节；不重跑512MiB样本或旧科学参照生成器。原双后端与既有必要门保留。当前执行计划和本地复现见根CI-PLAN.md；是否通过仍以相同最终提交的真实run/job/step为准。
