import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/locale/app_languages.dart';

void main() {
  test('maps Flutter locale codes to Sunbird ISO 639-3 codes', () {
    expect(AppLanguages.sunbirdCodeFor('en'), 'eng');
    expect(AppLanguages.sunbirdCodeFor('lg'), 'lug');
    expect(AppLanguages.sunbirdCodeFor('nyn'), 'nyn');
    expect(AppLanguages.sunbirdCodeFor('xog'), 'xog');
    expect(AppLanguages.sunbirdCodeFor('sw'), 'swa');
    expect(AppLanguages.sunbirdCodeFor('sign'), isNull);
  });

  test('picker lists the written languages plus sign language', () {
    expect(
      AppLanguages.pickerOptions.map((l) => l.flutterCode).toList(),
      ['en', 'lg', 'nyn', 'xog', 'sw', 'sign'],
    );
  });
}
