import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_mobile/app/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers the QWeather Icons artwork license', () async {
    registerThirdPartyLicenses();
    final license = await LicenseRegistry.licenses.firstWhere(
      (entry) => entry.packages.contains('QWeather Icons'),
    );
    final text = license.paragraphs.map((paragraph) => paragraph.text).join();
    expect(text, contains('Copyright QWeather'));
    expect(text, contains('https://github.com/qwd/Icons'));
    expect(text, contains('https://creativecommons.org/licenses/by/4.0/'));
  });
}
