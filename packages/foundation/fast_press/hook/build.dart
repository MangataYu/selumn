import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // buildCodeAssets 为 false 时访问 input.config.code 会直接抛异常
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    // Enable the Windows app while preserving other hosts' test setup.
    if (code.targetOS == OS.current && code.targetOS != OS.windows) return;
    // 不设置部署目标环境变量，Xcode 26 SDK 下 rustc 链接会因 ___chkstk_darwin 失败
    final env = switch (code.targetOS) {
      OS.iOS => {'IPHONEOS_DEPLOYMENT_TARGET': '${code.iOS.targetVersion}.0'},
      OS.macOS => {'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}.0'},
      OS.android => const {
        'CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS':
            '-C link-arg=-Wl,-z,max-page-size=16384',
        'CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_RUSTFLAGS':
            '-C link-arg=-Wl,-z,max-page-size=16384',
        'CARGO_TARGET_X86_64_LINUX_ANDROID_RUSTFLAGS':
            '-C link-arg=-Wl,-z,max-page-size=16384',
      },
      _ => const <String, String>{},
    };
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: env,
    ).run(input: input, output: output);
    // 显式登记 Cargo.toml/Cargo.lock 为依赖，否则改动不会触发钩子重跑
    output.dependencies.addAll([
      input.packageRoot.resolve('rust/Cargo.toml'),
      input.packageRoot.resolve('rust/Cargo.lock'),
      input.packageRoot.resolve('rust/rust-toolchain.toml'),
    ]);
  });
}
