class SchoolModel {
  final int id;
  final String code;
  final String name;

  const SchoolModel({required this.id, required this.code, required this.name});

  factory SchoolModel.fromJson(Map<String, dynamic> json) {
    final code = json['code'] as String;

    return SchoolModel(
      id: json['id'] as int,
      code: code,
      name: _normalizeSchoolName(
        code: code,
        rawName: json['name'] as String? ?? '',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'code': code, 'name': name};
  }

  static String _normalizeSchoolName({
    required String code,
    required String rawName,
  }) {
    switch (code.trim().toUpperCase()) {
      case 'HUCE':
        return 'Đại học Xây dựng Hà Nội';
      case 'HUST':
        return 'Đại học Bách khoa Hà Nội';
      default:
        return rawName;
    }
  }
}
