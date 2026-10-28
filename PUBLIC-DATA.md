# 公开数据与可复现结果

原始站点：BRUX00BEL，2026-09-23，Royal Observatory of Belgium / GNSSatROB；[DOI](https://doi.org/10.24414/ROB-GNSS-BRUX00BEL)，许可[CC-BY4.0](https://creativecommons.org/licenses/by/4.0/)。[数据集元数据](https://gnss.be/api/v1/epn/dataset/BRUX00BEL)与原始头均标明许可。下载地址：https://epncb.oma.be/pub/RINEX/2026/266/BRUX00BEL_R_20262660000_01D_30S_MO.crx.gz

原gzip 4986333字节，SHA256 ce01f694f036e4d8659e0f9e0375a22cb463207ed779574009cc5c4fcd482b58。用标准gzip解包后由GSI RNXCMP4.2.0的CRX2RNX转换，RNX 41314394字节，SHA256 0fe5e99ad02768434dc53b4c9d89603aa97e5ae924cf704e080b6c51279cd630。转换工具及其许可证另向官方获取；本项目不打包二进制。完整过程/工具散列见 examples/SOURCE.json。

```sh
# 普通RNX需由官方CRX2RNX先生成，不可直接传gzip或CRX
node tools/check-file.mjs /absolute/path/BRUX00BEL_R_20262660000_01D_30S_MO.rnx 2026 9 23 -1
python tools/reference/brux_reference.py /absolute/path/sample.rnx -o /absolute/path/reference.json
python tools/compare-reference.py /absolute/path/moonbit-report.json /absolute/path/reference.json
```

Node命令退出2是**预期**：头部声称131颗卫星，而体中127颗；PRN/#OF OBS细项缺失另报warning。2880时刻与30秒间隔本身一致。参考是独立Python标准库实现，不是GeoRust/gnss-js运行结果，也不判断RNXCMP是否丢失过数据。

仓库 `brux-first-two-epochs.rnx` 是转换后RNX的两个完整epoch字节前缀（保留未改动的整日声明），因此会报告缺失尾窗/头体不一致。节选处理为本项目所做，未改造其头部来伪造合格日文件。原始数据署名/许可保留；不暗示ROB支持本软件。

0.1.x 的 Checker 按原始3bit统计LLI，验证有限数值并统计非空/空/零；不保留测量序列。0.2.0 的 Reader 新增完整时刻的原始观测返回，详见 [RAW-OBSERVATIONS](RAW-OBSERVATIONS.md)，同样不计算多路径、周跳、可见性或坐标。短记录依据规范允许省略尾空格，不能凭空判断它是合法空字段还是传输丢掉了本应存在的数值；外部传输完整性需要源散列与独立声明。

2026-09-27追加：用固定GeoRinex1.16.2核对另一份公开CEDA3.03样本的时刻、信号计数和L1/L2 LLI，并独立复核814条间隔诊断。BRUX4.01未获该参考支持，原始版本头保持不变。详见 [GeoRinex参考](GEORINEX-REFERENCE.md)。

原BRUX4.01现在另有实际Rust rinex0.22.0对照，及直接比较当前MoonBit结果的便携工具。见 [GEORUST-REFERENCE](GEORUST-REFERENCE.md)；其成功解析不撤销头/体卫星数量不一致的QC结果。
