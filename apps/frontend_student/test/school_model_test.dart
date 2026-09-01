import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_student/shared/models/school_model.dart';

void main() {
  test('parses the public school API contract', () {
    final school = SchoolModel.fromJson({
      'id': 1,
      'code': 'HUCE',
      'name': 'Đại học Xây dựng Hà Nội',
    });

    expect(school.id, 1);
    expect(school.code, 'HUCE');
    expect(school.name, 'Đại học Xây dựng Hà Nội');
  });
}
