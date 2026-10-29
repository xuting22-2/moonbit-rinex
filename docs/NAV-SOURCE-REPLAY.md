# 选中NAV来源与实际文件重放

`queryNavigationWithSource(file, options)`与现有点查询使用同一筛选策略、参数、容量和错误边界。它启用原生来源捕获，整份输入通过原生finish及文件读取检查后，返回`{result,source,receipt}`。普通`queryNavigation`和不带`--source`的CLI保持原JSON/回执；批查询格式不变。

```sh
node tools/nav-query.mjs examples/catalog-synthetic.nav G01 2442 50500 --source
node examples/nav-source-replay.mjs examples/catalog-synthetic.nav NEW_SELECTED.nav examples/nav-source-query.json
```

带`--source`时stdout为`{result,source}`，stderr仍是加载回执。selected退出0；unavailable/ambiguous退出2且source=null；参数/输入/IO失败退出1、stdout为空。没有唯一选择就没有猜测的载荷。

## 来源对象

selected的`source`包含：

- `record_index`：原目录稳定、从1起的受支持记录索引。
- `first_line`、`last_line`：原文件从1起的物理行号，含头和跳过记录；所选记录共八行。
- `header_lines`：从首行到END OF HEADER的全部原文，含COMMENT、署名和未解析头记录。
- `record_lines`：同次原生解析、供选中目录记录使用的八行原文，保留大小写、D/E指数和末尾空格。

行分隔符不在字符串中，文件宿主把LF/CRLF拆开。该对象不保留原始分隔字节或原始全文件哈希，不认证提供者、不保证抵御主动并发替换。加载回执仍清楚区分成功读取与查询状态；显式跳过的其他星座只按长度跳过，未作数值认证。

来源缓存只在新入口启用，最多保存目录容量内的记录（默认4096、上限32768），没有历史无界增长。512MiB输入、4096行头、ASCII及已有NAV记录宽度限制不变。

## MoonBit公开入口

`NavReader::new(capture_source=true, skip_unsupported=false)`可直接使用。`header_lines()`返回完整头的复制数组，未启用时为空。每次`feed_line`开始清除上一条来源；只有该次成功发出受支持记录时，`last_record_source()`返回`NavRecordSource {first_line,last_line,raw_lines}`的复制快照。成功finish保留最后快照。

这些增量来源在成功finish前都是暂定结果，不能当作整文件完成证明。快照数组修改不会影响reader；默认不捕获，不增加目录原始记录存储。桥仅在成功完整加载后开放查询来源，原session未启用捕获时不能请求来源。

## 可运行接收方

`examples/nav-source-replay.mjs`导出`replaySelectedNavigation(input,newReplayFile,options)`。CLI第三参数是最多1MiB的查询JSON，字段与点查询API相同；示例显式列出GPST、轨道和容量，调用方决定BDS所需轨道类型。

该接收方会：

1. 完整查询输入，并取得原生绑定的来源对象。
2. selected时用独占创建方式写入全部原始头及所选八行，仅把换行统一为LF，随后关闭文件。
3. 用现有`queryNavigation`真正重新打开该文件，以相同参数读取、finish并查询。
4. 核对卫星、消息、Toc/Toe、健康标记及整个状态，成功后才返回包含原查询与重放查询的结果。

子文件的目录索引是1，起始行是header_lines.length+1。原目录的其他候选、淘汰原因和等价记录计数不等于子文件的结果，不复制成新的证明。只重放原先唯一选中的状态，不能用它重现被舍弃候选的排序过程。

没有唯一选择时不创建文件，退出2。已存在目标受独占创建保护；解析、写入、关闭或重读失败时退出1且无成功stdout。晚失败可能留下文件，没有通用回滚、fsync、断电事务或仅凭文件名的合格承诺；接收方成功结果才说明本次实际重读已完成。

这是项目自编的实际文件消费者，不是第三方采纳。它支持既有NAV2.11 GPS和NAV3.03/3.04/3.05 GPS/BDS范围，不增加NAV4或科学模型，不宣称原始空中电文、数据源真实性或物理轨道精度。

## 固定验证预期

`examples/nav-source/REFERENCE.json`及七份输入在实现前冻结。完整原文/物理行号来自已知固定布局，NAV2由自编GPS字段保留转换；数值使用已提交的独立RTKLIB2.4.3b34结果，日历标签用整数/Decimal独立计算。旧CLI完整stdout/stderr另外冻结为兼容预期，不当作独立数值预期。原始源码、外部数据许可和历史参照保持不变。
