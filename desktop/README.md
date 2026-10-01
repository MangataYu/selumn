# Selume Windows 桌面版

`desktop/` 是独立的 Flutter 应用入口（`moodiary_desktop`），复用 `packages/` 中的日记、编辑器、SQLite 数据和同步功能。电脑与手机各自保存本地数据，通过已有的 WebDAV / S3 同步协议交换日记，不需要为桌面版另建业务服务器。

## 开发运行

在仓库根目录执行：

```powershell
fvm dart tool/task.dart setup
fvm dart tool/task.dart run-desktop
```

`run-desktop` 在 `desktop/` 执行 `flutter run -d windows`。原有的 `run`、`build-apk`、`build-ios`、`test-mobile` 继续针对手机应用。

开发环境需要仓库 `.fvmrc` 指定的 Flutter、Windows C++ 编译工具链（含 MSVC v143 x64 / x86 ATL 组件）、Rust / Cargo，以及用于构建 Vue / TipTap 编辑器的 Node.js / Corepack。运行编辑器需要 Microsoft Edge WebView2 Runtime。仓库自带的 Rust 库和编辑器资源由构建钩子生成，不直接修改其构建产物，也不为桌面版另外升级依赖。

Flutter 的 Windows 插件需要创建符号链接，开发机应启用 Windows 开发者模式或具备相应权限。构建会自动下载并校验所需的 NuGet 客户端，使用项目内的 `NuGet.Config` 下载原生插件依赖。

```powershell
# 桌面测试，可在 -- 后指定测试文件或 Flutter 测试参数
fvm dart tool/task.dart test-desktop

# 工作区静态分析与依赖分层检查
fvm dart tool/task.dart analyze

# Windows 发布构建
fvm dart tool/task.dart build-windows -- --release
```

Windows 构建产物位于 `desktop/build/windows/x64/runner/Release/`。分发时需要整个输出目录，不能只复制其中的 `.exe`。构建钩子支持本机 Windows 目标，首次构建或测试可能编译 Rust 库与编辑器资源，需要可用的 C++ / Rust / Node 工具链及依赖下载。

本次已生成并启动 Debug 版本，路径为 `desktop/build/windows/x64/runner/Debug/selume.exe`。本机缺少 ATL 安装组件，验证时使用与已装 MSVC 匹配、经过 SHA256 校验的微软官方 ATL 文件，缓存于 Git 忽略的 `.dart_tool/atl/`；这些文件没有写入系统 SDK。后续干净构建建议通过 Visual Studio Installer 添加 `Microsoft.VisualStudio.Component.VC.ATL`。若沿用此缓存，可在当前 PowerShell 会话中设置以下参数再运行构建命令：

```powershell
$env:CL += ' /I"' + (Join-Path $PWD '.dart_tool/atl/include') + '"'
$env:LINK += ' /LIBPATH:"' + (Join-Path $PWD '.dart_tool/atl/lib/x64') + '"'
```

## 与手机同步

电脑和手机的本地数据库相互独立。电脑离线输入时，日记先保存在本机；联网后再通过同步入口上传，手机运行同步后下载到自己的数据库。

1. 在手机和桌面端的同步设置中选择相同的后端。
2. WebDAV 填写相同的服务器地址和账号；S3 / MinIO 填写相同的端点、区域及存储桶，并配置各自可访问该存储的凭据。
3. 已有云端加密数据时，桌面端按提示输入原有同步密码，以解开云端的同步密钥。
4. 先在已有数据的设备同步，再在另一端同步。可在同步控制台查看状态和失败原因。

开启自动同步后，应用使用已有的前台变更监听和远程检查机制。应用退出后不会继续同步，手机后台同步也受到系统限制。两端不必使用同一 Wi-Fi，也不必同时在线，但都必须能访问选定的云存储。

不使用云存储时，可以在同一局域网内使用发送 / 接收入口：接收端保持页面开启，发送端选择设备或输入地址，再输入接收端显示的 6 位配对码。局域网传输是手动操作；网络或 Windows 防火墙阻止互通时，页面会报告失败。

## 第一版范围

- 宽窗口使用侧栏、日记列表和内容区域，窄窗口切换为单页导航。
- 复用日记新增、查看、编辑和保存，以及标签筛选与同步页面。
- 提供 `Ctrl+N` 新建、`Ctrl+F` 搜索入口，沿用共享的主题和语言设置。
- 手机相册和相机等移动端专属能力不直接搬到 Windows；桌面媒体选择通过系统文件对话框处理。
- 桌面图片选择暂不包含 HEIF / HEIC，支持 JPEG、PNG、GIF、WebP 和 BMP。

Windows Debug 构建、实际首页启动和空白日记的 WebView2 编辑器加载已验证，编辑器 JavaScript 握手及激活均成功。桌面测试 23 条、共享编辑器测试 32 条、日记测试 193 条全部通过；图片库的 Windows JPEG 定向测试及 clippy 也通过。

WebView2 下的中文输入、原生编辑器获得焦点时的快捷键、媒体操作，以及电脑和真实手机间的同步尚未联测，需要实际设备和同步后端验证。当前没有生成安装包或进行 Release 验证。
