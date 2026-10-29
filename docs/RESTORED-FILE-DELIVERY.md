# CRINEX恢复文件交付与真实接收

现有CrinexDecoder/consumeFormats能恢复普通RNX，但finish前输出暂定。新入口面向任意本库已支持且容量内的原始未gzip CRINEX1.0/3.0，保存普通RNX、原生恢复报告和身份清单；不是只转换内置样例，不新增语法、时间或科学模型。

```sh
moon build --target js --release --deny-warn
node tools/restore-crinex.mjs examples/restoration/modern.crx NEW_DIRECTORY
node examples/consume-restored-file.mjs NEW_DIRECTORY --consumer modern-check
# legacy.crx使用另一新目录，接收模式显式选legacy。
```

```js
import {restoreCrinexFile} from '../tools/restore-crinex.mjs';
import {consumeRestoredFile} from '../examples/consume-restored-file.mjs';
const receipt = await restoreCrinexFile('input.crx', 'ABSENT_DIRECTORY', {recover:false});
const result = await consumeRestoredFile('ABSENT_DIRECTORY', {consumer:'modern-check'});
```

目标目录原先须不存在；已有目录拒绝且不改写。recover默认false且只接受布尔值。输入沿用512MiB及8192 ASCII字符行，支持CRLF和合法无LF末行；输出严格为原生恢复行加LF，不重新序列化测量值。新宿主另限输出512MiB，每份报告/清单1MiB；不把新预算反加到旧解码器或消费入口。

## 保存和资格

合格目录含restored.rnx、report.json、manifest.json。report仅保留原生complete、acceptable、epochs、recovered_epochs、findings；manifest含kind、complete、inputReadComplete、选项、输入身份、实际输出身份和native_report。输入SHA取同一打开流的原始字节，先于CRLF拆除；输出关闭后物理回读，长度/SHA必须与完整写入序列一致。正数短写继续完成；部分写异常后的文件身份须实际回读或明确未知，不能把尝试写入digest当成文件身份。

**最终manifest.json才是资格标记**：complete与原生complete/acceptable都必须为true，且实际消费身份吻合。写入过程先生成restored.rnx.part；经过输入EOF/大小/mtime/字节核对、Native finish与输出回读后写报告、改名RNX，最后发布从暂定文件完整写入的清单。

RNX重命名之后元数据仍可能失败，留下未合格的restored.rnx。manifest.json.part、成功命名的文件或暂定stdout均不能代替最终合格清单。没有跨文件事务、回滚、断电原子性或fsync持久性承诺。失败清单只尽力保存为complete=false；元数据错误也可能让它无法保存，没有合格清单始终是失败。

recover=true只沿用原生已知边界恢复。输入读完可为true，但有丢失的原生complete/acceptable及交付complete保持false，诊断/计数不重判，文件仍为.part且不自动送下游。Native finish异常时可没有原生报告，不编造报告；已确认EOF身份与恢复成功分开。

新CLI：合格退出0、stdout一份完整回执；恢复丢失退出2、stdout明确不合格回执；参数/解析/IO失败退出1、stdout为空、stderr错误JSON。原formats CLI仍保留同步暂定RNX stdout、结束回执和原退出码，默认格式逐字节兼容。

## 重新打开的文件接收方

consumeRestoredFile(directory,{consumer})明确选择legacy或modern-check，只读保存清单、报告和RNX，不需原CRX。先核对资格及两处原生报告一致，再经现有原生文件入口完整读取RNX，用该次消费返回的bytes/SHA与交付身份核对后才返回结果，不能仅凭路径或此前哈希接受。

modern-check复用inspectFile的原生OBS完成/质量报告。恢复包合格但OBS质量不合格时，delivery仍表示恢复包合格，downstream保留实际complete/acceptable/findings，接收CLI退出2。legacy复用consumeFormats，其报告表示语法完成，不伪造acceptable或物理质量结论。接收器交付完成/身份报告，全部测量仍在RNX文件中，不声称返回全文件历元数组。

共享consumeFormats只增加显式includeInputIdentity:true的同流IO回执；默认没有input字段、同步暂定回调不变。开启时input含bytes/lines/SHA；仅Native finish失败时，错误的verifiedInput/inputReadComplete保留已核对的EOF身份，原错误和旧默认行为不改。

接收CLI退出0表示完成；正常下游质量不合格退出2并保留完整结果；产物/身份/参数/原生输入失败退出1、stdout为空。版本、时标、跟踪码、轨道均不猜测。恢复器支持的某些事件/时标仍不在现代Checker范围，后者按旧合同拒绝，不把恢复成功称为新增Reader支持。

哈希仅核对保存字节一致性，不认证原CRX、测量真实性或一致恶意替换后的清单/数据。原头许可条目保留，外部数据不改授MIT。没有新格式、模型、第三方依赖或外部采用主张。

## 独立期待和验证

examples/restoration的手写两版流分别含C1C=1.234和旧L1=-3.250，GPST日历tick14776992000000001。完整RNX预期、原字段和原生报告在修改前冻结。LegacyEpoch的缺省钟差字段省略，而嵌套ObservationValue空LLI/SSI为JSON null，分别保持。

真实预算输入由独立字面配方生成约38MiB CRX，其完整RNX超过512MiB；核对实际拒绝处的完整行/字节前缀及SHA。原生零值拼作右对齐的.000，而非最初假设的0.000，数值及14字节宽度相同；输入未删改，旧期待留存，实际拼写以修改前冻结的基线字节作复制兼容预期，不冒充新解码算法的数值证明。

node tools/test-crinex-file-delivery.mjs核对真实API/CLI、原CRX移走后的两类接收、质量分离、旧接口字节、截断/丢失、短写/EIO、源变化、回读不匹配、重命名后元数据失败、错误清单无法落盘、元数据及真实输出预算。故障只在独立测试进程拦截真实文件操作；生产代码无测试开关、替代预算或模拟解码器。可传不存在的新目录作为首参数保留本次结果。
