# Gzip现代OBS完整接收

适用于已有`.rnx.gz`、希望直接进入现有原始历元文件接收流程的调用方。[IGS数据说明](https://connect.igs.org/data/)和[RINEX3.05命名规范](https://files.igs.org/pub/data/format/rinex305.pdf)列有gzip传输。调用者也能先在外部gunzip再使用原提取器；新入口提供一次有界流式接收、分域身份和明确的完成门，不宣称生态空白。

```sh
node tools/extract-gzip-observations.mjs INPUT.rnx.gz NEW_DIRECTORY
node tools/read-extracted-epochs.mjs NEW_DIRECTORY 1 3 --header
```

程序化入口为`extractGzipObservations(file,directory,gpsRange=null)`，从`tools/extract-observations.mjs`或新CLI模块导入。可选范围保持已有半开精确100ns字符串合同；范围只筛输出，整份解压输入及容器仍要验证。目录必须不存在。

## 复用原解析与交付

Node标准`createGunzip`只处理容器；其输出经原有有界ASCII拆行交给相同MoonBit Reader。所有RINEX字段、时间、计数、质量与选择政策不在Node复制。未改任何MoonBit源码、接口、SDK或默认未压缩API/CLI，未扩展原现代OBS3.03/3.04/3.05/4.00/4.01、GPS时标、flag0/1合同，不作测量改正。

新入口先等默认Gunzip管线完全结束，再检查物理输入读取身份，随后才调用原生finish并保存报告/最终complete清单。默认Node24.11.0 [Gunzip行为](https://nodejs.org/download/release/v24.11.0/docs/api/zlib.html#class-zlibgunzip)支持拼接成员，拒绝截断及非成员垃圾尾；未放宽finishFlush来接收损坏前缀。所有成员解压后须共同构成一份合法的本范围OBS，不能拼接两份独立RINEX头当作合并文件。

CRC/ISIZE错误、截断、垃圾尾或原生解析/finish失败，都以失败结束；已经写出的完整早期历元仍是暂定值。存储块测试会先写出所选正确首历元，再遇到坏CRC，目录仍complete=false，旧消费者拒绝它。CRC32用于发现损坏，不是来源认证。

## 两个输入字节域

输出仍是`epochs.ndjson`、`header.json`、`report.json`、`manifest.json`，原有已存历元API/CLI可读取。新清单额外有：

`compressedInput:{encoding:"gzip",file,bytes,sha256,complete:true}`

它表示同次实际读取的物理压缩文件。原`manifest.input`则表示精确解压后OBS的bytes/lines/SHA，file保留源文件basename作标签；它不是另一个已保存的普通RNX路径。CRLF和无末LF在该原始解压身份中保留；输入行号和原始头/槽对应解压后的文本，换行分隔不属于原始行字符串。

消费者的`observation.reported_input`照旧返回该逻辑OBS身份。旧接收方核对的是原生决定、保存的完整NDJSON身份与头上下文；源gzip移走后可继续消费，它不会重新解压或认证原gzip。测试另用预先冻结的Python容器结果和实际源字节核对两域，不能把下游NDJSON读回说成重新验证了源容器。

## 状态与限制

新CLI退出0表示容器完整、原生完成且质量可接受；2表示容器与原生完整但原生质量不合格；1表示参数、gzip、原生或IO失败，stdout为空、stderr给失败JSON。默认未压缩CLI的原输出不变。完整解压不等于原生质量通过，已正确选出一条记录也不等于容器完整。

物理gzip、解压后OBS分别最多512MiB，既有8192字符行/NDJSON/原生容量继续生效，计数在向后传递每个有界块前检查。流式解压不暂存整个RNX；本轮不执行512MiB压缩炸弹/边界样本，容量边界由代码检查及既有逻辑界限支持，未把静态检查说成实测大样本。

仅gzip容器；不含.Z/bzip2/zip或archive提取，不自动探测，未增加NAVgzip或直接CRINEXgzip入口。没有网络下载、源真实性、对抗性文件替换快照、fsync或断电事务承诺。晚IO可能留下未合格文件，原交付质量判断须保留。项目自编实际接收测试不等于第三方采用或完整RINEX/物理精度认证。

## 独立固定证据

`examples/gzip-observations`在实现前固定完整逻辑输入、Python gzip成员/错误文件、独立整数日历/Decimal逐槽对象，以及accepted-base普通文件字节兼容参照。12组Python容器检查与产品Node解压分开；原生基线字节不是新的独立科学参照。3历元样本保留奇数100ns、空历元、0/null、LLI/SSI和钟差；128历元/2048卫星记录的小输入选择首历元但仍验证全部容器。没有重跑旧RTKLIB/GSI或大预算生成器。
