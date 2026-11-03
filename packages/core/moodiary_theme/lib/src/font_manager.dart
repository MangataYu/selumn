import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:path/path.dart';

import 'font_tables.dart';

class FontManager {
  static Future<String?> getFontName({required String filePath}) =>
      FontTables.fullName(filePath);

  static Future<Map<String, dynamic>> getFontWghtAxis({
    required String filePath,
  }) async {
    try {
      return Map<String, dynamic>.from(await FontTables.wghtAxis(filePath));
    } catch (_) {
      return {};
    }
  }

  static Future<XFile?> pickFont() {
    return getIt<IFilePicker>().pickFile(allowedExtensions: ['ttf', 'otf']);
  }

  static Future<List<({String fileName, Map<String, dynamic> wghtAxis})>>
  scanFontFiles() async {
    final fontFileList = await AppFiles.getDirFilePath('font');
    final result = <({String fileName, Map<String, dynamic> wghtAxis})>[];
    for (final fontFile in fontFileList) {
      final fontName = await getFontName(filePath: fontFile);
      if (fontName == null) continue;
      result.add((
        fileName: '$fontName${extension(fontFile)}',
        wghtAxis: await getFontWghtAxis(filePath: fontFile),
      ));
    }
    return result;
  }
}
