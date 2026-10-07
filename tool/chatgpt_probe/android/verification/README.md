# RS256 原生验签自测

此测试直接编译应用使用的 `Rs256Verifier.kt`，在 JVM 中生成临时 RSA 密钥和测试签名；不访问 Android、网络、ChatGPT 账号或凭据，不执行 Flutter / Gradle，也不下载依赖。

在仓库根目录用 PowerShell 运行：

```powershell
& ./tool/chatgpt_probe/android/verification/verify_rs256.ps1
```

要求 `JAVA_HOME` 指向 JDK 21。脚本只读使用 `GRADLE_USER_HOME`（默认用户目录下的 `.gradle`）中已缓存的 Kotlin 2.4.0 编译器及其依赖。编译输出仅写入本工具已忽略的 `build/rs256-verification/`。

若使用其他编译器存放位置，可通过 `KOTLIN_COMPILER_CLASSPATH` 环境变量，或 `-CompilerClassPath` 参数传入完整的 Kotlin 2.4.0 编译器 classpath。Windows 路径以分号分隔；必须包含 compiler-embeddable、build-tools-api、stdlib、script-runtime、reflect、daemon-embeddable、coroutines-core-jvm 和 annotations JAR。缺少缓存时脚本明确失败，不自动安装。

预期输出：

```text
RS256 verification: 8 checks passed
```

覆盖有效签名，以及篡改正文、截断签名、非 ASCII 输入、畸形 JWK、零指数、空签名、错误公钥。该测试已通过；它验证 JVM 验签逻辑，不代表 Android 登录回调或订阅推理已在真机通过。
