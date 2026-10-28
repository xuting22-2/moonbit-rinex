# 使用任务

接收一份声称覆盖全天的GPS观测文件，调用方明确给出日期；逐行处理后只有 complete=true 且 acceptable=true 才进入该策略下的下游队列。失败时按code/line/detail定位问题。别把退出2当作程序崩溃，更不能把退出1或中间计数当作通过。

`examples/consumer`展示纯MoonBit API；`examples/minimal.rnx`为原创最小成功输入；`examples/brux-first-two-epochs.rnx`为带署名许可的真实不完整日文件例。完整公开输入、命令与已知131/127差异见PUBLIC-DATA.md。没有实际机构接入，不承诺完整RINEX合规。
