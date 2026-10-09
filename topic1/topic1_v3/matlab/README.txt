通达杯题1 MATLAB 仿真代码

运行环境
本代码仅调用基础 MATLAB 函数，目标环境为本机 R2023a。代码尽量采用
R2018b 已有语法，但尚未在 R2018b 运行。无需 Bluetooth、Communications、
Signal Processing 或 Statistics Toolbox，无需 SDR。全部输出为 Simulation only。

一键运行
1. MATLAB 当前文件夹切换到本 README 所在目录（仓库中为 topic1/topic1_v3/matlab）。
2. 输入 outputs = run_all;
   默认每个距离/SNR/场景测试 50 次，并执行自检与独立参数敏感性分析。
   快速集成检查可用 outputs = run_all(3);
3. 只运行单项：
   addpath('tests'); report = test_topic1;
   results = run_topic1(fullfile(pwd,'results','benchmark'),50);
   sensitivity = run_sensitivity(fullfile(pwd,'results','sensitivity'),20);

主要模块
+td1/defaultConfig.m 配置、随机种子和六个声明的场景。
+td1/prepare.m       自写 GFSK 同步模板、tone模板和匹配滤波搜索缓存。
+td1/simulate.m      生成同步和双向tone复基带IQ。
+td1/observe.m       由IQ估计CFO、TOA、双向相位和质量。
+td1/calibrate.m     从独立已知参考距离观测拟合硬件/固定时延校准。
+td1/estimate.m      RTT、PBR候选解、置信度筛选与融合。
+td1/receiverConfig.m  接收机设计参数白名单，隔离信道与硬件真值。
+td1/phaseSlope.m    独立展开相位与线性回归算法，交叉核对PBR。
estimate_capture.m  已保存IQ的处理入口；采集文件含obs、cfg，校准文件含cal。
tests/test_topic1.m  物理不变量和失效分支自检。
run_sensitivity.m   CFO、相位噪声、多径强度、时钟漂移、时延漂移扫描。

仿真范围与证据口径
同步是2 Msymbol/s、BT=0.5、h=0.5的GFSK风格自定义探测序列，tone为已知
复正弦。它不是完整 BLE CS SYNC/CS Tone 封包，也不声明 LE2M 互操作合规。
RTT采用等效返回波形：已知本地回复等待、两个方向的传播和H(f)^2等效信道。
未实现真实的两台设备收包、检测、回复调度状态机；同步检测和TOA在IQ上执行。
假设接收记录与设备发射样本原点已对齐。主机调用耗时或USB到达时间不可替代它。

独立时钟采用 A、B 时间倍率 aA=1+ppmA*1e-6、aB=1+ppmB*1e-6：
R_A=aA*(2*d/c+D_B/aB)+T_hw。采样钟误差在往返时标中建模，未完整重采样
探测波形的SFO。LO频偏独立建模，CFO补偿不会冒充采样钟/回复钟校准。
已知参考距离校准只能消除稳定固定回复时间下的偏差，漂移场景显式展示其限制。

PBR使用理想互易、已校准双向相位关系。先由tone IQ估正反CFO，既补窗口内旋转，
也补交换间隔相移。exchangeGapS来自声明的等效共同调度时间轴；真实设备必须
测定这一映射，不能拿仿真中的理想调度当已完成Pluto双机同步。
未知共同相位由相干度幅度消去。线性硬件相位与距离混淆，需要已知距离校准。
随机跳频独立PLL相位不是固定校准能够修复的误差，单独列为失败场景。

校准数据与测试数据使用不同随机种子。校准为已知距离的LOS参考链路，不包含
测试多径或测试后的漂移。估计器不读取真距离、真CFO、真硬件时延、场景标签。
方差来自独立校准重复和IQ残差，RTT 0.25 m、phase 0.025 rad下限为公开设计参数，
不是Pluto实测精度或NLOS置信区间。CFO带来的跨频点相关斜率误差单独传播。
RTT与PBR共同偏差及其交叉相关仍可能导致融合失败，不能承诺融合总能提高精度。

