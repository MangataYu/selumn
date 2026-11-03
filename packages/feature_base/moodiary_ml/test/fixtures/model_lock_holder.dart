import 'dart:io';

Future<void> main(List<String> args) async {
  final lock = await File(args.single).open(mode: FileMode.append);
  await lock.lock(FileLock.blockingExclusive);
  stdout.writeln('locked');
  await stdin.first;
  await lock.close();
}
