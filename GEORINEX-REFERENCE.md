# GeoRinex 公开观测文件交叉核对

本轮保持 MoonBit 核心和0.1.0 API不变，用未经修改的 GeoRinex 1.16.2核对公开 CEDA RINEX 3.03测试样本。来源固定在 [GeoRinex提交8d1210a](https://github.com/geospace-code/georinex/tree/8d1210a0f1ada71ff7b8d0484cfaf22ff154a38e)，输入路径 `src/georinex/tests/data/CEDA00USA_R_20182100000_23H_15S_MO.rnx.gz`。只解压gzip，没有改头部或补写数据。文件名带23H不证明其中包含完整23小时的测站原始数据；它是上游保存的参考样本。

实际比较通过：4675个时刻、19个卫星标识、27项系统/信号的非空和零值计数（共107714个非空字段），以及5项可获取的相位LLI计数。逐项结果见 [comparison.json](evidence/georinex-20260927/comparison.json)。这里核对的是计数，不是保存或逐值比较所有测量数值。

MoonBit指出814处相邻时刻间隔与头部INTERVAL不同；GeoRinex解析出的时刻差独立确认了这个数目。文件检查保持退出2，`complete=true, acceptable=false`。没有为了使示例变绿而改样本或放宽政策。

## 复现

在独立Python3.12环境安装 `python -m pip install -r tools/georinex-requirements.txt`，实际完整依赖版本另存于 evidence目录。

```sh
python tools/fetch-georinex-reference.py /new/reference-directory
moon build --target js --release
python tools/compare-georinex.py /new/reference-directory/CEDA00USA_R_20182100000_23H_15S_MO.rnx --evidence /new/comparison.json
```

固定输入SHA256为 `2563103ee2803a16f81c068658b6c7a210dd379f53327ff79b7de29afb034ee9`。获取器校验压缩和解压后两份散列，并拒绝覆盖已有目录。上游项目采用MIT许可；本轮未逐项确认其测站输入原始数据的独立许可，所以产品包只带链接、散列和检查程序，不再分发该输入文件。

## 独立参考的边界

- GeoRinex 1.16.2公开入口实际拒绝RINEX4.01。现有BRUX4.01未被修改成3.x去迎合参考；该文件仍仅由原手写参考核对。本次增加的是另一个输入上的成熟解析器实测。
- 此版本只输出L1/L2的LLI变量；其余4项相位信号不计为本次独立LLI验证。缺少变量不当成计数为零。
- GeoRinex的NaN填充无法区分没有卫星行与存在但全空的行，因而没有声称它独立证明原始行数和空槽总数。
- 时刻按文件GPS日历标签比较，没有UTC换算，也没有定位、物理可用性或EPN认证结论。它不验证所有非法输入的拒绝行为，原有失败测试继续独立保留。

产品源码指纹与上一份核心回执一致；本轮只增加参考检查和材料，没有重复运行不受影响的整个核心测试集，也没有公开发布或执行远端CI。
