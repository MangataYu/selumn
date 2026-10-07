param(
    [string]$CompilerClassPath = $env:KOTLIN_COMPILER_CLASSPATH
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    throw 'Set JAVA_HOME to a JDK 21 installation.'
}
$probeJava = Join-Path $env:JAVA_HOME 'bin/java.exe'
if (-not (Test-Path -LiteralPath $probeJava)) {
    throw 'JAVA_HOME does not contain bin/java.exe.'
}

if ([string]::IsNullOrWhiteSpace($CompilerClassPath)) {
    $probeGradleHome = $env:GRADLE_USER_HOME
    if ([string]::IsNullOrWhiteSpace($probeGradleHome)) {
        $probeGradleHome = Join-Path $env:USERPROFILE '.gradle'
    }
    $probeCache = Join-Path $probeGradleHome 'caches/modules-2/files-2.1'
    # Versions match Kotlin 2.4.0's compiler POM and the app's Gradle settings.
    $probeArtifacts = @(
        'org.jetbrains.kotlin/kotlin-compiler-embeddable/2.4.0',
        'org.jetbrains.kotlin/kotlin-build-tools-api/2.4.0',
        'org.jetbrains.kotlin/kotlin-stdlib/2.4.0',
        'org.jetbrains.kotlin/kotlin-script-runtime/2.4.0',
        'org.jetbrains.kotlin/kotlin-reflect/1.6.10',
        'org.jetbrains.kotlin/kotlin-daemon-embeddable/2.4.0',
        'org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.8.0',
        'org.jetbrains/annotations'
    )
    $probeJars = foreach ($probeArtifact in $probeArtifacts) {
        $probeArtifactPath = Join-Path $probeCache $probeArtifact
        if (-not (Test-Path -LiteralPath $probeArtifactPath)) {
            throw "Missing cached compiler dependency: $probeArtifact. Set KOTLIN_COMPILER_CLASSPATH to a complete compiler classpath."
        }
        $probeMatches = @(Get-ChildItem -LiteralPath $probeArtifactPath -Recurse -Filter '*.jar')
        if ($probeMatches.Count -eq 0) {
            throw "No cached JAR found for $probeArtifact."
        }
        $probeMatches.FullName
    }
    $CompilerClassPath = $probeJars -join [IO.Path]::PathSeparator
}

$probeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$probeOutput = Join-Path $probeRoot 'build/rs256-verification'
$probeSource = Join-Path $probeRoot 'android/app/src/main/kotlin/cn/yooss/moodiary/Rs256Verifier.kt'
$probeTest = Join-Path $PSScriptRoot 'Rs256VerifierSelfTest.kt'
New-Item -ItemType Directory -Force -Path $probeOutput | Out-Null

& $probeJava -cp $CompilerClassPath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler `
    -no-stdlib -no-reflect -classpath $CompilerClassPath -jvm-target 21 `
    -d $probeOutput $probeSource $probeTest
if ($LASTEXITCODE -ne 0) {
    throw "RS256 self-test compilation failed with exit code $LASTEXITCODE."
}

$probeRuntimeClassPath = $probeOutput + [IO.Path]::PathSeparator + $CompilerClassPath
& $probeJava -cp $probeRuntimeClassPath cn.yooss.moodiary.Rs256VerifierSelfTestKt
if ($LASTEXITCODE -ne 0) {
    throw "RS256 self-test failed with exit code $LASTEXITCODE."
}
