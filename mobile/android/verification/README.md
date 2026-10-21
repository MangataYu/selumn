# Android RS256 验签自测

在仓库根目录执行：

```powershell
& ./mobile/android/verification/verify_rs256.ps1
```

此命令直接编译主应用使用的 `cn.yooss.moodiary.Rs256Verifier` 并运行 8 项纯 JVM 测试，不运行 Flutter、Gradle，不连接网络，不读取账号凭据。测试使用临时生成的 RSA 密钥。

`JAVA_HOME` 需指向 JDK 21。脚本只读查找 `GRADLE_USER_HOME`（默认用户目录下的 `.gradle`）中已缓存的 Kotlin 2.4.0 编译器及依赖；也可用 `KOTLIN_COMPILER_CLASSPATH` 或 `-CompilerClassPath` 指定完整 classpath。输出写入 `mobile/build/rs256-verification/`。缺少依赖时明确失败，不自动下载。

预期输出 `RS256 verification: 8 checks passed`。覆盖有效签名，以及篡改正文、截断签名、非 ASCII 输入、畸形 JWK、零指数、空签名和错误公钥。Android MethodChannel 的实际装配仍由主应用 APK 构建与实机验证覆盖。

凭据使用现有 `FlutterSecureStorage` 默认命名空间。`res/xml/backup_rules.xml` 与 `res/xml/data_extraction_rules.xml` 排除默认凭据、包装密钥和加密配置的 SharedPreferences，不改变日记数据库与文件的备份规则。若将来配置自定义 `storageNamespace`，同时更新两份排除规则。

## 构建渠道、环境与签名验证

`verify_environment.init.gradle` 读取 Android 插件最终生成的 6 个 variants（production / alpha × release / debug / profile），与固定期望表核对 `applicationId`、`app_name` 和最终签名配置。默认及 production 环境保持已有正式、Debug、Profile 标识；Alpha 增加 `.alpha`，staging / development 环境后缀随后拼接，例如 `com.aerieyarrowy.selume.alpha.staging.debug`。

在仓库根目录运行隔离矩阵：

```powershell
& ./mobile/android/verification/verify_environment.ps1
```

脚本需要 PowerShell 7、JDK 21、已缓存的 Gradle / Android 依赖、`.fvm/flutter_sdk` 和 Android SDK。SDK 默认按 `ANDROID_HOME`、`ANDROID_SDK_ROOT`、Windows 用户目录下的 `Android/Sdk` 顺序查找，也可传入 `-FlutterSdk` / `-AndroidSdk`。先按项目说明安装 Flutter 依赖，保证插件配置已经生成。

脚本将非秘密构建文件复制到 `mobile/build/android-environment-verification/<随机目录>/`，仅把 fixture 的 Flutter 源码位置指回实际 `mobile/`；使用临时生成的测试密钥，既不复制也不改动正式 `key.jks` / `local.properties`。它验证：

- 缺少密钥文件、缺少密钥库密码、缺少密钥密码时，production release 仍选择正式配置且构建前检查明确失败，alpha release 回退 debug 配置并通过签名校验。
- 正式材料完整时，production / alpha release 选择正式配置；debug / profile 始终选择 debug 配置。
- 本地 Properties 密码可用，环境变量密码优先于本地配置。
- default、production、staging、development 四种环境的全部 6 个 variant 名称、包名和应用名。

测试不打包、不安装、不读取日记或账号凭据；`validateSigning` 检查配置完整性，并不替代实际 APK 签名与安装升级验证。矩阵在清除了签名环境变量的子进程中运行，不读取或保存调用方的密码值，也不改变调用方环境；fixture 会保留以便排查。缺少离线缓存会明确失败。

只检查当前项目配置时，也可直接运行下列命令；这会让 Gradle 使用本机的签名配置，但不会输出密码或读取密钥内容：

在仓库根目录用 PowerShell 验证四种配置：

```powershell
Push-Location ./mobile/android
try {
    foreach ($testEnvironment in @('default', 'production', 'staging', 'development')) {
        $taskGradleArgs = @(':app:verifySelumnEnvironment', '--offline', '--console=plain',
            '--init-script', 'verification/verify_environment.init.gradle',
            "-PselumnVerificationEnvironment=$testEnvironment")
        if ($testEnvironment -ne 'default') {
            $encodedDefine = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes("SELUMN_ENVIRONMENT=$testEnvironment"))
            $taskGradleArgs += "-Pdart-defines=$encodedDefine"
        }
        & ./gradlew.bat @taskGradleArgs
        if ($LASTEXITCODE -ne 0) { throw "环境标识验证失败：$testEnvironment" }
    }
} finally {
    Pop-Location
}
```

每种配置应输出 6 行 `Verified`，包含最终包名和签名配置名称。`--offline` 不允许解析时下载依赖，但 Gradle Wrapper 自身仍要求已有对应 Gradle 分发缓存。
