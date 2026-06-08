import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kTmdbApiKey = '459748b4e1dbed21bf8ba93fbff3dab6';
const String kTmdbReadAccessToken =
    'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI0NTk3NDhiNGUxZGJlZDIxYmY4YmE5M2ZiZmYzZGFiNiIsIm5iZiI6MTc4MDgyMjkzMi41NDQ5OTk4LCJzdWIiOiI2YTI1MzM5NDI5NWVhYTUyZmU1YTdiOTEiLCJzY29wZXMiOlsiYXBpX3JlYWQiXSwidmVyc2lvbiI6MX0.y5k0CO0S0805FkAiZgh62AoDycKnMNhzTS6_DUJ-fHo';

/// Thin client for the NAS AI gateway. Singleton: Api.I
class Api {
  Api._();
  static final Api I = Api._();

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  late Dio _dio;
  final Dio _tmdbDio = Dio(BaseOptions(
    baseUrl: 'https://api.themoviedb.org',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  String baseUrl = 'https://nas.mattyzem.com'; // public gateway via Cloudflare Tunnel
  String? token;
  String? username;
  String? displayName;
  List<String> groups = <String>[];
  bool isSuperadmin = false;

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
    isSuperadmin = prefs.getBool('isSuperadmin') ?? false;
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
    isSuperadmin = (data['is_superadmin'] as bool?) ?? false;
    _build();
  }

  Future<void> _persistSession() async {
    await _secure.write(key: 'token', value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('groups', groups);
    await prefs.setString('username', username ?? '');
    await prefs.setString('displayName', displayName ?? username ?? '');
    await prefs.setBool('isSuperadmin', isSuperadmin);
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
    isSuperadmin = false;
    baseUrl = 'https://nas.mattyzem.com';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('baseUrl');
    await _secure.delete(key: 'token');
    _build();
  }

  // ----------------------------- API calls -----------------------------------

  Future<List<dynamic>> search(String q, String type, {String lang = 'en'}) async {
    final r = await _dio.get<Map<String, dynamic>>('/search',
        queryParameters: <String, dynamic>{'q': q, 'type': type, 'lang': lang});
    return r.data!['results'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> grab({
    required String type,
    int? tmdbId,
    int? tvdbId,
    required String tier,
    String language = 'en',
  }) async {
    final r = await _dio.post<Map<String, dynamic>>('/grab',
        data: <String, dynamic>{
          'type': type,
          'tier': tier,
          'tmdbId': tmdbId,
          'tvdbId': tvdbId,
          'language': language,
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

  Future<List<dynamic>> sessions() async {
    final r = await _dio.get<Map<String, dynamic>>('/sessions');
    return r.data!['sessions'] as List<dynamic>;
  }

  Future<void> terminateSession(String source, String sessionKey) async {
    await _dio.delete<dynamic>('/sessions/$source/$sessionKey');
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

  Future<void> reorderTorrent(String hash, int oldIdx, int newIdx) async {
    await _dio.post<dynamic>('/qbt/reorder',
        data: <String, dynamic>{'hash': hash, 'old_idx': oldIdx, 'new_idx': newIdx});
  }

  Future<List<dynamic>> listUsers() async {
    final r = await _dio.get<Map<String, dynamic>>('/users');
    return r.data!['users'] as List<dynamic>;
  }

  Future<void> createUser({
    required String username,
    required String password,
    String displayname = '',
    bool isAdmin = false,
    bool isAiAccess = false,
  }) async {
    await _dio.post<dynamic>('/users', data: <String, dynamic>{
      'username': username,
      'password': password,
      'displayname': displayname,
      'is_admin': isAdmin,
      'is_ai_access': isAiAccess,
    });
  }

  Future<void> updateUser(
    String username, {
    String? password,
    String displayname = '',
    bool isAdmin = false,
    bool isAiAccess = false,
  }) async {
    await _dio.put<dynamic>('/users/$username', data: <String, dynamic>{
      if (password != null) 'password': password,
      'displayname': displayname,
      'is_admin': isAdmin,
      'is_ai_access': isAiAccess,
    });
  }

  Future<void> deleteUser(String username) async {
    await _dio.delete<dynamic>('/users/$username');
  }

  /// Extracts the human-readable detail string from a DioException response.
  /// Returns empty string for non-Dio errors or when no detail field is present.
  static String errorDetail(Object e) {
    if (e is DioException) {
      final dynamic detail =
          (e.response?.data as Map<String, dynamic>?)?['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
    return '';
  }

  // ---- AI chat history -------------------------------------------------------

  Future<List<dynamic>> listChats() async {
    final r = await _dio.get<Map<String, dynamic>>('/ai/chats');
    return r.data!['chats'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> createChat({String title = 'New chat'}) async {
    final r = await _dio.post<Map<String, dynamic>>('/ai/chats',
        data: <String, dynamic>{'title': title});
    return r.data!;
  }

  Future<Map<String, dynamic>> getChat(String chatId) async {
    final r = await _dio.get<Map<String, dynamic>>('/ai/chats/$chatId');
    return r.data!;
  }

  Future<Map<String, dynamic>> sendChatMessage(
      String chatId, String content) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/ai/chats/$chatId/message',
      // active:true tells the gateway the chat screen is open → skip push + unread flag
      data: <String, dynamic>{'content': content, 'active': true},
      options: Options(receiveTimeout: const Duration(minutes: 3)),
    );
    return r.data!;
  }

  Future<void> renameChat(String chatId, String title) async {
    await _dio.patch<dynamic>('/ai/chats/$chatId',
        data: <String, dynamic>{'title': title});
  }

  Future<void> deleteChat(String chatId) async {
    await _dio.delete<dynamic>('/ai/chats/$chatId');
  }

  Future<Map<String, dynamic>> speedtest() async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/speedtest',
      options: Options(receiveTimeout: const Duration(seconds: 90)),
    );
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> notifications() async {
    final r = await _dio.get<Map<String, dynamic>>('/notifications');
    return r.data ?? <String, dynamic>{};
  }

  Future<void> markNotificationsRead() async {
    await _dio.post<dynamic>('/notifications/read');
  }

  Future<void> clearNotifications() async {
    await _dio.post<dynamic>('/notifications/clear');
  }

  Future<void> cancelDownload(String hash) async {
    await _dio.delete<dynamic>('/downloads/$hash');
  }

  Future<void> triggerNewEpisodeCheck() async {
    await _dio.post<dynamic>('/cron/new-episodes');
  }

  Future<Map<String, dynamic>> healthReport() async {
    final r = await _dio.get<Map<String, dynamic>>('/health/report');
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> triggerHealthCheck() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/health/check',
      options: Options(receiveTimeout: const Duration(minutes: 5)),
    );
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> swapTorrent({
    required String type,
    required int itemId,
    required int queueItemId,
    required String guid,
    required int indexerId,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>('/grab/swap',
        data: <String, dynamic>{
          'type': type,
          'item_id': itemId,
          'queue_item_id': queueItemId,
          'guid': guid,
          'indexer_id': indexerId,
        });
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> itemDetail({
    required String type,
    int tmdbId = 0,
    int tvdbId = 0,
  }) async {
    final r = await _dio.get<Map<String, dynamic>>('/detail',
        queryParameters: <String, dynamic>{
          'type': type,
          'tmdb_id': tmdbId,
          'tvdb_id': tvdbId,
        });
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> healthResolve(Map<String, dynamic> item) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/health/resolve',
      data: <String, dynamic>{'item': item},
      options: Options(receiveTimeout: const Duration(minutes: 2)),
    );
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> tmdbMovieDetails(int tmdbId,
      {String language = 'en-US'}) async {
    final r = await _tmdbDio.get<Map<String, dynamic>>(
      '/3/movie/$tmdbId',
      queryParameters: <String, dynamic>{
        'append_to_response': 'credits',
        'language': language,
      },
      options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $kTmdbReadAccessToken',
          }),
    );
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> tmdbTvDetails(int tmdbId,
      {String language = 'en-US'}) async {
    final r = await _tmdbDio.get<Map<String, dynamic>>(
      '/3/tv/$tmdbId',
      queryParameters: <String, dynamic>{
        'append_to_response': 'credits',
        'language': language,
      },
      options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $kTmdbReadAccessToken',
          }),
    );
    return r.data ?? <String, dynamic>{};
  }
}
