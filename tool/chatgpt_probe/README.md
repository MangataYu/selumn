# Android ChatGPT 订阅验证包

用于真机验证 Sign in with ChatGPT 的最小 Flutter 应用。与主应用使用相同 Flutter SDK、mui 主题、slang 文案、url_launcher 和 flutter_secure_storage；没有日记数据库、文件访问或普通 API Key 接入。

授权、回调恢复、凭据刷新和测试响应解析由 `packages/core/moodiary_chatgpt` 共享。此工具只保留独立安全存储记录与验签通道适配；主日记 App 使用自己的注册记录，安装主 App 后需要另外登录。

- 独立应用 ID：`com.aerieyarrowy.selume.chatgptprobe`。
- Android 9（API 28）及以上；可打包 ARM32 + ARM64。
- 仅申请网络权限。凭据存入 Android 安全存储，关闭备份和设备迁移。
- release 包使用本机 debug 签名，供个人验证安装，不用于应用商店发布。

## 真机验证

1. 安装 APK，打开「Selume 订阅验证」。
2. 点击 `Continue with ChatGPT`，在官方系统浏览器页面完成登录和计划使用授权。
3. 浏览器收到回调后，手动返回测试应用。检查「手机收到授权回调」「账号身份校验通过」「已授予订阅使用权限」。浏览器成功页本身不代表身份验证通过。
4. 获取账号可用模型，主动选择一个模型，再点击「发送测试消息」。只发送固定的 `Reply with exactly OK.`，每次测试可能使用计划额度或可用积分。
5. 只有收到 `response.completed` 且状态为 completed 才会通过；模型列表、HTTP 200 和部分回复均不作为推理成功的证据。
6. 在 ChatGPT 设置 → Usage 核对应用授权、额度及用量。一次短请求不一定使百分比明显变化。
7. 关闭重开应用，再获取模型并测试，验证安全存储恢复。另用「刷新登录凭据并测试」验证真实 refresh grant；重启成功不等于刷新通过。刷新时机受服务端策略约束。
8. 失败时复制页面的诊断信息，其中只包含阶段、失败步骤、耗时、固定错误码、HTTP 状态、响应头／正文类型分类、收到的字节数及 request ID，不含账号、日记、提示词和凭据。

### 测试结果与响应类型

0.1.4 修正了仅因缺少 `Content-Type` 就拒绝读取正文的问题：当 HTTP 200 未声明类型时，同一个响应直接进入现有 SSE 校验，仍需 `response.completed` 且状态为 completed 才会通过。已明确声明为 HTML、JSON 等不兼容类型的响应继续失败，不自动重发。

诊断保留 `response_format=missing`，另外提供 `body_format` 和 `received_bytes`。正文分类只观察最多 1024 字节的开头，不记录内容；明确的 HTML／JSON 开头会拒绝，实际收到 0 字节并结束时报告 `empty_response_body`。流中断或超时保留 HTTP 状态和 request ID。未读取正文时不输出这两项，避免把“未读取”误报成“空响应”。

0.1.3 在发送按钮旁显示等待、成功或失败，并在结束时弹出提示。部分回复单独标注，出现 `OK` 本身不代表成功。新测试会先清除旧回复与完成标记，刷新凭据失败也不会残留上次的成功结果。

0.1.2 的 `phase=failed / failed_phase=testing / code=invalid_response / http=200` 表示响应头不是预期的 `text/event-stream`，尚未进入回复流解析；不能仅据此归因于代理或断定模型已回复。0.1.3 将网页、JSON 和其他类型分别报告，并在诊断中加入 `response_format` 固定分类。JSON 仅提取白名单中的结构化错误码，不把 JSON 或网页正文当作回复，也不自动重发消耗额度。

保持手机可联网的代理设置。缺失响应头本身不能证明代理或服务端故障，也不能证明正文是有效的流式回复；实际响应仍需真机验证。

### 浏览器打不开本机返回地址

0.1.2 提供「粘贴授权结果」备用入口。保持手机原来可以联网的代理设置，无需为使用此入口关闭系统代理。

