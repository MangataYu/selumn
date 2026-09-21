# Selume Android 包名与签名

本分支使用独立的 Android 应用 ID：

| 构建 | applicationId |
| --- | --- |
| Release | `com.aerieyarrowy.selume` |
| Debug | `com.aerieyarrowy.selume.debug` |
| Profile | `com.aerieyarrowy.selume.profile` |

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
- 在 **Build & Release → Run workflow** 中选择 `main`，默认只构建并上传 APK。下载运行结果中的 `android-apk` artifact，即可取得 Selume 安装包。
- 手动勾选 `prerelease`，会在 APK 构建成功并上传附件后公开一个 **Pre-release**，不会设为 Latest。测试标签自动生成为 `v<版本>-selume-test.<运行编号>.<重跑次数>`，指向本次构建的提交；APK 文件名含完整测试标签。每次运行或重跑使用独立标签，不覆盖已有发布。预发布说明包含提交与构建链接，不要求修改 `CHANGELOG.md`。
- `prerelease` 未勾选时，手动勾选 `create_release` 或推送版本标签会进入原有草稿发布流程；创建草稿要求 `CHANGELOG.md` 含对应版本说明，推送的标签必须严格等于 `mobile/pubspec.yaml` 中版本对应的 `v<版本>`。测试版请使用手动 `prerelease`，不要手动推测试标签。
- `prerelease` 优先于 `create_release`，只勾选前者即可发布测试版。这仍是 `com.aerieyarrowy.selume` 的正式签名 APK，可以与 Debug 共存；GitHub 上的预发布标记不会改变应用 ID 或签名。
- 现有 `tool/release.dart` 和合并发布流程仍面向 `develop`。个人分支日常打包使用手动工作流，无需执行发布脚本。

上述工作流和代码改动提交并推送到 GitHub 后才会在线生效。文档不代表仓库 Secrets 已配置，也不代表已执行在线构建。
