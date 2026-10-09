# 通达杯题1：双向无线测距与融合定位仿真

面向题1“基于 PlutoSDR 的双向无线测距与融合定位原型设计”的 MATLAB 仿真代码，包含 GFSK 风格同步、频偏补偿、独立校准、RTT/PBR 测距、相位消歧、融合与失效诊断。目前交付的是 **Simulation only** 测距闭环，供队友复现、分析与后续开发。

## 运行

已在 **MATLAB R2023a** 验证，只使用基础 MATLAB 函数。无需 Bluetooth、Communications、Signal Processing 或 Statistics Toolbox，无需 SDR 硬件。R2018b 尚未实机验证。

克隆仓库后，将 MATLAB 当前文件夹切换到 `topic1/topic1_v7/matlab` 目录，再运行：

```matlab
outputs = run_all;
```

默认执行自检、7,200 次主测试和参数敏感性分析。快速检查可运行 `outputs = run_all(3);`。本机重跑写入已忽略的 `results/`；已验证基准位于 `reference_results/`。大型 MAT 缓存可重跑生成，未提交到 Git。

## 模块结构

| 路径 | 职责 |
| --- | --- |
| `run_all.m` | 完整运行入口 |
| `+td1/defaultConfig.m`、`prepare.m` | 配置、探测波形与搜索缓存 |
| `+td1/simulate.m`、`observe.m` | 复基带 IQ 仿真、CFO/TOA/双向相位估计 |
| `+td1/calibrate.m` | 独立已知参考距离校准 |
| `+td1/estimate.m`、`phaseSlope.m` | RTT/PBR、候选距离、质量筛选与融合 |
| `+td1/receiverConfig.m` | 接收机参数白名单，隔离仿真真值 |
| `estimate_capture.m` | 已保存观测的处理入口，数据格式见原始 `README.txt` |
| `tests/test_topic1.m` | 物理不变量与失效分支自检 |
| `run_topic1.m`、`run_sensitivity.m` | 主测试与独立参数扫描 |
| `reference_results/` | 已验证的逐次试验、汇总、诊断、图与运行记录 |
| `results/` | 本机重跑生成的文件，已加入 Git 忽略规则 |

## 原始基线参考结果

下列 `reference_results/` 是原始 `topic1/matlab` 基线的副本，不能作为本版本新增实验模块的验证结果。原始校验清单描述旧基线源码，部分 SHA 与本版本不同是预期现象；本次 PR 的独立审核记录见 [审核记录](../../review_20261009/REVIEW.txt)。

2026年10月9日，MATLAB `9.14.0.2206163 (R2023a)` 完整运行通过：

- **10 项自检通过**。
- 6 场景 × 6 距离 × 4 SNR × 50 次，共 **7,200 次主测试、720 行方法汇总**。
- **540 次独立参数扫描**，覆盖 CFO、相位噪声、多径和时钟/时延漂移。
- MATLAB `checkcode` 无诊断；Python 标准库独立重算统计与比例分母，验证通过。

可复核 [MATLAB 验证记录](reference_results/verification/verification.json)、[独立统计核验](reference_results/verification/independent_validation.json)及 [完整运行日志](reference_results/full_run.log)。这些记录证明声明的仿真与自检通过。

## 范围与解释

同步探测序列采用自定义 GFSK 风格波形；代码未实现完整 BLE Channel Sounding 协议、LE2M 互操作或两台设备的收包/回复调度状态机。RTT 使用等效返回波形；PBR 假设理想互易、可校准的双向相位与声明的共同调度时间轴。真实 Pluto 收发、设备时序、OTA 测距以及二维多节点定位仍需后续实现与验证。

校准来自独立 LOS 已知距离数据，不能消除测试多径或测试后的漂移。RTT 与 PBR 的共同偏差、相关误差及跳频 PLL 相位变化可能使融合失败，**不能承诺融合总能提高精度**。结果中的 `NaN` 表示量测不可用，比较误差时应同时查看有限样本数、可用样本数与诊断比例。CPU 耗时是离线 MATLAB 估计耗时，不能作为无线系统时延。

完整假设、输出字段与解释见 [原始运行说明](README.txt)。GitHub 模块参考、许可证与取舍见 [参考与模块取舍](docs/参考与模块取舍.txt)；算法为基础 MATLAB 独立实现，没有第三方运行时依赖。

## 队友协作

每人使用独立分支，通过 Pull Request 合并代码；提交时说明变更、验证方法及对结果的影响。个人实验的 `results/` 不提交；确需更新 `reference_results/` 基准结果时，在 PR 中一起说明配置、随机种子、运行环境及差异。赛事资料、报名和提交不属于本仓库代码交付范围。

## 查看仿真结果

- [误差曲线](reference_results/benchmark/rmse.png)
- [失效与回退诊断](reference_results/benchmark/robustness.png)
- [参数敏感性](reference_results/sensitivity/sensitivity.png)
