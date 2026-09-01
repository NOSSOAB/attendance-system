import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../shared/models/school_model.dart';
import '../config/api_config.dart';

class SchoolsApiService {
  Future<List<SchoolModel>> getSchools() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/schools');

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception(
        'API lỗi: status=${response.statusCode}, body=${response.body}',
      );
    }

    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;

    return data
        .map((item) => SchoolModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