常规频点间距1 MHz，距离周期149.896 m，在0–40 m设计范围内无周期模糊。
Sparse_alias单独使用5个8 MHz间隔频点，周期18.737 m；测距点仍为1/3/5/10/15/20 m。
它展示RTT选择PBR分支的作用，不是常规1 MHz方案普遍存在模糊的证据。
各tone逐频采集；总频率跨度不是20 MSPS接收机的瞬时带宽。
独立PBR有多个等价候选时输出最小候选并设置PBR_Ambiguous，候选全集供融合使用。
低质量phase但可信RTT时回退RTT；无同步/非法CFO时融合量测为NaN并记录原因。

输出
results/benchmark/trials.csv 每次试验五条基线/估计、状态、质量、运行耗时。
results/benchmark/summary.csv MAE、RMSE、偏差、95%绝对误差、有限/可用样本数。
results/benchmark/diagnostics.csv 融合通过、RTT回退、不可用比例、变差和别名错误率。
results/benchmark/rmse.png 与 robustness.png 仿真图。
results/sensitivity/ 参数扫描结果、sensitivity.png。
results/verification/ 自检表与运行环境记录。
results.mat保留配置、校准及数值结果，可追溯每个参数。程序重跑会覆盖相应结果目录。
AbsErrorOver1mRate中1 m是自行选定的观察阈值，赛题未规定硬性精度门槛。
NaN表示不可用量测；不要把剔除无效后的RMSE当作所有包的成功率，需同时看FiniteN
和UsableN。FiniteN只说明产生了数值，UsableN说明质量检查通过；Raw_RTT与Raw_PBR
为消融诊断，不声明可用率。PBR失效时仍保留其数值误差展示失败，但PBR_Usable=false。
FusionWorseThanPBR仅在PBR可用且融合量测有限时比较；别名错误率仅统计接受的
多候选融合决策，各自分母为ComparedN、AliasDecisionN。最小别名策略影响对比。
CPU耗时是MATLAB离线估计耗时，不能宣称OTA系统实时延迟。

来源
GitHub参考、许可证与模块取舍见docs/参考与模块取舍.txt。所有算法在本目录中
用基础MATLAB独立实现，没有下载或执行第三方仓库代码，没有额外运行时依赖。
赛事报告、报名和提交不在本次代码交付范围内。二维多节点定位为赛题加分项，
当前优先完成测距仿真闭环；真实Pluto收发、设备时序和OTA须硬件阶段验证。
本GitHub目录只发布v2版本；旧教学基线和赛事资料未包含，原件保持不变。

本次验证记录
2026年10月9日本机 MATLAB 9.14.0.2206163 (R2023a) 完整运行通过。
10项自检通过；6场景×6距离×4 SNR×50次，共7200次主测试、720行方法汇总；
另外完成540次独立参数扫描。全部MATLAB源文件checkcode无诊断。
另用Python标准库从逐试验CSV独立重算720行统计，检查比例分母、重复记录和
频偏超范围失效返回，全部通过；原交接16文件SHA-256均未改变。
详见reference_results/verification/verification.json、independent_validation.json、
checkcode.json与reference_results/full_run.log。这些记录只证明声明仿真与自检通过。

GitHub布局说明
已验证CSV、PNG与校验记录存放在reference_results/；程序运行生成results/（已忽略）。大型results.mat重跑生成，不进入Git历史。

审核补充 2026年10月9日
reference_results是原始基线副本，并非本版本新增实验的测试证据。
独立审核见topic1/review_20261009；输出类型新增OutputMode与PBRFallbackRate，PBR单独回退不再计作RTT回退。
run_compare_v1现在直接成对运行默认与实验分支，不需要修改共享配置文件。
