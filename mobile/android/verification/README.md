# Android RS256 验签自测

在仓库根目录执行：

```powershell
& ./mobile/android/verification/verify_rs256.ps1
```

此命令直接编译主应用使用的 `cn.yooss.moodiary.Rs256Verifier` 并运行 8 项纯 JVM 测试，不运行 Flutter、Gradle，不连接网络，不读取账号凭据。测试使用临时生成的 RSA 密钥。

`JAVA_HOME` 需指向 JDK 21。脚本只读查找 `GRADLE_USER_HOME`（默认用户目录下的 `.gradle`）中已缓存的 Kotlin 2.4.0 编译器及依赖；也可用 `KOTLIN_COMPILER_CLASSPATH` 或 `-CompilerClassPath` 指定完整 classpath。输出写入 `mobile/build/rs256-verification/`。缺少依赖时明确失败，不自动下载。

预期输出 `RS256 verification: 8 checks passed`。覆盖有效签名，以及篡改正文、截断签名、非 ASCII 输入、畸形 JWK、零指数、空签名和错误公钥。Android MethodChannel 的实际装配仍由主应用 APK 构建与实机验证覆盖。

凭据使用现有 `FlutterSecureStorage` 默认命名空间。`res/xml/backup_rules.xml` 与 `res/xml/data_extraction_rules.xml` 排除默认凭据、包装密钥和加密配置的 SharedPreferences，不改变日记数据库与文件的备份规则。若将来配置自定义 `storageNamespace`，同时更新两份排除规则。

## 测试环境安装包标识验证

`verify_environment.init.gradle` 读取 Android 插件最终生成的 variants，与固定期望表核对 `applicationId` 和 `app_name` 覆盖值。默认及 production 保持已有正式、Debug、Profile 标识；staging 与 development 使用各自独立后缀。测试只配置项目，不打包、安装或读取应用数据，需要本机已缓存 Gradle 和项目依赖。

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

每种配置应输出 3 行 `Verified`，分别对应 release、debug、profile。`--offline` 不允许解析时下载依赖，但 Gradle Wrapper 自身仍要求已有对应 Gradle 分发缓存。
