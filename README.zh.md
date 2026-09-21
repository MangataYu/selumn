# selumn

简体中文 | [English](README.md)

一个使用 Flutter 和 Rust 开发、正文编辑器基于 Vue / TipTap 的个人日记应用。本分支由 [MangataYu](https://github.com/MangataYu) 维护，着重改进标签整理和日常浏览体验。

基于 [ZhuJHua 的 Moodiary](https://github.com/ZhuJHua/moodiary) 开发，为独立维护的衍生版本，非 Moodiary 官方发行版。

[下载](https://github.com/MangataYu/selumn/releases) · [源代码](https://github.com/MangataYu/selumn) · [后续计划](TODO.md)

![Flutter](https://img.shields.io/badge/Flutter-3.47.2-blue)
[![许可证](https://img.shields.io/github/license/MangataYu/selumn)](LICENSE)

仓库名称为 **selumn**；应用内名称及现有 APK 文件名目前使用 **Selume**。

## 本分支的改动

- **正文标签**：输入 `#工作/项目` 后加空格，即可形成标签；输入时提供已有标签候选，使用 `/` 表示层级。
- **标签管理**：搜索、重命名或删除标签及其子标签，并按层级调整显示顺序。
- **侧栏筛选**：通过可折叠标签树浏览记录，或快速查看无标签、含图片、链接或音频的记录；父标签筛选包含子标签。
- **侧栏导航**：集中访问媒体、地图、关联图谱、日历和助手。
- **记录概览**：在侧栏查看日记数、标签数、使用天数和记录热力图，点击日期查看当天记录数与字数。
- **本仓库更新源**：Android 的“检查更新”连接本仓库的 GitHub Releases。

计划中的功能及待完成的验证见 [TODO.md](TODO.md)。从其他应用快捷收录文本、感受体系改造、导入后的 AI 辅助整理仍属于后续计划。

## 日记功能

- **富文本与媒体**：在日记中插入图片、音频和视频。
- **搜索与标签**：全文搜索，按标签筛选记录。
- **主题与字体**：浅色与深色模式、多种配色，支持导入字体，包括可变字体。
- **应用锁**：密码保护，支持生物识别解锁。
- **导入、导出与分享**：导出为 Markdown、Word、PDF 或长图，从 Markdown 压缩包或本地备份导入。
- **备份与同步**：WebDAV、S3 / MinIO 与局域网同步，可选端到端加密。
- **天气与地点**：为记录添加天气和常用地点，在地图上查看足迹。
- **心情记录**：手动选择或修改每篇日记的心情。
- **智能助手**：接入 OpenAI 或 Anthropic 兼容的供应商，使用对话和日记工具。

## 下载与使用

本分支发布的安装包见 [selumn Releases](https://github.com/MangataYu/selumn/releases)。当前 CI 构建 **Android ARM64 APK**，测试预发布包会在发布说明中标明。如果没有适合的安装包，可按下方说明从源码运行。

基础日记功能可离线使用，可选的在线服务需要自行配置。Android 应用内的更新检查会查找本仓库中版本更高的正式发行版；测试预发布包请直接从发布页面下载。

## 开发

Flutter 应用位于 `mobile/`，共享包位于 `packages/`。Flutter 版本以 [.fvmrc](.fvmrc) 为准，Rust 版本以各原生包的工具链文件为准，Node / pnpm 要求见[编辑器依赖配置](packages/feature_base/moodiary_editor/editor/package.json)。构建前需安装 Git LFS、FVM 和目标平台的构建工具。

准备好上述环境后，在仓库根目录执行：

```sh
git lfs pull
fvm use
fvm dart tool/task.dart setup
fvm dart tool/task.dart run
```

运行应用前请连接设备或启动模拟器。项目结构与验证命令见 [AGENTS.md](AGENTS.md)，编辑器开发说明见[编辑器 README](packages/feature_base/moodiary_editor/README.md)。

## 致谢与许可证

感谢原作者 [ZhuJHua](https://github.com/ZhuJHua)、原项目 [Moodiary](https://github.com/ZhuJHua/moodiary) 及所有[上游贡献者](https://github.com/ZhuJHua/moodiary/graphs/contributors)。本分支的改动由 [MangataYu](https://github.com/MangataYu) 维护。

本项目继续采用 [GNU Affero General Public License v3.0](LICENSE)，保留已有版权与许可声明。本 README 于 **2026-09-21** 改写为 selumn 的项目说明。

[上游文档](https://docs.moodiary.net) 面向 Moodiary，本分支的界面和操作可能有所不同。如需支持原作者，可前往[原项目](https://github.com/ZhuJHua/moodiary#-sponsor)查看捐助方式。

<details>
<summary>原项目捐助者</summary>

以下名单保留自 Moodiary，感谢这些用户对原项目的支持。

<!-- sponsors:start -->
朱东杰、[dsxksss](https://github.com/dsxksss)、不对味的雪碧、[xiaoxianzi-99](https://github.com/xiaoxianzi-99)、Lucci、[Higanoneko](https://github.com/Higanoneko)、h、大作文
<!-- sponsors:end -->

</details>
