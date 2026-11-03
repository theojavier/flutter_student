import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/utils/student_class_ids.dart';

void main() {
  group('studentClassIdsFromProfile', () {
    test(
      'includes the primary class and enrolled classes without duplicates',
      () {
        expect(
          studentClassIdsFromProfile({
            'classId': '648',
            'classIds': ['648', '231'],
          }),
          ['648', '231'],
        );
      },
    );

    test('ignores empty IDs and trims string values', () {
      expect(
        studentClassIdsFromProfile({
          'classId': ' ',
          'classIds': [' 231 ', null, ''],
        }),
        ['231'],
      );
    });

    test('returns no IDs when the profile has no class assignments', () {
      expect(studentClassIdsFromProfile(null), isEmpty);
      expect(studentClassIdsFromProfile({}), isEmpty);
    });
  });
}
