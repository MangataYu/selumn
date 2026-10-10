# 可选账号服务与发布包测试

本文中的命令以仓库根目录为起点。

## 本地使用边界

官方账号是可选增值服务的入口。启动、写日记、读取附件、导入导出、备份以及现有 WebDAV / S3 / 局域网功能不要求注册或登录。未配置官方服务、断网、会话失效或退出账号都不改变这些功能。

当前接入范围为邮箱注册、验证、登录、续期、账号状态、退出和密码找回。登录不会上传、迁移、归属或删除本地日记，不会修改现有同步提供方、自动同步开关、同步密钥或应用锁。退出只移除当前服务的账号会话；离线时会明确提示无法确认服务端会话撤销。账号与密码不会进入普通 KV 或日志，密码不持久化。

官方云同步、容量权益、订阅收费尚未接入。后端对象、配额、版本和租约接口完成后，再开发官方同步适配器；届时需单独处理首次上传确认、游客数据归属、不同账号的云数据隔离及加密恢复。当前不能把“登录成功”视为“日记已备份”。

## 服务地址

使用构建期参数配置，普通用户不需要填写服务器地址：

| 参数 | 默认值 | 规则 |
| --- | --- | --- |
| `SELUMN_API_URL` | 空 | 空值关闭账号操作；配置为服务器 origin，例如 `https://api.example.com`，不带 `/v1`、路径前缀、查询或凭据 |
| `SELUMN_ENVIRONMENT` | `production` | 只接受 `production`、`staging`、`development` |

`production` 和 `staging` 要求 HTTPS。`development` 额外允许回环和局域网 HTTP，供本地开发使用。无效配置只关闭账号操作，不阻断本地启动。账号凭据按环境和规范化服务地址隔离。

修改参数必须重新构建。环境标签本身不会创建独立后端；测试 URL 应指向独立测试数据库、邮件配置和存储，不能把正式地址当作测试地址。

App 使用 `/v1/auth/register`、`resend-verification`、`verify-email`、`login`、`refresh`、`logout`、`forgot-password`、`reset-password` 与 `GET /v1/me`。访问及续期令牌为不透明字符串。客户端串行处理会话变更，刷新后把新令牌对保存为一个安全存储值。验证邮箱需要邮件令牌及原注册密码；当前提供手动粘贴令牌流程。

## 使用 Release 构建测试

Release 指编译模式，不必等同于正式服务。可以构建带 Release 优化的独立测试应用，同时保留日常使用的正式应用和数据。

### Android

在仓库根目录执行，示例地址需要替换为实际测试服务：

```powershell
Set-Location mobile
fvm flutter build apk --release --dart-define=SELUMN_ENVIRONMENT=staging --dart-define=SELUMN_API_URL=https://staging-api.example.com
```

需要先按 `mobile/android/SIGNING.md` 配置已有签名。此命令只构建，不安装或发布。

| 环境 | Release 应用 ID | 数据 |
| --- | --- | --- |
| 默认 / `production` | `com.aerieyarrowy.selume` | 保留现有正式应用的数据路径 |
| `staging` | `com.aerieyarrowy.selume.staging` | 独立测试数据 |
| `development` | `com.aerieyarrowy.selume.development` | 独立开发数据 |

Debug / Profile 继续追加已有 `.debug` / `.profile` 后缀。GitHub 的 `prerelease` 标签本身不会切换环境或隔离数据；必须给构建传入对应参数。

### Windows

在仓库根目录执行：

```powershell
Set-Location desktop
fvm flutter build windows --release --dart-define=SELUMN_ENVIRONMENT=staging --dart-define=SELUMN_API_URL=https://staging-api.example.com
```

将整个输出目录保存到单独的测试程序目录再运行，避免覆盖日常程序文件。Windows 使用产品资源名称确定应用数据目录：正式构建保持 `MangataYu/Selume`；测试和开发构建分别使用 `MangataYu/Selume Staging`、`MangataYu/Selume Development`，同时隔离数据库、附件、普通配置和安全凭据。仅复制同一个正式 EXE 到别处不会隔离数据。

### iOS

账号界面与协议共用，但当前未添加独立 iOS 测试签名和 Bundle ID 配置。仅传 Dart 参数不能隔离 iOS 的本地数据。并存测试包需要后续在 macOS/Xcode 中配置独立 Bundle ID、显示名称和签名；不要将当前构建当作独立数据沙盒。

## 验证顺序

1. 新测试包首次打开应使用独立数据，可先写一篇测试日记并添加图片。空白测试库是正常隔离结果，不会自动搬入正式库。
2. 不登录即可编辑、重启后读取、导出与备份。打开设置仍能访问原有同步入口。
3. 在测试服务完成注册、收信、验证、登录；检查原测试日记和附件保持原样。
4. 验证退出、断网、登录过期、找回密码和重新登录：本地日记、附件及既有同步设置均保留。
5. 两台设备登录只验证账号会话；官方云同步未接入时，不应预期日记传输。
6. 正式环境验收仍使用正式签名与版本升级流程；先保存应用外备份，用专门测试账号和测试设备验证，再扩大内测范围。

本说明中的构建命令不代表已经完成签名构建、安装、真机联调或上线。
