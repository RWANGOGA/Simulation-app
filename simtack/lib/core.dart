/// Minimal storage contract so tests can swap in an in-memory fake
/// instead of touching real platform secure storage.
abstract class TokenStorage {
  Future<void> write(String value);
  Future<String?> read();
  Future<void> delete();
}

class SecureTokenStorage implements TokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _tokenKey = 'auth_token';

  @override
  Future<void> write(String value) => _storage.write(key: _tokenKey, value: value);
  @override
  Future<String?> read() => _storage.read(key: _tokenKey);
  @override
  Future<void> delete() => _storage.delete(key: _tokenKey);
}

/// Secure, token-aware HTTP client. Accepts an injectable http.Client and
/// TokenStorage for testing; production code uses ApiClient.instance, which
/// wires up the real ones.
class ApiClient {
  ApiClient({http.Client? httpClient, TokenStorage? storage})
      : _http = httpClient ?? http.Client(),
        _storage = storage ?? SecureTokenStorage();

  static final ApiClient instance = ApiClient();

  final http.Client _http;
  final TokenStorage _storage;

  Uri _uri(String path) => Uri.parse('$kApiBaseUrl$path');

  Future<void> saveToken(String token) => _storage.write(token);
  Future<String?> getToken() => _storage.read();
  Future<void> clearToken() => _storage.delete();
  Future<bool> get isLoggedIn async => (await getToken()) != null;

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await getToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path) async {
    final response = await _http.get(_uri(path), headers: await _headers()).timeout(kRequestTimeout);
    return _handle(response);
  }

  /// application/x-www-form-urlencoded — required by FastAPI's OAuth2PasswordRequestForm.
  Future<dynamic> postForm(String path, Map<String, String> fields) async {
    final headers = await _headers(json: false);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    final response = await _http.post(_uri(path), headers: headers, body: fields).timeout(kRequestTimeout);
    return _handle(response);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    final response = await _http
        .post(_uri(path), headers: await _headers(), body: jsonEncode(body))
        .timeout(kRequestTimeout);
    return _handle(response);
  }

  dynamic _handle(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty ? null : jsonDecode(response.body);
    }
    throw ApiException.fromResponse(response.statusCode, response.body);
  }
}