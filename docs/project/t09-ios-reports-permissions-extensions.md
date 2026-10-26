# T09：iOS 报告、权限与配套扩展中文闭环

对应 [iOS #4](https://github.com/DaisenHo/healthlog-iOS/issues/4)，基于 T02 的账户语言、T07 的健康模块中文资源与 T08 的用药/通知中文资源。

## 范围

本次完成主 App 剩余词条、本地医生报告语言分支、系统权限说明，以及随 App 交付的四个配套目标（`HealthLogWidgets`、`HealthLogNotificationService`、`HealthLogWatch`、`HealthLogWatchWidgets`）的简体中文支持：

- **本地医生报告与回退路径**：`ReportLocale` 新增 `.zh = "zh-CN"` 与 `init(serverCode:)`，覆盖 `DoctorReportDisclaimer`、`LocaleText`（封面、生命体征表头、趋势图、用药、服药依从性、心情汇总与标签）、`DateRangeFormatter`（`至`）和 `PDFMeta` 标题。`UnifiedSharingStore.produceLocalPDF` 与 `ExportStore.makeLocalBundleJSON` 按当前账户语言代码解析 `ReportLocale`，不再把中文账户回退成德文。
- **系统权限说明与构建配置**：新增 `HealthLog/Resources/zh-Hans.lproj/InfoPlist.strings`，覆盖全部 9 项已声明的 `NS*UsageDescription`（Apple 健康读写、面容 ID、通知、AlarmKit 响亮闹钟、语音识别、麦克风、相机与文档保险库、Omron 蓝牙血压计），保持相册权限不声明。`project.yml` 与四个配套目标的 `Info.plist` 同步加入 `zh-Hans` 到 `CFBundleLocalizations`，并执行 `xcodegen generate` 更新工程文件。
- **四个配套目标 String Catalog**：为 `HealthLogWidgets/Resources/Localizable.xcstrings`（含补齐 `MoodWidget` 直接引用的 `Lousy`、`Bad`、`Okay`、`Good`、`Great` 共 52 个键）、`NotificationServiceExtension/Resources/Localizable.xcstrings`（2 个锁屏脱敏键）、`HealthLogWatch/Resources/Localizable.xcstrings`（41 个键）和 `HealthLogWatchWidgets/Localizable.xcstrings`（9 个键）补齐 `zh-Hans`。
- **账户语言切换与快照刷新**：`AppContainer.wireSharedAccountPrefs` 在账户语言变更时触发 `LatestMeasurement` Widget 快照刷新与 Watch 快照重推，使主进程预格式化的指标标题和单位及时更新。
- **主 App 剩余词条与边界**：为主 App `HealthLog/Resources/Localizable.xcstrings` 剩余的 1,722 个非排除词条补齐简体中文（设置其余页面、引导、助手、App Intents 与快捷指令、报告导出叶节点与免责声明、Spotlight、本地简报、应用锁等），清单见 [覆盖清单](t09-localization-coverage.json)。`MiniCoachPrompt`、`MiniCoachAskClassifier` 与 `MiniCoachDataBinder` 补齐中文分类、提示词、历史与拒绝/不支持分支，`CacheInvalidator` 的指标洞察缓存失效增加 `zh-CN`。75 个受验证临床量表词条与 5 个锁定的 GLP-1 药代动力学词条继续保持原文，不添加 `zh-Hans`。

## 平台限制

- iOS 系统权限弹窗（`InfoPlist.strings`）、组件画廊与控制中心画廊名称，以及运行在独立进程中的 Widget、Notification Service Extension、Watch App 和 Watch 复杂功能内的静态界面词条，由系统按设备语言或系统“设置 → App → HealthLog → 语言”匹配 `CFBundleLocalizations` 解析，无法由主进程内的运行时账户语言直接覆写。
- 主进程写入 App Group 或推送到 Watch 的预格式化快照字段（如最近测量的指标名称与单位）跟随账户语言，并在账户语言切换后刷新；实况活动在启动时按当前账户语言写入锁屏隐藏药名占位标题（已启动的实况活动受 ActivityKit 静态属性限制，在下次启动或状态重建时更新）。
- 本次未在模拟器上执行小屏、动态字体、VoiceOver 或完整中文界面旅程的人工视觉验收（留待 M1 整体验收 T10 统一完成）。

## 验证

- `T09LocalizationTests`：验证 `ReportLocale(serverCode:)` 映射、使用虚构健康数据生成 6 页中文医生报告 PDF、Mini-Coach 中文拒绝/不支持文案、`CacheInvalidator` 的 `zh-CN` 缓存键、`zh-Hans.lproj/InfoPlist.strings` 9 项权限说明与 5 个发布目标的 `CFBundleLocalizations`、4 个配套目标目录与格式签名、账户语言切换后的 Widget/Watch 快照刷新，以及主 App 1,722 个新增中文词条的覆盖和参数格式签名。
- 定向回归：15 个测试组、98 项测试全部通过（含 `T09LocalizationTests`、`T08LocalizationTests`、`CatalogFormatSignatureTests`、`PluralVariationGuardTests`、`EmptyTranslationGuardTests`、`CoNamedKeyGuardTests`、`GlossaryGuardTests`、`AppGermanCopyGuardTests`、`PermissionDeclarationTests`、`AppReviewConfigurationTests`、`DoctorReportLocalSpecTests`、`DoctorReportEndToEndTests`、`DoctorReportServerAdherenceTests`、`DoctorReportServerFiguresTests`、`MiniCoachServiceTests`）。
- 构建与资源检查：`xcodegen generate`、`HealthLog`（含 `HealthLogWidgets`、`HealthLogNotificationService`）与 `HealthLogWatch`（含 `HealthLogWatchWidgets`）模拟器构建通过，5 个编译产物均生成 `zh-Hans.lproj`。本机未安装 watchOS Simulator runtime，因此对 Watch 目标完成编译与产物资源核验，未在 watchOS 模拟器中运行交互。
- 门禁脚本：`scripts/t07_zh.py --check`、`scripts/check-strings.sh`、`scripts/check-missing-strings.sh`、`scripts/check-visible-punctuation.py`（含 `--self-test`）、`scripts/i18n-guard.py HealthLog`、`scripts/lint-strict-baseline.sh`（含 `--self-test`，272 条既有警告、0 错误）、`scripts/verify-function-body-baseline.sh`（含 `--self-test`）、`scripts/scan-tracked-secrets.sh`、`scripts/test-ci-workflow-contract.sh` 和 `swift build` 均通过。
- 工具链说明：当前环境为 Xcode 27.1 / Swift 6.4（非 CI 固定的 Xcode 26.6），本机未安装 `swiftformat`，且 `verify-spm-core-build.sh` 因新工具链不再输出旧式 `Compiling HealthLogCore` 行而存在已知计数兼容限制。
