import 'package:file_picker/file_picker.dart' as fp;
import 'package:injectable/injectable.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:mui/mui.dart';

@LazySingleton(as: IFilePicker)
class DesktopFilePicker implements IFilePicker {
  @override
  Future<List<XFile>> pickImages(
    BuildContext context, {
    int maxAssets = 9,
  }) async {
    if (maxAssets <= 0) return const [];
    final files = await fp.FilePicker.pickFiles(
      type: .custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
    );
    return files.take(maxAssets).map((file) => file.xFile).toList();
  }

  @override
  Future<XFile?> pickVideo(BuildContext context) async =>
      (await fp.FilePicker.pickFile(type: .video))?.xFile;

  @override
  Future<XFile?> pickAudio() async =>
      (await fp.FilePicker.pickFile(type: .audio))?.xFile;

  @override
  Future<XFile?> pickFile({List<String>? allowedExtensions}) async =>
      (await fp.FilePicker.pickFile(
        type: allowedExtensions == null ? .any : .custom,
        allowedExtensions: allowedExtensions,
      ))?.xFile;
}
