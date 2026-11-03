import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
import 'package:mui/mui.dart';

class _ThemeWithoutSystemColor extends ThemeManager {
  @override
  Future<void> findDynamicColor() async {}
}

void main() {
  test(
    'theme refresh ignores a saved application font without deleting it',
    () async {
      await getIt.reset();
      final storage = MemoryKVStorage();
      final theme = _ThemeWithoutSystemColor();
      getIt.registerSingleton<IKVStorage>(storage);
      getIt.registerSingleton<ThemeManager>(theme);
      MoodiaryKVs.customFont.set('Previously imported font');
      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await getIt.reset();
      });

      await container.read(appSettingsControllerProvider.notifier).bumpTheme();

      final expected = buildMuiTheme(
        brightness: Brightness.light,
        accent: theme.resolveAccent(),
      );
      expect(
        container
            .read(appSettingsControllerProvider)
            .lightTheme
            .textTheme
            .bodyMedium,
        expected.textTheme.bodyMedium,
      );
      expect(MoodiaryKVs.customFont.get(), 'Previously imported font');
    },
  );
}
