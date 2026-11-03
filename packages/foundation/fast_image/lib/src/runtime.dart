import 'rust/frb_generated.dart';

/// Acquires a media-use lease and returns its asynchronous release function.
typedef MediaReadLeaseFactory = Future<Future<void> Function()> Function();

abstract final class FastImageRuntime {
  static String? _imageDir;
  static String? _thumbDir;
  static void Function(String message) _log = (_) {};
  static MediaReadLeaseFactory? mediaReadLeaseFactory;

  /// Hosts that share media with a cleaner can inject a cross-process lease.
  /// Standalone hosts keep the existing behaviour when no factory is set.
  static Future<Future<void> Function()> acquireMediaRead() async =>
      await mediaReadLeaseFactory?.call() ?? () async {};

  static Future<T> withMediaRead<T>(Future<T> Function() action) async {
    final release = await acquireMediaRead();
    try {
      return await action();
    } finally {
      await release();
    }
  }

  // 顺序依赖：先 init() 装载原生库，configure() 之后才能用 FastImageDerivatives / FastImage
  static Future<void> init() => FastImageLib.init();

  static void configure({
    required String imageDir,
    required String thumbDir,
    void Function(String message)? log,
  }) {
    _imageDir = imageDir;
    _thumbDir = thumbDir;
    if (log != null) _log = log;
  }

  static String get imageDir =>
      _imageDir ?? (throw StateError('FastImageRuntime.configure 还没调用'));

  static String get thumbDir =>
      _thumbDir ?? (throw StateError('FastImageRuntime.configure 还没调用'));

  static void log(String message) => _log(message);
}
