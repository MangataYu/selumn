#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$FlutterSdk,
    [string]$AndroidSdk,
    [switch]$IsolatedProcess
)

$ErrorActionPreference = 'Stop'
$signingVariables = @('ANDROID_STORE_PASSWORD', 'ANDROID_KEY_PASSWORD',
    'SELUME_VERIFY_STORE_PASSWORD', 'SELUME_VERIFY_KEY_PASSWORD')
if (-not $IsolatedProcess) {
    # Do not read or save the caller's signing passwords; sanitize only the child.
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', $PSCommandPath, '-IsolatedProcess')) {
        $startInfo.ArgumentList.Add($argument)
    }
    foreach ($name in @('FlutterSdk', 'AndroidSdk')) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $startInfo.ArgumentList.Add('-' + $name)
            $startInfo.ArgumentList.Add($PSBoundParameters[$name])
        }
    }
    foreach ($name in $signingVariables) { [void]$startInfo.Environment.Remove($name) }
    $child = [Diagnostics.Process]::Start($startInfo)
    $childOutput = $child.StandardOutput.ReadToEndAsync()
    $childError = $child.StandardError.ReadToEndAsync()
    $child.WaitForExit()
    $childExitCode = $child.ExitCode
    Write-Host $childOutput.GetAwaiter().GetResult()
    Write-Host $childError.GetAwaiter().GetResult()
    $child.Dispose()
    if ($childExitCode -ne 0) { throw "Isolated Android verification failed with exit code $childExitCode." }
    return
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$mobileRoot = Join-Path $repositoryRoot 'mobile'
$androidRoot = Join-Path $mobileRoot 'android'
if (-not $FlutterSdk) { $FlutterSdk = Join-Path $repositoryRoot '.fvm/flutter_sdk' }
if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_HOME }
if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $AndroidSdk) { $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$FlutterSdk = (Resolve-Path $FlutterSdk).Path
$AndroidSdk = (Resolve-Path $AndroidSdk).Path
if (-not $env:JAVA_HOME) { throw 'JAVA_HOME must point to JDK 21.' }
$keytool = Join-Path $env:JAVA_HOME 'bin/keytool.exe'
if (-not (Test-Path -LiteralPath $keytool -PathType Leaf)) { throw 'JDK keytool was not found.' }

$fixtureRoot = Join-Path $mobileRoot ('build/android-environment-verification/' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$testPassword = 'selume-fixture-only'
function Set-VerificationEnvironment {
    param([string]$Name, $Value)
    if ($null -eq $Value) {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    } else {
        [Environment]::SetEnvironmentVariable($Name, [string]$Value, 'Process')
    }
}
foreach ($name in $signingVariables) {
    Set-VerificationEnvironment -Name $name -Value $null
}

function Invoke-VerificationGradle {
    param([string]$ProjectDirectory, [string[]]$TaskArguments, [bool]$ExpectFailure = $false)
    $arguments = @('--project-dir', $ProjectDirectory, '--offline', '--console=plain',
        '--max-workers=2', '--init-script', (Join-Path $PSScriptRoot 'verify_environment.init.gradle'))
    $previousErrorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & (Join-Path $androidRoot 'gradlew.bat') @arguments @TaskArguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorPreference
    }
    $output | ForEach-Object { Write-Host $_ }
    if ($ExpectFailure) {
        if ($exitCode -eq 0) { throw 'Production signing validation unexpectedly succeeded.' }
        if (($output -join "`n") -notmatch '(?s)(preProductionReleaseBuild|verifyProductionReleaseSigning).*Production release signing') {
            throw 'Gradle failed before the expected production signing validation.'
        }
        Write-Host 'Verified production release rejects incomplete signing.'
    } elseif ($exitCode -ne 0) {
        throw "Android verification failed with exit code $exitCode."
    }
}

& {
    $testKeystore = Join-Path $fixtureRoot 'fixture.jks'
    & $keytool '-J-Duser.language=en' '-J-Duser.country=US' -genkeypair -keystore $testKeystore -storetype JKS -alias key0 `
        -keyalg RSA -keysize 2048 -validity 1 -dname 'CN=Selume Build Verification' `
        -storepass $testPassword -keypass $testPassword -noprompt
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate the isolated test keystore.' }

    $cases = @(
        @{ Name = 'missing-keystore'; Key = $false; Store = $true; Password = $true; Env = $false },
        @{ Name = 'missing-store-password'; Key = $true; Store = $false; Password = $true; Env = $false },
        @{ Name = 'missing-key-password'; Key = $true; Store = $true; Password = $false; Env = $false },
        @{ Name = 'complete-properties'; Key = $true; Store = $true; Password = $true; Env = $false },
        @{ Name = 'complete-env-precedence'; Key = $true; Store = $true; Password = $true; Env = $true }
    )
    foreach ($case in $cases) {
        $fixtureMobile = Join-Path $fixtureRoot ($case.Name + '/mobile')
        $fixtureAndroid = Join-Path $fixtureMobile 'android'
        $fixtureApp = Join-Path $fixtureAndroid 'app'
        New-Item -ItemType Directory -Path $fixtureApp -Force | Out-Null
        foreach ($file in @('settings.gradle.kts', 'build.gradle.kts', 'gradle.properties')) {
            Copy-Item -LiteralPath (Join-Path $androidRoot $file) -Destination $fixtureAndroid
        }
        foreach ($file in @('pubspec.yaml', '.flutter-plugins-dependencies')) {
            $source = Join-Path $mobileRoot $file
            if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $fixtureMobile }
        }
        Copy-Item -LiteralPath (Join-Path $androidRoot 'app/src') -Destination $fixtureApp -Recurse
        Copy-Item -LiteralPath (Join-Path $androidRoot 'app/proguard-rules.pro') -Destination $fixtureApp
        $appBuild = Get-Content -LiteralPath (Join-Path $androidRoot 'app/build.gradle.kts') -Raw
        if ([regex]::Matches($appBuild, 'source = "\.\./\.\."').Count -ne 1) {
            throw 'Flutter source declaration changed; update the fixture setup.'
        }
        $appBuild = $appBuild.Replace('source = "../.."', 'source = "' + $mobileRoot.Replace('\', '/') + '"')
        Set-Content -LiteralPath (Join-Path $fixtureApp 'build.gradle.kts') -Value $appBuild -Encoding utf8
        if ($case.Key) { Copy-Item -LiteralPath $testKeystore -Destination (Join-Path $fixtureApp 'key.jks') }

        $properties = @(('flutter.sdk=' + $FlutterSdk.Replace('\', '/')), ('sdk.dir=' + $AndroidSdk.Replace('\', '/')))
        if ($case.Store) { $properties += 'storePassword=' + $(if ($case.Env) { 'wrong-local-store' } else { $testPassword }) }
        if ($case.Password) { $properties += 'keyPassword=' + $(if ($case.Env) { 'wrong-local-key' } else { $testPassword }) }
        Set-Content -LiteralPath (Join-Path $fixtureAndroid 'local.properties') -Value $properties -Encoding ascii
        foreach ($name in @('ANDROID_STORE_PASSWORD', 'ANDROID_KEY_PASSWORD')) {
            Set-VerificationEnvironment -Name $name -Value $(if ($case.Env) { $testPassword } else { $null })
        }
        Set-VerificationEnvironment -Name 'SELUME_VERIFY_STORE_PASSWORD' -Value $(if ($case.Store) { $testPassword } else { $null })
        Set-VerificationEnvironment -Name 'SELUME_VERIFY_KEY_PASSWORD' -Value $(if ($case.Password) { $testPassword } else { $null })
        $complete = $case.Key -and $case.Store -and $case.Password
        $environments = if ($case.Name -eq 'complete-properties') {
            @('default', 'production', 'staging', 'development')
        } else { @('default') }
        foreach ($testEnvironment in $environments) {
            Write-Host "Verifying $($case.Name) / $testEnvironment"
            $taskArguments = @(':app:verifySelumnEnvironment', ':app:validateSigningAlphaRelease',
                "-PselumnVerificationEnvironment=$testEnvironment",
                ('-PselumnVerificationSigning=' + $(if ($complete) { 'complete' } else { 'incomplete' })))
            if ($complete) {
                $taskArguments += @(':app:preProductionReleaseBuild', ':app:validateSigningProductionRelease')
            }
            if ($testEnvironment -ne 'default') {
                $define = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("SELUMN_ENVIRONMENT=$testEnvironment"))
                $taskArguments += "-Pdart-defines=$define"
            }
            Invoke-VerificationGradle -ProjectDirectory $fixtureAndroid -TaskArguments $taskArguments
        }
        if (-not $complete) {
            Invoke-VerificationGradle -ProjectDirectory $fixtureAndroid `
                -TaskArguments @(':app:preProductionReleaseBuild') -ExpectFailure $true
        }
    }
    Write-Host "Android environment/signing verification passed. Fixtures: $fixtureRoot"
}