1. 升级后重新点击 `Continue with ChatGPT` 开始一次登录，在浏览器完成授权。
2. 浏览器跳到 `http://127.0.0.1:端口/auth/callback?...` 后，即使显示无法访问，也可以复制地址栏的**完整地址**。OpenAI 登录/授权页面的地址不能用于此入口。
3. 返回应用，点击「粘贴授权结果」，在输入框粘贴并继续验证。链接含一次性授权信息，仅粘贴到此应用，不要发送到聊天、日志或第三方网站。

应用不会自动读取剪贴板，也不会请求粘贴的地址。它校验原始地址、端口、state 和客户端身份，再使用本次 PKCE verifier 兑换授权码并校验 ID token。手动提交与自动回调共享一次性处理流程。

待完成授权所需的信息保存在现有 Android 安全存储中，可在应用重启后恢复；有效期仍为本次登录开始后的 15 分钟，不因重启延长。取消、过期、开始新登录或处理有效结果后清理。授权结果地址及其中的 code 不写入持久化存储或诊断。过期或服务端已使授权码失效时必须重新登录。

此入口绕过浏览器访问本机监听端口的问题，不能解决 OpenAI 网页或接口本身无法连接的问题；真实账号仍需手机实测。

### 授权等待超时

0.1.1 将浏览器授权等待上限由 5 分钟调整为 15 分钟，并把验证进度放在模型测试操作之前。超过等待时间后会关闭本次回调端口；浏览器之后才返回旧的 `127.0.0.1` 地址，会提示无法访问。请关闭旧的授权页面，在应用重新点击 `Continue with ChatGPT`，不要刷新旧回调页。

`authorization_timeout` 表示未及时收到浏览器回调，`browser_launch_timeout` 表示启动浏览器超时。其他网络超时会附带 `failed_phase` 区分凭据交换、身份校验或模型加载；`elapsed_seconds` 是本次操作的总耗时。这些诊断不会记录授权链接或凭据。

这项调整解决原先 5 分钟上限不足以及超时提示不明确的问题，不保证 Android 后台进程不会被系统回收。若在 15 分钟内仍出现本地连接拒绝，请提供应用复制的诊断信息，不要发送完整授权链接。

手机必须能连接 OpenAI 的授权和 API 服务。开源应用通道、账号资格、可用模型和额度均由服务端决定。本地 mock 测试和 APK 构建不能证明你的账号已可用。

## 开发与构建

在仓库根目录执行依赖解析；其他命令进入此目录：

```powershell
fvm flutter pub get --offline
Set-Location tool/chatgpt_probe
fvm dart run slang
fvm flutter analyze --no-pub
fvm flutter test --no-pub
fvm flutter build apk --release --no-pub --target-platform android-arm,android-arm64
```

APK 位于 `build/app/outputs/flutter-apk/app-release.apk`。本工具是 workspace 成员，根目录 `pubspec.lock` 管理版本。未引入新的第三方依赖版本。构建需要本机 Flutter、Pub、Gradle 和 Android SDK 缓存可写。

手机窄屏和大字号布局由 `test/page_test.dart` 验证。Android RSA 验签的纯 JVM 自测及运行说明位于 `android/verification/`。

## 协议边界

- 仅监听 `127.0.0.1`，随机端口，固定 `/auth/callback`；使用 PKCE S256、state、nonce。
- 使用官方动态客户端注册，持久化服务端返回的 issued client ID 和本机 host ID。
- 校验 ID token 的 RS256 签名、官方 issuer、audience、时效与 nonce。JWK 只从官方发现文档指定的受限域名获取。
- 使用实际返回的 `chatgpt.tokens.use.direct` scope 决定是否可推理。
- 所有携带凭据的 HTTP 请求禁止自动重定向。错误展示和复制结果采用固定安全代码，不显示原始响应正文。
- 凭据轮换串行执行，保存最新 access/refresh token；刷新时保留首次已校验的身份记录，不依赖刷新 ID token 的可选 nonce。
- 注销尝试撤销远端 refresh 会话，再清本机凭据；远端撤销未确认会明确提示。保留注册标识以便再次登录。

官方资料：

- [注册与登录](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [模型与推理](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [账号与会话](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Token 字段](https://developers.openai.com/siwc/token-sharing-open-source/token-reference)
