import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin client for the NAS AI gateway. Singleton: Api.I
class Api {
  Api._();
  static final Api I = Api._();

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  late Dio _dio;
  String baseUrl = 'http://100.91.166.12:8000'; // tailnet IP of the NAS, gateway port
  String? token;
  String? username;
  String? displayName;
  List<String> groups = <String>[];

  bool get isLoggedIn => token != null;
  bool get isAdmin => groups.contains('admins');
  String get role => isAdmin ? 'admin' : 'user';

  /// Called when the gateway returns 401 and auto-reauth also fails.
  void Function()? onUnauthorized;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('baseUrl') ?? baseUrl;
    groups = prefs.getStringList('groups') ?? <String>[];
    username = prefs.getString('username');
    displayName = prefs.getString('displayName');
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
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, ErrorInterceptorHandler handler) async {
        if (e.response?.statusCode == 401 && token != null) {
          // Try silent re-auth with stored credentials before giving up.
          final bool reauthed = await _tryAutoLogin();
          if (reauthed) {
            // Retry the original request with the new token.
            final opts = e.requestOptions;
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              final resp = await _dio.fetch<dynamic>(opts);
              return handler.resolve(resp);
            } catch (_) {}
          }
          await logout();
          onUnauthorized?.call();
        }
        handler.next(e);
      },
    ));
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
    _build();
  }

  // ----------------------------- auth / remember-me --------------------------

  Future<void> login(String username, String password) async {
    final r = await _dio.post<Map<String, dynamic>>('/login',
        data: <String, String>{'username': username, 'password': password});
    _applyLoginResponse(r.data!);
    await _persistSession();
  }

  void _applyLoginResponse(Map<String, dynamic> data) {
    token = data['token'] as String;
    username = data['username'] as String?;
    final dynamic dn = data['displayname'];
    displayName = dn is String && dn.isNotEmpty ? dn : username;
    groups = List<String>.from(data['groups'] as List<dynamic>? ?? <dynamic>[]);
    _build();
  }

  Future<void> _persistSession() async {
    await _secure.write(key: 'token', value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('groups', groups);
    await prefs.setString('username', username ?? '');
    await prefs.setString('displayName', displayName ?? username ?? '');
  }

  /// Returns true if credentials are stored and not expired.
  Future<bool> hasRememberedCredentials() async {
    final expStr = await _secure.read(key: 'rememberExpiry');
    if (expStr == null) return false;
    final exp = int.tryParse(expStr) ?? 0;
    return DateTime.now().millisecondsSinceEpoch < exp;
  }

  Future<String?> rememberedUsername() => _secure.read(key: 'rememberUser');

  /// Saves credentials for remember-me. Call after a successful login.
  Future<void> saveRememberedCredentials(String username, String password) async {
    final exp = DateTime.now()
        .add(const Duration(days: 365))
        .millisecondsSinceEpoch;
    await _secure.write(key: 'rememberUser', value: username);
    await _secure.write(key: 'rememberPass', value: password);
    await _secure.write(key: 'rememberExpiry', value: exp.toString());
  }

  /// Refreshes the 365-day expiry (call on each successful use).
  Future<void> renewRememberedExpiry() async {
    final hasIt = await hasRememberedCredentials();
    if (!hasIt) return;
    final exp = DateTime.now()
        .add(const Duration(days: 365))
        .millisecondsSinceEpoch;
    await _secure.write(key: 'rememberExpiry', value: exp.toString());
  }

  Future<void> clearRememberedCredentials() async {
    await _secure.delete(key: 'rememberUser');
    await _secure.delete(key: 'rememberPass');
    await _secure.delete(key: 'rememberExpiry');
  }

  /// Silent auto-login using stored credentials (no biometric).
  Future<bool> _tryAutoLogin() async {
    try {
      final hasIt = await hasRememberedCredentials();
      if (!hasIt) return false;
      final u = await _secure.read(key: 'rememberUser');
      final p = await _secure.read(key: 'rememberPass');
      if (u == null || p == null) return false;
      await login(u, p);
      await renewRememberedExpiry();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Auto-login with biometric gate (called from UI on startup).
  /// Returns true on success.
  Future<bool> biometricAutoLogin() async {
    try {
      final hasIt = await hasRememberedCredentials();
      if (!hasIt) return false;
      final available = await _localAuth.isDeviceSupported();
      if (!available) {
        // Fall back to silent auto-login if biometrics not available.
        return _tryAutoLogin();
      }
      final authed = await _localAuth.authenticate(
        localizedReason: 'Authenticate to log in to NAS',
        options: const AuthenticationOptions(biometricOnly: false),
      );
      if (!authed) return false;
      return _tryAutoLogin();
    } catch (_) {
      return false;
    }
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    token = null;
    username = null;
    displayName = null;
    groups = <String>[];
    await _secure.delete(key: 'token');
    _build();
  }

  // ----------------------------- API calls -----------------------------------

  Future<List<dynamic>> search(String q, String type, {String lang = 'en'}) async {
    final r = await _dio.get<Map<String, dynamic>>('/search',
        queryParameters: <String, dynamic>{'q': q, 'type': type, 'lang': lang});
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

  Future<Map<String, dynamic>> diskspace() async {
    final r = await _dio.get<Map<String, dynamic>>('/diskspace');
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> transfer() async {
    final r = await _dio.get<Map<String, dynamic>>('/transfer');
    return r.data ?? <String, dynamic>{};
  }

  Future<List<dynamic>> plexSessions() async {
    final r = await _dio.get<Map<String, dynamic>>('/plex/sessions');
    return r.data!['sessions'] as List<dynamic>;
  }

  Future<void> terminatePlexSession(String sessionKey) async {
    await _dio.delete<dynamic>('/plex/sessions/$sessionKey');
  }

  Future<Map<String, dynamic>> qbtLimits() async {
    final r = await _dio.get<Map<String, dynamic>>('/qbt/limits');
    return r.data ?? <String, dynamic>{};
  }

  Future<void> setQbtLimits(double dlMbps, double upMbps) async {
    await _dio.post<dynamic>('/qbt/limits',
        data: <String, dynamic>{'dl_mbps': dlMbps, 'up_mbps': upMbps});
  }

  Future<void> qbtPause() async => _dio.post<dynamic>('/qbt/pause');
  Future<void> qbtResume() async => _dio.post<dynamic>('/qbt/resume');

  Future<List<dynamic>> listUsers() async {
    final r = await _dio.get<Map<String, dynamic>>('/users');
    return r.data!['users'] as List<dynamic>;
  }

  Future<void> createUser({
    required String username,
    required String password,
    String displayname = '',
    bool isAdmin = false,
  }) async {
    await _dio.post<dynamic>('/users', data: <String, dynamic>{
      'username': username,
      'password': password,
      'displayname': displayname,
      'is_admin': isAdmin,
    });
  }

  Future<void> updateUser(
    String username, {
    String? password,
    String displayname = '',
    bool isAdmin = false,
  }) async {
    await _dio.put<dynamic>('/users/$username', data: <String, dynamic>{
      if (password != null) 'password': password,
      'displayname': displayname,
      'is_admin': isAdmin,
    });
  }

  Future<void> deleteUser(String username) async {
    await _dio.delete<dynamic>('/users/$username');
  }
}
