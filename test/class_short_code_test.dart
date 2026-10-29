import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/helpers/class_short_code.dart';

void main() {
  group('classShortCode', () {
    test('uses initials for two to four meaningful subject words', () {
      expect(classShortCode('649', 'Object Based Programming'), '649-OBP');
      expect(classShortCode('321', 'Network and Security'), '321-NS');
    });

    test('uses a shortened first word for longer subject names', () {
      expect(
        classShortCode(
          '649',
          'Introduction to Object Based Programming Languages',
        ),
        '649-INTR',
      );
      expect(classShortCode('777', 'Mathematics'), '777-MATH');
    });

    test('falls back to the class code when there is no subject', () {
      expect(classShortCode('649', ''), '649');
    });
  });
}
