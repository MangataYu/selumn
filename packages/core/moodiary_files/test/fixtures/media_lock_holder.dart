import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final file = await File(args[0]).open(mode: FileMode.append);
  await file.lock(args[1] == 'shared' ? FileLock.shared : FileLock.exclusive);
  stdout.writeln('locked');
  await stdout.flush();
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  await file.unlock();
  await file.close();
}
