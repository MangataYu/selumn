# Selume Android 包名与签名

本分支使用独立的 Android 应用 ID：

| 构建（默认 production 环境） | applicationId | 签名 |
| --- | --- | --- |
| Production Release | `com.aerieyarrowy.selume` | 正式签名，缺少材料时构建失败 |
| Production Debug | `com.aerieyarrowy.selume.debug` | Debug 签名 |
| Production Profile | `com.aerieyarrowy.selume.profile` | Debug 签名 |
| Alpha Release | `com.aerieyarrowy.selume.alpha` | 正式材料完整时用正式签名，否则用 Debug 签名 |
| Alpha Debug | `com.aerieyarrowy.selume.alpha.debug` | Debug 签名 |
| Alpha Profile | `com.aerieyarrowy.selume.alpha.profile` | Debug 签名 |

`--flavor` 选择发行渠道，`SELUMN_ENVIRONMENT` 选择账号服务环境，两者独立。staging / development 在渠道后追加环境后缀，例如 `--flavor alpha --dart-define=SELUMN_ENVIRONMENT=staging` 的 release 包名是 `com.aerieyarrowy.selume.alpha.staging`，显示名为 `Selume Staging Alpha`；debug / profile 再追加对应后缀。只选择 Alpha 不会自动切换 API 地址，测试服务仍需显式设置 `SELUMN_ENVIRONMENT` 和 `SELUMN_API_URL`。

Alpha 与正式版独立安装和存储，不会覆盖正式版。相同包名的后续安装必须保持签名一致；同一个 Alpha 包从 Debug 签名改为正式签名后不能直接覆盖旧安装，因此长期使用 Alpha 时也应固定签名。签名回退不改变 release 优化配置，也不允许安装低于已安装 `versionCode` 的版本。文件存在且两个密码非空才算材料完整；密钥损坏、密码错误或缺少 `key0` 不会自动重试 Debug 签名。

代码命名空间仍为 `cn.yooss.moodiary`，便于继续合并上游代码。应用 ID 与代码命名空间可以不同。深链接 host 使用各构建实际的应用 ID。

旧 `cn.yooss.moodiary.debug` 与新 Debug 是独立应用。迁移时，在旧版的「我的 → 导入与导出 → 导出备份」中把 ZIP 保存到应用外，再在新版选择「从备份恢复」。确认日记和附件完整后再处理旧应用。

## 在本机生成签名

在仓库根目录打开 PowerShell，使用 JDK 自带的 `keytool`：

```powershell
keytool -genkeypair -v -keystore .\mobile\android\app\key.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias key0
```

根据终端提示输入密码和证书信息。已存在自己的正式密钥时应继续使用它，不要重新生成。密钥别名需要为 `key0`，与当前 Gradle 配置一致。

在 `mobile/android/local.properties` 中追加以下两项，保留已有的 SDK 路径等配置：

```properties
storePassword=你的密钥库密码
keyPassword=你的密钥密码
```

如果两个密码相同，两项填写相同内容。该文件遵循 Java Properties 转义规则，例如密码中的反斜杠需写为 `\\`。Gradle 也支持 `ANDROID_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD` 环境变量，环境变量优先于本地配置；CI 使用此方式，密码不会被写入脚本源码。

`key.jks` 和 `local.properties` 已被 Git 忽略。将密钥文件另行备份，密码保存在密码管理器中；后续正式版更新继续使用同一签名。

配置完成后，在仓库根目录执行：

```powershell
fvm dart tool/task.dart build-apk
```

该入口默认使用 `--flavor production`，产物为 `mobile/build/app/outputs/flutter-apk/app-production-release.apk`。本地 Alpha 构建与运行：

```powershell
fvm dart tool/task.dart build-apk -- --flavor alpha --release
fvm dart tool/task.dart run -- --flavor alpha
```

Alpha release 产物为 `mobile/build/app/outputs/flutter-apk/app-alpha-release.apk`，应用内显示 `ALPHA` 角标。直接使用 `flutter run` / `flutter build apk` 时也要显式传入所需的 `--flavor`；正式调试使用 `fvm dart tool/task.dart run -- --flavor production`。独立环境与签名校验见 [验证说明](verification/README.md)。

## GitHub Actions

Secrets 属于 GitHub 仓库，不属于 Git 分支，也不会从上游仓库自动复制。打开自己的仓库，进入 **Settings → Secrets and variables → Actions → New repository secret**，设置：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KJS` | `key.jks` 的 Base64 内容；名称沿用现有工作流的拼写 |
| `ANDROID_STORE_PASSWORD` | 密钥库密码 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

需要在网页填写 `ANDROID_KJS` 时，可在本机 PowerShell 中将内容复制到剪贴板：

```powershell
$keystorePath = (Resolve-Path .\mobile\android\app\key.jks).Path
Set-Clipboard -Value ([Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath)))
```

将剪贴板内容粘贴到该 Secret 的值中。Base64 仍是密钥数据，不要提交到仓库或粘贴到日志、讨论中。两个密码直接在 GitHub 的 Secret 输入框中填写。

本分支的 CI 行为：

- 推送到 `main`，或提交目标为 `develop` / `main` 的 PR，会运行 **Quality & Tests**；该流程不需要正式签名。
- 在 **Build & Release → Run workflow** 中选择 `main`，默认只构建并上传 **production release** APK。工作流必须提供全部签名 Secrets，缺失即失败，不回退 Debug 签名，也不自动生成 Alpha 包。下载运行结果中的 `android-apk` artifact，其中的文件名为 `app-production-release.apk`。
- 手动勾选 `prerelease`，会在 APK 构建成功并上传附件后公开一个 **Pre-release**，不会设为 Latest。测试标签自动生成为 `v<版本>-selume-test.<运行编号>.<重跑次数>`，指向本次构建的提交；APK 文件名含完整测试标签。每次运行或重跑使用独立标签，不覆盖已有发布。预发布说明包含提交与构建链接，不要求修改 `CHANGELOG.md`。
- 手动勾选 `publish_release`，会先构建 ARM64 APK，核对包名、版本和上一版正式签名证书，再创建草稿并核对目标提交和附件，最后公开为 Latest。该路径要求版本标签不存在，不覆盖已有发布；发布说明来自 `CHANGELOG.md` 对应版本段。更换正式签名时，需有意更新该校验并处理已有用户的升级兼容性。`prerelease` 同时勾选时仍优先生成测试预发布。
- `prerelease` 未勾选时，手动勾选 `create_release` 或推送版本标签会进入原有草稿发布流程；创建草稿要求 `CHANGELOG.md` 含对应版本说明，推送的标签必须严格等于 `mobile/pubspec.yaml` 中版本对应的 `v<版本>`。测试版请使用手动 `prerelease`，不要手动推测试标签。
- `prerelease` 优先于 `create_release`，只勾选前者即可发布测试版。这仍是 `com.aerieyarrowy.selume` 的正式签名 APK，可以与 Debug 共存；GitHub 上的预发布标记不会改变应用 ID 或签名。
- 现有 `tool/release.dart` 和合并发布流程仍面向 `develop`。个人分支日常打包使用手动工作流，无需执行发布脚本。

上述工作流和代码改动提交并推送到 GitHub 后才会在线生效。文档不代表仓库 Secrets 已配置，也不代表已执行在线构建。
