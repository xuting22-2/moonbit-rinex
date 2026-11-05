# MoonBit RINEX：多星座导航与可追溯 GNSS 文件接收

当前源码0.5.0，模块 `xuting22-2/rinex`，维护账号xuting22-2；保留原xuting22署名、版权及真实Git历史。[仓库](https://github.com/xuting22-2/moonbit-rinex)。未发布Mooncakes、未重新提交比赛，也未取得组委会重新接纳。本次材料仅记录2026-11-05初审意见整改；粘贴通知的10月31日期限不代表当前仍可报名。

项目面向离线GNSS处理、测站文件接收和科研工具开发者。定宽解析、差分恢复、整数时间、质量统计、广播计算和交付政策由MoonBit实现，JS与Wasm-GC共享核心；Node负责有界文件IO和参数。新增导航路径回应初审指出的GLONASS、Galileo及RINEX4核心缺口。

1. 多星座NAV：新增原生NavigationReader，读取所列NAV3.00–3.05和4.00–4.02；除传统GPS/北斗外，解释GLONASS FDMA、Galileo INAV/FNAV以及GPS/QZSS CNAV/CNV2、北斗CNV1/2/3等独立字段布局。
2. RINEX4核心语义：解释EPH/STO/EOP/ION、具名单位槽、源/目标时标、连续周/历元、信号源与健康、两组BGD、区域与消息子类型。STO和EOP可数值消费，ION系数和现代星历可由下游按具名字段消费，不把CNAV强制当LNAV传播。
3. 广播状态：保留GPS/BDS传统传播，新增GLONASS FDMA的PZ-90 RK4和Galileo的GTRF Kepler/相对论钟差；Galileo按所选信号DVS/HS检查健康。原始群延迟另返且未应用，框架明确，不作精度认证。
4. 保真交换：新文件接口保存全部头与记录原文、字段/单位/空值、行号及输入/实际输出SHA256。未知R4记录显式保留并阻止全覆盖/合格结论；截断、错星及坏数值失败。完整读取、格式支持与物理质量分别说明。
5. 观测与压缩：保留OBS3.03/3.04/3.05/4.00/4.01及OBS2.11原值接收、码映射/事件/周跳、CRINEX1.0/3.0恢复；可追溯提取、CSV、gzip、时间窗回写和已保存历元消费保持原合同。
6. 时间与选择：旧GPST100ns观测tick继续连接GPS/BDS目录的健康/fit/Toe/Toc/冲突选择。新导航历元明确UTC/GST/BDT等时标，以相对钟历元的SI秒消费R/E轨道；不猜闰秒表或自动混用时标，R/E不冒用旧目录选择规则。

版本、星座、消息类型、字段映射、时间、原文交换及轨道能力的正式边界见[兼容矩阵](docs/NAVIGATION-COMPATIBILITY.md)。它区分真实公开文件、受控案例、参数消费和轨道求值；NAV4新增CDMA/NavIC消息有受控布局案例，不伪称已经取得真实广播样本或已实现它们的轨道模型。

最短原生示例：

```sh
moon run examples/navigation-messages --target wasm-gc --deny-warn
```

文件消费示例：

```sh
moon build --target js --release --deny-warn
node tools/navigation-file.mjs exchange examples/navigation-core-4.02.rnx NEW_NAV_DIRECTORY
python tools/reference/verify-navigation-exchange.py examples/navigation-core-4.02.rnx NEW_NAV_DIRECTORY
node tools/navigation-file.mjs evaluate examples/navigation-core-4.02.rnx 3 600 E5a
```

独立验证使用DLR/GSOC经IGS/BKG匿名发布的真实4.02与3.04全文件，核对20,355和17,152条记录及全部原始字段。实际运行的nav-solutions/rinex固定提交支持4.02，核对38类真实选择记录、559个数值并重读实际交换文件；RTKLIB实际轨道例程提供18个GLONASS/Galileo正负偏移预期。其映射去重和QZSS区域差异显式记录，原始冲突不丢失。既有OBS/CRINEX/NAV与合法错误路径仍执行完整JS/Wasm-GC及文件消费者回归。[复现与参考](docs/NAVIGATION-REFERENCE.md)，[同提交CI](https://github.com/xuting22-2/moonbit-rinex/actions/workflows/ci.yml)。本地/CI通过不代表物理精度或外部采纳。

贡献是可移植的MoonBit原生状态机、具名消息语义、完成与质量分离，以及从原始文件到实际消费者的身份链。采用标准公式，无新定位算法主张。不含接收机定位/PPP、光行时/Sagnac、UTC/GST/GPST自动换算、跨框架改正、完整ION延迟引擎、现代CNAV/CDMA/NavIC传播、OBS4.02、CRINEX3.1或SP3；不宣称全格式/全ICD认证。

根代码与自编示例为MIT；外部数据、规范和参考工具各自保留许可与提供者署名，公开原始导航文件仅下载到任务缓存，不改授MIT或打入源码包。[0.5来源说明](THIRD-PARTY-0.5.md)以及以前的第三方声明继续有效。
