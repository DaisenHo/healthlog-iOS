# T08：iOS 用药、目标与通知中文闭环

对应 [iOS #3](https://github.com/DaisenHo/healthlog-iOS/issues/3)，基于 T02 的账户语言与 T07 的健康模块中文资源。

本次沿用 String Catalog，为既有用药向导、计划、历史、来源标识、库存、GLP-1 记录、目标区间编辑、测量与预防保健提醒、通知渠道设置及相应错误增加简体中文。词条清单见 [覆盖清单](t08-localization-coverage.json)，包括共享词条。德文、英文及已存在的中文保留。

这里的目标仍是现有目标区间，没有新增通用目标引擎。服药依从率仍按已有计划计算，不将 Apple 健康服药记录次数解释为应服次数。药名、用户输入、来源记录、API 值、提醒调度、版本和授权门控保持原有行为，不决定 Apple 健康替代方案。

## 文案边界

- 药物浓度图的三条锁定德英文案，以及 `sources.method.glp1PK`、`sources.methodTitle.glp1PK` 保持原文。仓库的药物浓度说明要求逐字保留，T07 检查也明确禁止向这些词条加入中文。
- 服务端下发的通知正文继续由服务端负责。本次覆盖 App 的通知界面、本地通知回退文案和通知动作。
- Widget、Watch、通知服务扩展、权限说明、引导和其余设置由后续任务完成。本次不代表 M1 全部发布。

## 验证

`T08LocalizationTests` 复用现有 `ParityCatalog` 和 `CatalogFormatSignatureTests`：覆盖清单中的每个词条须有德英中资源；检查每个中文字符串单元、复数分支和替换参数的格式签名；通过账户语言解析确认来源、目标、提醒、错误、药名插值与周期复数的中英结果。

初始目录检查发现 778 个范围内词条缺少中文，追踪通知诊断入口后，共为 812 个词条增加中文；最终覆盖清单包含 1,027 个词条。翻译后目录检查通过。

- `xcodegen generate` 和模拟器测试构建通过。
- 定向回归：7 个测试组、18 项测试通过，含 T08、格式签名、复数、通知、用药效果文案和锁定药物浓度说明。审查追加的两条语义断言也在全量测试中通过。
- 完整 SwiftLint 警告基线通过：272 条既有警告，无新增警告或错误。目录卫生、德文泄漏、标点、CI 工作流契约、秘密扫描和 diff 检查通过。
- Standards 与 Spec 独立审查已完成，发现的上下文误译已修复，无未解决发现。
- 当前环境是 Xcode 27.1 / Swift 6.4，未达到仓库固定的 Xcode 26.6 CI 环境。`swift build` 直接构建成功；SPM 门禁与其健康夹具自测因新工具链不再输出旧式 `Compiling HealthLogCore <file>` 行而在计数上失败，不能将门禁写为通过。
- 本机缺少 `swiftformat`，未执行该格式检查。未做小屏、动态字体、VoiceOver 或完整中文界面旅程的视觉验收。

完整 `HealthLogTests` 目标执行了 9,914 项测试（1,430 个测试组），因 23 处断言问题未通过。问题位于本次未修改的五个文件：`DashboardSyncStatusRenderTests.swift`、`HLScoreRingRenderTests.swift`、`HealthSyncOrchestratorTests.swift`、`MeasurementListDateRangeTests.swift`、`SyncProgressRenderTests.swift`，涉及像素渲染、HealthKit 样本类型计数和日期范围。T08 两项测试在全量运行中均通过。未对原提交单独重跑这五组，因此不把这些失败称为已验证的基线失败。

全量测试引擎已输出上述最终汇总，但 Xcode 随后报告系统版本解析错误并停留于结果收集。等待约三分钟后终止该进程，未获得完整 `.xcresult`；全量结论来自保留的测试运行日志。
