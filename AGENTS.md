# AGENTS.md

本文件供在此仓库工作的 AI 编程助手使用。目标是先理解已有实现，再做最小、正确、可维护的改动。

## 工作方式

- 用户当前的明确要求优先于仓库中的一般建议；处理子目录时，同时检查该目录适用的 `AGENTS.md`。
- 默认用中文沟通。先说明准备检查或修改什么；完成后说明改动、理由、验证结果和剩余限制。
- 动手前检查 `git status`、相关目录、依赖、周边实现和已有测试。能从仓库查明的问题，不凭印象猜测；搜索优先用 `rg`。
- 保留用户已有的未提交改动，不覆盖、回退或清理无关文件。改动应限于当前任务，避免顺手重构、全仓格式化和无关配置调整。
- 优先复用现有抽象和约定，不为单一场景引入通用框架、重复逻辑或额外依赖。
- 修复问题时查明根因；显式处理错误，不用空结果或静默捕获掩盖失败。
- 大规模重构、架构调整、重大依赖引入或公共 API 变更，若尚未获授权，先说明方案、影响和取舍再确认。已经明确授权的工作不重复请求确认。
- 不自动提交、推送、发布或改写 Git 历史；不删除测试来让检查通过。
- `TODO.md` 是未来计划，不是已实现能力，也不是自动执行全部任务的指令。只推进本次请求涉及的条目，完成并验证后再更新状态。

## 项目地图

Selume / Moodiary 是 Flutter + Rust 的日记应用，正文编辑器使用 Vue + TipTap。根目录是 Dart workspace / Melos 协调层，移动应用位于 `mobile/`。

| 位置 | 职责 |
| --- | --- |
| `mobile/lib/app/` | 应用组合、依赖注入、路由、生命周期和设置 |
| `mobile/android/`、`mobile/ios/` | 平台入口和原生配置 |
| `packages/foundation/` | 基础工具、路由定义、国际化、UI 基础和 Rust 桥接 |
| `packages/core/` | 平台、网络、文件、KV 存储、主题等基础设施 |
| `packages/feature_base/moodiary_models/` | 领域模型与事件 |
| `packages/feature_base/moodiary_data/` | Drift 数据库、仓储与跨页面状态 |
| `packages/feature_base/moodiary_editor/` | Flutter 编辑器桥接；`editor/` 中是 Vue / TipTap 源码 |
| `packages/feature_base/moodiary_ml/` | 本地 ONNX 模型、下载及推理 |
| `packages/feature/` | 日记、助手、同步、导入导出、媒体、应用锁等功能 |
| `tool/` | 任务入口、依赖层级和生成代码检查 |

SDK 与依赖版本以 `.fvmrc`、各包的 `pubspec.yaml`、`Cargo.toml`、`rust-toolchain.toml` 和编辑器 `package.json` 为准，不顺手升级。

## 架构和代码约定

- 依赖层级从低到高为 `foundation → core → feature_base → feature → mobile`。高层依赖低层；功能包不互相导入，跨功能组合放在应用层，共享实现放到合适的下层。
- `core`、`feature_base` 内部也有依赖顺序，具体以 `tool/check_layers.dart` 为准，不通过增加例外绕过检查。
- 服务和仓储使用 `get_it` / `injectable`，容器内优先构造函数注入；Riverpod 管理 UI 生命周期内的状态，不另造一套仓储容器。
- 路由定义放在 `moodiary_router`，沿用 typed route 和 `extra` 参数，传递可序列化的 ID、布尔值等，不携带会过期的领域对象快照。
- Flutter UI 沿用 `mui` 与现有主题；用户可见文案走现有国际化，避免另起一套组件、颜色或硬编码文案。
- 编辑器行为修改 Vue / TipTap 源码，保持 Dart 桥接协议一致；不直接修改构建出的编辑器资源。
- 生成代码修改其源文件后重新生成，不手改 `*.g.dart`、`*.freezed.dart`、FRB 绑定等生成产物。
- 日记正文、分享文本和密钥不应被写入诊断日志；错误日志保留定位所需信息，避免暴露用户内容。

## 数据与兼容性

