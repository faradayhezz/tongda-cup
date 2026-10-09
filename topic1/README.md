# 通达杯题1代码入口

[原始可复现基线](matlab/)保留原样。新增版本采用独立目录，运行时只添加一个版本的 MATLAB 路径，避免同名 `td1` 包混用。

| 版本 | 主要内容 | 本次审核状态 |
| --- | --- | --- |
| [v1](topic1_v1/matlab/) | 相位曲率诊断与可选 PBR 单独回退 | 队友正在补传，最后审核 |
| [v2](topic1_v2/matlab/) | 双径候选拟合 | 基础自检与入口测试通过 |
| [v3](topic1_v3/matlab/) | 双径候选门控 | 基础自检与入口测试通过 |
| [v4](topic1_v4/matlab/) | 分频点稳定性检查 | 基础自检与入口测试通过 |
| [v5](topic1_v5/matlab/) | 模型复杂度与软修正 | 基础自检与实际候选测试通过 |
| [v6](topic1_v6/matlab/) | 频率跨度及回波可辨识性实验 | 基础自检与入口测试通过 |
| [v7](topic1_v7/matlab/) | 强回波候选救援 | 基础自检与入口测试通过 |
| [v8](topic1_v8/matlab/) | RTT/PBR 冲突实验策略 | 基础自检与六场景入口测试通过 |
| [v8_1](topic1_v8_1/matlab/) | 独立六场景回归入口 | 完整基线、独立回归及多径实验通过运行核验 |

在 MATLAB R2023a 中进入 `topic1/topic1_v8_1/matlab`，可运行：

```matlab
outputs = run_all;
paired = run_v8_1_regression(50,202610091);
conflicts = run_v8_conflict(20,202610092);
addpath('tests'); report = test_experimental_policies;
```

新增策略仍为独立实验入口，没有自动替换默认测距结果。审核与数据见 [审核记录](review_20261009/REVIEW.txt)、[六场景回归](review_20261009/paired_summary.csv)、[多径实验](review_20261009/multipath_summary.csv)。

当前所有结果为仿真；原六场景中的轻多径和校准漂移仍有米级偏差。更宽频率跨度中的改善不能直接作为 Pluto 实测性能，原始 `reference_results` 副本也不能充当新增实验的验证证据。
