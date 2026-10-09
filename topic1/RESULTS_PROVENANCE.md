# 运行结果与版本对应说明

本目录保留本地 MATLAB 项目的版本结构。文件上传成功仅说明文件已同步，不等于所有版本均已独立运行或重新验证。

## 旧基线参考结果

根目录 `matlab/reference_results/` 是既有基线。`topic1_v2` 至 `topic1_v8_2` 中各自的 `matlab/reference_results/` 都沿用了这一基线的 14 个文件，逐字节相同。

这些参考结果所带 `verification/source_snapshot.json` 记录的以下四个 MATLAB 文件，与各版本当前文件的校验值不匹配：

- `+td1/defaultConfig.m`
- `+td1/estimate.m`
- `+td1/receiverConfig.m`
- `run_topic1.m`

因此，这些旧参考结果及其中的通过记录不能用来证明对应新版本已通过验证。这里保留原记录，不修改其来源或把旧结果重新标为新版本结果。

## 补充上传的本地实验输出

各版本 `matlab/results/` 内的实验表格、图片和说明来自用户本地文件夹。此前它们被 `results/` 忽略规则排除；本次逐项纳入版本管理。其他新产生的结果仍遵循原有忽略规则。

- 根 `matlab/results/`、v1 的 benchmark、sensitivity 与 verification 是本地保存的输出。
- v2 至 v8_1 分别保存 probe、frequency study、diagnostic、conflict、regression 等实验输出。
- v8_2、v9_A、v9_A_1 本次同时补充上传代码和本地现有实验输出。

这些文件没有在上传过程中重新计算；没有可靠源码快照关联的输出，不能仅凭所在目录认定一定由当前代码生成。复核应同时记录源码校验值、参数、随机种子和 MATLAB 版本。

## v1 缺失依赖

本地原始 `topic1_v1/matlab/+td1/observe.m` 缺失，上传时副本中也不存在。v1 的 `receiverConfig.m` 已在仓库中，两者不是同一文件。

在恢复 MATLAB 默认搜索路径后，仅加入 v1 及其 tests 目录，运行 `test_topic1` 会在第 104 行报告无法解析 `td1.observe`。本次文件补传不会自动修复这一问题，也不会从其他版本借用同名文件冒充原始 v1 实现。v1 的历史通过记录不能证明该目录目前能够独立运行。

## 审核修复补充

以上 v1 缺失情况描述原上传快照。后续审核提交明确从已验证基线补齐 `observe.m`，作为新修复而非原件还原，独立自检与运行检查通过。新结果见 [最终审核记录](review_20261009/FINAL_REVIEW.txt)，不重写原归档验证记录。
