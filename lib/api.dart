import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin client for the NAS AI gateway. Singleton: Api.I
class Api {
  Api._();
  static final Api I = Api._();

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  late Dio _dio;
  String baseUrl = 'http://100.91.166.12:8000'; // tailnet IP of the NAS, gateway port
  String? token;
  List<String> groups = <String>[];

  bool get isLoggedIn => token != null;
  bool get isAdmin => groups.contains('admins');

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('baseUrl') ?? baseUrl;
    groups = prefs.getStringList('groups') ?? <String>[];
    token = await _secure.read(key: 'token');
    _build();
  }

  void _build() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 90),
    ));
    if (token != null) _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
    _build();
  }

  Future<void> login(String username, String password) async {
    final r = await _dio.post<Map<String, dynamic>>('/login',
        data: <String, String>{'username': username, 'password': password});
    token = r.data!['token'] as String;
    groups = List<String>.from(r.data!['groups'] as List<dynamic>? ?? <dynamic>[]);
    await _secure.write(key: 'token', value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('groups', groups);
    _build();
  }

  Future<void> logout() async {
    token = null;
    groups = <String>[];
    await _secure.delete(key: 'token');
    _build();
  }

  Future<List<dynamic>> search(String q, String type) async {
    final r = await _dio.get<Map<String, dynamic>>('/search',
        queryParameters: <String, dynamic>{'q': q, 'type': type});
    return r.data!['results'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> grab(
      {required String type, int? tmdbId, int? tvdbId, required String tier}) async {
    final r = await _dio.post<Map<String, dynamic>>('/grab',
        data: <String, dynamic>{
          'type': type,
          'tier': tier,
          'tmdbId': tmdbId,
          'tvdbId': tvdbId,
        });
    return r.data!;
  }

  Future<List<dynamic>> downloads() async {
    final r = await _dio.get<List<dynamic>>('/downloads');
    return r.data ?? <dynamic>[];
  }

  Future<List<dynamic>> library(String type, String q) async {
    final r = await _dio.get<Map<String, dynamic>>('/library',
        queryParameters: <String, dynamic>{'type': type, 'q': q});
    return r.data!['items'] as List<dynamic>;
  }

  Future<void> deleteItem(String type, int id) async {
    await _dio.delete<dynamic>('/library',
        queryParameters: <String, dynamic>{'type': type, 'id': id});
  }

  Future<List<dynamic>> plexSessions() async {
    final r = await _dio.get<Map<String, dynamic>>('/plex/sessions');
    return r.data!['sessions'] as List<dynamic>;
  }
}
