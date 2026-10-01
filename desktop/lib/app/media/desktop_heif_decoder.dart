import 'package:injectable/injectable.dart';
import 'package:moodiary_files/moodiary_files.dart';

@LazySingleton(as: IHeifDecoder)
class DesktopHeifDecoder implements IHeifDecoder {
  @override
  Future<String?> convert(
    String srcPath, {
    required String outputPath,
    required String format,
  }) async {
    // The mobile HEIF converter has no Windows implementation. Let the existing
    // media import error handling report the unsupported conversion.
    throw UnsupportedError('HEIF conversion is unavailable on Windows');
  }
}