- 数据库结构源文件在 `packages/feature_base/moodiary_data/lib/src/db/*_tables.drift`，迁移入口在同目录的 `database.dart`。改结构前先检查已有迁移、读写路径和相关测试。
- 为已有数据库追加兼容迁移，不破坏已发布的迁移逻辑；同时检查模型序列化、导入导出、备份和同步的兼容性。
- 持久化的枚举名称、字段和标签/分类关系不能直接删除或重命名；先确定旧数据如何读取或迁移。
- 写入沿用仓储与领域事件流程。用户编辑和同步/迁移落库对 `lastModified`、`fromSync` 的处理不同，不混用，具体见数据包说明。
- FTS 索引由数据库触发器维护，不另加一套 Dart 写索引逻辑。

## 验证与常用命令

先跑最小相关验证，再扩大到受影响的包。行为变化应补充有意义的测试，修复缺陷时优先增加回归覆盖。仅修改文档时检查内容、链接和差异即可。

以下任务命令在仓库根目录执行，按需要选择；环境缺少工具时如实说明，不把未运行的检查报告为通过。

| 用途 | 命令 |
| --- | --- |
| 安装 Flutter 依赖 | `fvm dart tool/task.dart setup` |
| 运行移动应用 | `fvm dart tool/task.dart run` |
| 检查生成代码、分层和静态分析 | `fvm dart tool/task.dart analyze` |
| 仅检查依赖层级 | `fvm dart tool/task.dart check-layers` |
| 测试改动影响的包及其依赖方 | `fvm dart tool/task.dart test` |
| 指定测试比较基准 | `fvm dart tool/task.dart test --diff=<ref>` |
| 仅移动应用测试 | `fvm dart tool/task.dart test-mobile` |
| 全部 Dart / Flutter 测试 | `fvm dart tool/task.dart test --all` |
| Dart 模型、DI、Drift 等生成 | `fvm dart tool/task.dart build-runner` |
| Rust FFI 绑定生成 | `fvm dart tool/task.dart gen-rust` |
| 国际化生成 | `fvm dart tool/task.dart i18n` |

- Flutter 单个测试：在相应包目录运行 `fvm flutter test test/<file>.dart`。根目录不是应用，不直接在根目录运行裸 `flutter test`。
- Web 编辑器：在 `packages/feature_base/moodiary_editor/editor/` 运行 `corepack pnpm type-check`、`corepack pnpm test`；可向测试命令传入相关测试文件。使用仓库指定的 pnpm，不切换包管理器或重建其他锁文件。
- Rust：在受影响包的 `rust/` 目录运行 `cargo fmt --all`、相关 `cargo test`，再运行 `cargo clippy --all-targets -- -D warnings`。
- 格式化限定于本次修改的源文件。`build-runner` 任务目前会生成全 workspace 并格式化全仓，运行前检查工作区，运行后仔细核对差异，保护已有改动。
- 共享核心或依赖行为变化、用户要求完整验证时，再跑完整相关套件；全仓检查范围参考 `.github/workflows/quality.yml`，不仅包含 Dart，还包含原生 Rust 和 Web 编辑器。
- 旧 Isar 数据库迁移集成测试需要 `ISAR_TEST_DYLIB`。缺少库导致跳过时，应明确报告，不视为迁移验证通过。

## 按需阅读的现有说明

只读取本次任务相关部分，避免把所有细节复制到本文件。

- 总体实现约定：[CLAUDE.md](CLAUDE.md)
- 移动应用组合：[mobile/CLAUDE.md](mobile/CLAUDE.md)
- 仓储、事件和同步写入边界：[数据包说明](packages/feature_base/moodiary_data/CLAUDE.md)
- 国际化：[国际化说明](packages/foundation/moodiary_i18n/CLAUDE.md)
- 编辑器桥接与构建：[编辑器说明](packages/feature_base/moodiary_editor/README.md)
- 后续产品计划：[TODO.md](TODO.md)

这些说明提供项目背景；发现其中的路径、版本或命令与实际代码不一致时，先核实源码和脚本，不传播过时信息。维护本文件时保留稳定、可执行的规则，避免加入临时任务状态或机器专属绝对路径。
