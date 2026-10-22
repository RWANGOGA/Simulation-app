import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/patient_profile.dart';

/// Storage contract for the auth token — abstracted so tests can inject
/// an in-memory fake instead of touching platform secure storage.
abstract class TokenStorage {
  Future<void> write(String value);
  Future<String?> read();
  Future<void> writeRefreshToken(String value) async {}
  Future<String?> readRefreshToken() async => null;
  Future<void> delete();
}

class SecureTokenStorage implements TokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';

  @override
  Future<void> write(String value) =>
      _storage.write(key: _tokenKey, value: value);

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeRefreshToken(String value) =>
      _storage.write(key: _refreshTokenKey, value: value);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> delete() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}

class Doctor {
  final int id;
  final String email;
  final String fullName;
  final bool isActive;
  final String? role;
  final String? licenseNumber;
  final String? phone;
  final String? hospitalName;

  /// False until an administrator approves a freshly registered account.
  /// A pending account cannot sign in, so the register screen has to be able
  /// to tell the two outcomes apart instead of showing the 403 as a failure.
  /// Defaults to false: a server that did not say "approved" must never be
  /// interpreted as approval.
  final bool isApproved;

  /// 'practitioner' or 'admin'. Display only — every privileged action is
  /// re-checked on the server, so a tampered client gains nothing.
  final String accessLevel;

  const Doctor({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    this.role,
    this.licenseNumber,
    this.phone,
    this.hospitalName,
    this.isApproved = false,
    this.accessLevel = 'practitioner',
  });

  bool get isAdmin => accessLevel == 'admin';

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: (json['full_name'] as String?) ?? '',
        isActive: json['is_active'] as bool? ?? true,
        role: json['role'] as String?,
        licenseNumber: json['license_number'] as String?,
        phone: json['phone'] as String?,
        hospitalName: json['hospital_name'] as String?,
        isApproved: json['is_approved'] as bool? ?? false,
        accessLevel: (json['access_level'] as String?) ?? 'practitioner',
      );
}

/// Error thrown by every API call, with FastAPI's error shape parsed out —
/// handles both {"detail": "..."} (401) and {"detail": [...]} (422).
///
/// Transport failures are folded into the same type so callers only ever
/// have to catch one thing. [isNetworkError] marks those, which lets a screen
/// say "you are offline" instead of echoing a server rejection.
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  /// True when the request never reached the server (no connection, DNS or
  /// socket failure) or the server did not answer in time.
  final bool isNetworkError;

  ApiException({
    required this.message,
    this.statusCode,
    this.isNetworkError = false,
  });

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;

  factory ApiException.fromResponse(int statusCode, String body) {
    try {
      final decoded = body.isNotEmpty ? jsonDecode(body) : null;
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is String) {
        return ApiException(statusCode: statusCode, message: detail);
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        final msg = first is Map
            ? (first['msg']?.toString() ?? 'Validation error')
            : first.toString();
        return ApiException(statusCode: statusCode, message: msg);
      }
      return ApiException(
        statusCode: statusCode,
        message: "Unexpected error (status $statusCode)",
      );
    } catch (_) {
      return ApiException(
        statusCode: statusCode,
        message: "Unexpected error (status $statusCode)",
      );
    }
  }
}

class PatientResult {
  final int id;
  final String anonymousCode;

  const PatientResult({required this.id, required this.anonymousCode});

  factory PatientResult.fromJson(Map<String, dynamic> json) => PatientResult(
        id: json['id'] as int,
        anonymousCode: json['anonymous_code'] as String,
      );
}

class TriageReport {
  final String bodyRegion;
  final String painType;
  final int severity;
  final String? direction;
  final String? depth;
  final String? expansionBehavior;
  final List<String>? triggers;
  final List<String>? relievers;
  final List<String>? dailyLimitations;
  final int? patientId;
  final String? patientCode;
  final String? visitId;
  final Map<String, String>? questionAnswers;

  const TriageReport({
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.depth,
    this.expansionBehavior,
    this.triggers,
    this.relievers,
    this.dailyLimitations,
    this.patientId,
    this.patientCode,
    this.visitId,
    this.questionAnswers,
  });

  Map<String, dynamic> toJson() => {
        'body_region': bodyRegion,
        'pain_type': painType,
        'severity': severity,
        if (direction != null) 'direction': direction,
        if (depth != null) 'depth': depth,
        if (expansionBehavior != null && expansionBehavior!.isNotEmpty)
          'expansion_behavior': expansionBehavior,
        if (triggers != null && triggers!.isNotEmpty)
          'triggers': jsonEncode(triggers),
        if (relievers != null && relievers!.isNotEmpty)
          'relievers': jsonEncode(relievers),
        if (dailyLimitations != null && dailyLimitations!.isNotEmpty)
          'daily_limitations': jsonEncode(dailyLimitations),
        if (patientId != null && patientId! > 0) 'patient_id': patientId,
        if (visitId != null) 'visit_id': visitId,
        if (questionAnswers != null && questionAnswers!.isNotEmpty)
          'question_answers': questionAnswers,
      };

  /// Reverses [toJson] for a report that was scored and stored on the device
  /// and is now being uploaded.
  ///
  /// The list fields have to be read two ways because [toJson] writes them as
  /// JSON strings and a payload that round-tripped through the local store can
  /// arrive as real lists. Accepting both means a queued report is never
  /// uploaded with its triggers silently dropped.
  factory TriageReport.fromJson(Map<String, dynamic> json) => TriageReport(
        bodyRegion: (json['body_region'] as String?) ?? '',
        painType: (json['pain_type'] as String?) ?? '',
        severity: (json['severity'] as num?)?.toInt() ?? 0,
        direction: json['direction'] as String?,
        depth: json['depth'] as String?,
        expansionBehavior: json['expansion_behavior'] as String?,
        triggers: _stringList(json['triggers']),
        relievers: _stringList(json['relievers']),
        dailyLimitations: _stringList(json['daily_limitations']),
        patientId: (json['patient_id'] as num?)?.toInt(),
        patientCode: json['patient_code'] as String?,
        visitId: json['visit_id'] as String?,
        questionAnswers: json['question_answers'] is Map
            ? {
                for (final entry in (json['question_answers'] as Map).entries)
                  entry.key.toString(): entry.value.toString(),
              }
            : null,
      );

  /// A queued report carries no server ids — they did not exist when it was
  /// written — so the upload supplies them here.
  TriageReport withPatient({int? patientId, String? patientCode}) =>
      TriageReport(
        bodyRegion: bodyRegion,
        painType: painType,
        severity: severity,
        direction: direction,
        depth: depth,
        expansionBehavior: expansionBehavior,
        triggers: triggers,
        relievers: relievers,
        dailyLimitations: dailyLimitations,
        patientId: patientId ?? this.patientId,
        patientCode: patientCode ?? this.patientCode,
        visitId: visitId,
        questionAnswers: questionAnswers,
      );

  static List<String>? _stringList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        // Not JSON — fall through and treat the row as having no list.
      }
    }
    return null;
  }
}

class TriageEscalation {
  /// Red-flag verdict from the server (triage_service.escalation_for).
  ///
  /// Deliberately separate from [TriageResult.riskScore]: the score is a clamped
  /// sum, so a single dangerous finding can sit inside a medium total. 'level'
  /// is the server's verdict, 'action' says what the patient should do, and
  /// 'reasons' are the findings that fired.
  final String level;
  final String action;
  final List<String> reasons;

  const TriageEscalation({
    required this.level,
    this.action = '',
    this.reasons = const [],
  });

  bool get isEmergency => level == 'emergency';
  bool get isUrgent => level == 'urgent';

  /// Returns null rather than throwing: an older server without the field, or a
  /// malformed payload, must never stop a report from rendering.
  static TriageEscalation? tryParse(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final level = raw['level'];
    if (level is! String || level.isEmpty) return null;
    final triggers = raw['triggers'];
    return TriageEscalation(
      level: level,
      action: raw['action'] is String ? raw['action'] as String : '',
      reasons: [
        if (triggers is List)
          for (final trigger in triggers)
            if (trigger is Map<String, dynamic> && trigger['detail'] is String)
              trigger['detail'] as String,
      ],
    );
  }
}

class TriageResult {
  final int id;
  final int? patientId;
  final String? anonymousCode;
  final String bodyRegion;
  final String painType;
  final int severity;
  final String? direction;
  final String? depth;
  final String? expansionBehavior;
  final List<String> triggers;
  final List<String> relievers;
  final List<String> dailyLimitations;
  final String? visitId;
  final double? riskScore;
  // Red flags, computed server-side from the clinical fields on every read.
  final TriageEscalation? escalation;
  final String? shapExplanation;
  final String? qrPayloadHash;
  final DateTime createdAt;
  // Patient demographics — collected at intake and stored server-side, now
  // joined onto every triage response so they can actually be displayed.
  final int? patientAge;
  final String? patientGender;
  final double? patientWeight;
  final double? patientHeight;
  // Personal demographics carried through so the practitioner sees the
  // patient's identity/contact when scanning the QR passport.
  final String? patientName;
  final String? patientDateOfBirth;
  final String? patientPhone;
  final String? patientAddress;
  final String? patientNextOfKinName;
  final String? patientNextOfKinPhone;
  final String? patientHospitalName;
  // Practitioner decision workflow (blueprint section 5).
  final String status; // 'open' until reviewed, then 'closed'
  final String? priority;
  final List<String> actionsTaken;
  final String? clinicalNotes;
  final Map<String, String>? questionAnswers;

  const TriageResult({
    required this.id,
    this.patientId,
    this.anonymousCode,
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.depth,
    this.expansionBehavior,
    this.triggers = const [],
    this.relievers = const [],
    this.dailyLimitations = const [],
    this.visitId,
    this.riskScore,
    this.escalation,
    this.shapExplanation,
    this.qrPayloadHash,
    required this.createdAt,
    this.patientAge,
    this.patientGender,
    this.patientWeight,
    this.patientHeight,
    this.patientName,
    this.patientDateOfBirth,
    this.patientPhone,
    this.patientAddress,
    this.patientNextOfKinName,
    this.patientNextOfKinPhone,
    this.patientHospitalName,
    this.status = 'open',
    this.priority,
    this.actionsTaken = const [],
    this.clinicalNotes,
    this.questionAnswers,
  });

  String get riskLevel {
    final score = riskScore ?? 0.0;
    if (score >= 0.7) return 'HIGH RISK';
    if (score >= 0.4) return 'MEDIUM RISK';
    return 'LOW RISK';
  }

  /// True when this pain point carries a red flag that needs care now.
  bool get needsEmergencyCare => escalation?.isEmergency ?? false;

  /// True when care is needed today, but not necessarily in an emergency unit.
  bool get needsUrgentCare => escalation?.isUrgent ?? false;

  factory TriageResult.fromJson(Map<String, dynamic> json) {
    return TriageResult(
      id: json['id'] as int,
      patientId: json['patient_id'] as int?,
      anonymousCode: json['anonymous_code'] as String?,
      bodyRegion: json['body_region'] as String,
      painType: json['pain_type'] as String,
      severity: json['severity'] as int,
      direction: json['direction'] as String?,
      depth: json['depth'] as String?,
      expansionBehavior: json['expansion_behavior'] as String?,
      triggers: _parseListString(json['triggers']),
      relievers: _parseListString(json['relievers']),
      dailyLimitations: _parseListString(json['daily_limitations']),
      visitId: json['visit_id'] as String?,
      riskScore: (json['risk_score'] as num?)?.toDouble(),
      escalation: TriageEscalation.tryParse(json['escalation']),
      shapExplanation: json['shap_explanation'] as String?,
      qrPayloadHash: json['qr_payload_hash'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      patientAge: json['patient_age'] as int?,
      patientGender: json['patient_gender'] as String?,
      patientWeight: (json['patient_weight'] as num?)?.toDouble(),
      patientHeight: (json['patient_height'] as num?)?.toDouble(),
      patientName: json['patient_name'] as String?,
      patientDateOfBirth: json['patient_date_of_birth'] as String?,
      patientPhone: json['patient_phone'] as String?,
      patientAddress: json['patient_address'] as String?,
      patientNextOfKinName: json['patient_next_of_kin_name'] as String?,
      patientNextOfKinPhone: json['patient_next_of_kin_phone'] as String?,
      patientHospitalName: json['patient_hospital_name'] as String?,
      status: (json['status'] as String?) ?? 'open',
      priority: json['priority'] as String?,
      actionsTaken: _parseActionsTaken(json['actions_taken']),
      clinicalNotes: json['clinical_notes'] as String?,
      questionAnswers: (json['question_answers'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  static List<String> _parseListString(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        return [raw];
      }
    }
    return const [];
  }

  // actions_taken travels as a JSON array string ("[\"a\", \"b\"]") from the
  // server, which stores it in a text column. A list is accepted too so a
  // locally assembled payload cannot silently lose a practitioner's ticked
  // actions — this is the record of what was actually done for the patient.
  static List<String> _parseActionsTaken(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        // Malformed JSON — treat as no actions rather than crashing.
      }
    }
    return const [];
  }
}

class ApiClient {
  static String get baseUrl {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredUrl.isNotEmpty) return configuredUrl;
    if (kDebugMode) {
      const debugHost = String.fromEnvironment(
        'API_DEBUG_HOST',
        defaultValue: '127.0.0.1',
      );
      return 'http://$debugHost:8000/api/v1';
    } else {
      return 'https://backend-fastapi-linv.onrender.com/api/v1';
    }
  }

  static http.Client httpClient = http.Client();
  static TokenStorage tokenStorage = SecureTokenStorage();

  /// Bounded wait for a normal request. The production host is a free tier
  /// that sleeps when idle; 20s covers a warm server plus a slow mobile link
  /// without leaving the UI spinning forever. Public so screens and tests can
  /// reason about the same number instead of guessing.
  static const Duration requestTimeout = Duration(seconds: 20);

  /// The first contact after the host has been idle can take ~50s to wake
  /// up, so the two calls a patient is most likely to make first get a
  /// longer leash.
  static const Duration _coldStartTimeout = Duration(seconds: 45);

  /// Fired once when a session can no longer be repaired (refresh token
  /// missing or rejected). main.dart wires this to a redirect back to the
  /// login screen, so an expired session never leaves the practitioner
  /// staring at empty screens.
  static void Function()? onSessionExpired;

  /// De-duplicates concurrent refreshes: if five requests get a 401 at the
  /// same moment we must not fire five refresh calls.
  static Future<bool>? _refreshInFlight;

  static Future<Map<String, String>> _authHeaders({bool json = true}) async {
    final token = await tokenStorage.read();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': "Bearer $token",
    };
  }

  /// The single choke point for every backend call.
  ///
  /// Routing everything through here buys three guarantees that the previous
  /// hand-rolled calls each had to remember for themselves:
  ///
  /// 1. **No request can hang forever** — every call is bounded by [timeout].
  /// 2. **One exception type** — transport failures, timeouts and non-2xx
  ///    answers all surface as [ApiException].
  /// 3. **Expired tokens heal themselves** — a 401 triggers one refresh and
  ///    one retry; when that fails the session is cleared and
  ///    [onSessionExpired] sends the app back to the login screen.
  ///
  /// Throws [ApiException] and returns the response only when it carries
  /// [expectedStatus].
  static Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = requestTimeout,
    bool authenticated = true,
    bool retryOnUnauthorized = true,
    int expectedStatus = 200,
  }) async {
    http.Response response;
    try {
      response = await _dispatch(method, uri, headers, body).timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        message: 'The request timed out after ${timeout.inSeconds} seconds. '
            'The server may still be waking up — please try again.',
        isNetworkError: true,
      );
    } catch (error) {
      if (error is ApiException) rethrow;
      if (_isTransportFailure(error)) {
        throw ApiException(
          message: 'Cannot reach the server. Check your internet connection '
              'and try again.',
          isNetworkError: true,
        );
      }
      rethrow;
    }

    if (response.statusCode == 401 && authenticated && retryOnUnauthorized) {
      if (await _refreshAccessTokenOnce()) {
        // The access token changed, so the auth header has to be rebuilt —
        // replaying the stale one would just 401 again.
        return _send(
          method,
          uri,
          headers: await _withFreshToken(headers),
          body: body,
          timeout: timeout,
          authenticated: authenticated,
          retryOnUnauthorized: false,
          expectedStatus: expectedStatus,
        );
      }
      await _clearSession();
    }

    if (response.statusCode != expectedStatus) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return response;
  }

  static Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String>? headers,
    Object? body,
  ) {
    switch (method) {
      case 'GET':
        return httpClient.get(uri, headers: headers);
      case 'POST':
        return httpClient.post(uri, headers: headers, body: body);
      case 'PATCH':
        return httpClient.patch(uri, headers: headers, body: body);
      case 'PUT':
        return httpClient.put(uri, headers: headers, body: body);
      case 'DELETE':
        return httpClient.delete(uri, headers: headers, body: body);
      default:
        throw ArgumentError.value(method, 'Unsupported HTTP method');
    }
  }

  /// Recognises "the request never made it" without importing dart:io, which
  /// has no web implementation. Matching on the runtime type keeps this file
  /// compilable for the web build while still catching SocketException,
  /// HandshakeException and friends on mobile and desktop.
  static bool _isTransportFailure(Object error) {
    if (error is http.ClientException) return true;
    const transportTypes = {
      'SocketException',
      'HandshakeException',
      'TlsException',
      'HttpException',
    };
    return transportTypes.contains(error.runtimeType.toString());
  }

  /// Replaces the bearer token in an existing header map after a refresh.
  static Future<Map<String, String>?> _withFreshToken(
      Map<String, String>? headers) async {
    if (headers == null || !headers.containsKey('Authorization')) {
      return headers;
    }
    final token = await tokenStorage.read();
    final refreshed = Map<String, String>.of(headers);
    if (token != null) {
      refreshed['Authorization'] = 'Bearer $token';
    }
    return refreshed;
  }

  /// Refreshes the access token at most once per wave of 401s.
  /// Returns false when the session cannot be repaired.
  static Future<bool> _refreshAccessTokenOnce() {
    final pending = _refreshInFlight;
    if (pending != null) return pending;
    final future = _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
    _refreshInFlight = future;
    return future;
  }

  static Future<bool> _performRefresh() async {
    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      // Same urlencoded shape /login uses; the backend accepts the token from
      // the form body or the query string.
      final response = await httpClient.post(
        Uri.parse('$baseUrl/auth/refresh'),
        body: {'refresh_token': refreshToken},
      ).timeout(requestTimeout);
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['access_token'] as String?;
      if (token == null) return false;
      await tokenStorage.write(token);
      final rotated = data['refresh_token'] as String?;
      if (rotated != null) await tokenStorage.writeRefreshToken(rotated);
      return true;
    } catch (_) {
      // Any failure here means the session is not recoverable.
      return false;
    }
  }

  static Future<void> _clearSession() async {
    await tokenStorage.delete();
    onSessionExpired?.call();
  }

  static Future<Doctor> login(
      {required String email, required String password}) async {
    // Unauthenticated call: a 401 here means "wrong password", not "expired
    // session", so it must never trigger the refresh-and-retry path.
    final response = await _send(
      'POST',
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
      authenticated: false,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    if (token == null) {
      throw ApiException(
          message: 'Login response was missing an access token.');
    }
    await tokenStorage.write(token);
    final refreshToken = data['refresh_token'] as String?;
    if (refreshToken != null) {
      await tokenStorage.writeRefreshToken(refreshToken);
    }
    return getCurrentDoctor();
  }

  /// Explicit refresh, for callers that want to extend a session proactively
  /// (for example when the app returns to the foreground).
  static Future<void> refreshAccessToken() async {
    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      throw ApiException(message: 'No refresh token is available.');
    }
    final http.Response response;
    try {
      response = await _send(
        'POST',
        Uri.parse('$baseUrl/auth/refresh'),
        body: {'refresh_token': refreshToken},
        authenticated: false,
      );
    } on ApiException {
      // A dead refresh token must not linger; otherwise every later request
      // keeps retrying a session that can never come back.
      await tokenStorage.delete();
      rethrow;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    if (token == null) {
      throw ApiException(
          message: 'Refresh response was missing an access token.');
    }
    await tokenStorage.write(token);
    // The backend rotates: the token we just spent is now consumed, so the
    // replacement has to be stored or the next refresh fails and the
    // practitioner is signed out mid-session.
    final rotated = data['refresh_token'] as String?;
    if (rotated != null) await tokenStorage.writeRefreshToken(rotated);
  }

  /// Creates a practitioner account, then logs in with the same
  /// credentials so the user lands directly on the dashboard.
  static Future<Doctor> register({
    required String email,
    required String password,
    required String fullName,
    String? role,
    String? licenseNumber,
    String? phone,
    String? hospitalName,
    DateTime? dateOfBirth,
    String? inviteCode,
  }) async {
    final response = await _send(
      'POST',
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
        if (role != null && role.isNotEmpty) 'role': role,
        if (licenseNumber != null && licenseNumber.isNotEmpty)
          'license_number': licenseNumber,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (hospitalName != null && hospitalName.trim().isNotEmpty)
          'hospital_name': hospitalName.trim(),
        if (dateOfBirth != null)
          'date_of_birth': '${dateOfBirth.year.toString().padLeft(4, '0')}-'
              '${dateOfBirth.month.toString().padLeft(2, '0')}-'
              '${dateOfBirth.day.toString().padLeft(2, '0')}',
        if (inviteCode != null && inviteCode.trim().isNotEmpty)
          'invite_code': inviteCode.trim(),
      }),
      authenticated: false,
      expectedStatus: 201,
    );
    // Registered but not yet signed in — the token is issued by login below.
    //
    // Unless the account is pending approval. Signing up no longer grants
    // access, and /auth/login answers 403 for an unapproved account, so
    // calling it here would turn a success into an error on screen and invite
    // the user to retry into a 409 "already exists". Returning the pending
    // account lets the caller say what actually happened.
    final registered = Doctor.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (!registered.isApproved) return registered;
    return login(email: email, password: password);
  }

  static Future<Doctor> getCurrentDoctor() async {
    final response = await _send(
      'GET',
      Uri.parse('$baseUrl/auth/me'),
      headers: await _authHeaders(),
    );
    return Doctor.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<bool> get isLoggedIn async =>
      (await tokenStorage.read()) != null;

  static Future<void> logout() => tokenStorage.delete();

  // The live backend is hosted on a free tier that goes to sleep after a
  // period of inactivity and can take 30 to 50 seconds to wake back up.
  // The very first request after that sleep can otherwise hang with no
  // response at all, which browsers then report as a misleading CORS
  // failure rather than a timeout. A bounded timeout here turns that into
  // an honest, actionable error instead.
  static Future<PatientResult> createPatient(
    PatientProfile profile, {
    String? anonymousCode,
  }) async {
    final body = profile.toJson();
    // A device that recorded the patient while offline minted this code itself
    // and already printed it on the patient's card, so it is sent back here:
    // the server then answers on the same code, and a retried upload is a no-op
    // (409) instead of a second record for the same person.
    if (anonymousCode != null && anonymousCode.isNotEmpty) {
      body['anonymous_code'] = anonymousCode;
    }
    final response = await _send(
      'POST',
      Uri.parse('$baseUrl/patients/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
      timeout: _coldStartTimeout,
      authenticated: false,
      expectedStatus: 201,
    );
    return PatientResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Practitioner-only correction of a patient's demographics — sends only
  /// the fields the caller actually set on [profile] (see
  /// PatientProfile.toJson), so an edit to just one field doesn't clobber
  /// the rest. JWT-guarded on the backend.
  static Future<void> updatePatientDemographics(
      String anonymousCode, PatientProfile profile) async {
    await _send(
      'PATCH',
      Uri.parse('$baseUrl/patients/$anonymousCode'),
      headers: await _authHeaders(),
      body: jsonEncode(profile.toJson()),
    );
  }

  static Future<TriageResult> sendTriage(TriageReport report) async {
    // No debugPrint of the payload: it carries the patient's symptoms and
    // demographics, and debug logs are readable by anyone with the device.
    final response = await _send(
      'POST',
      Uri.parse('$baseUrl/triage/'),
      headers: {
        'Content-Type': 'application/json',
        if (report.patientCode != null) 'X-Patient-Code': report.patientCode!,
      },
      body: jsonEncode(report.toJson()),
      timeout: _coldStartTimeout,
      authenticated: false,
      expectedStatus: 201,
    );
    return TriageResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<TriageResult>> getLatestVisit(String patientCode) async {
    // Anonymous lookup — no JWT; routed through the shared pipeline anyway
    // so tests can inject a mock and callers get the same error handling.
    final response = await _send(
      'GET',
      Uri.parse('$baseUrl/triage/patient/$patientCode'),
      authenticated: false,
    );
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => TriageResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Practitioner-only: every session the patient ever submitted, newest
  /// first. Powers the visit timeline on the clinical report.
  static Future<List<TriageResult>> getPatientHistory(
      String patientCode) async {
    final response = await _send(
      'GET',
      Uri.parse('$baseUrl/triage/patient/$patientCode/history'),
      headers: await _authHeaders(),
    );
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => TriageResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Map<String, dynamic>> getTriageStats() async {
    // Doctor-only endpoint — must carry the JWT.
    final response = await _send(
      'GET',
      Uri.parse('$baseUrl/triage/stats'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getTriageReports(
      {String period = 'all'}) async {
    // Doctor-only endpoint — must carry the JWT.
    final response = await _send(
      'GET',
      Uri.parse('$baseUrl/triage/reports?period=$period'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getTriageList({
    int limit = 50,
    int offset = 0,
    String? patientCode,
    String? riskLevel,
    String? status,
  }) async {
    final uri = Uri.parse('$baseUrl/triage/list').replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (patientCode != null) 'patient_code': patientCode,
      if (riskLevel != null) 'risk_level': riskLevel,
      if (status != null) 'status': status,
    });
    // Doctor-only endpoint — must carry the JWT.
    final response = await _send('GET', uri, headers: await _authHeaders());
    return List<Map<String, dynamic>>.from(jsonDecode(response.body));
  }

  /// Practitioner review workflow: saves the decision (status, priority,
  /// ticked actions, notes) on one triage session. Doctor-only endpoint —
  /// must carry the JWT.
  static Future<TriageResult> updateTriageDecision(
    int sessionId, {
    String? status,
    String? priority,
    List<String>? actionsTaken,
    String? clinicalNotes,
  }) async {
    final response = await _send(
      'PATCH',
      Uri.parse('$baseUrl/triage/$sessionId/decision'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (status != null) 'status': status,
        if (priority != null) 'priority': priority,
        if (actionsTaken != null) 'actions_taken': actionsTaken,
        if (clinicalNotes != null) 'clinical_notes': clinicalNotes,
      }),
    );
    return TriageResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<Doctor> updateDoctorProfile({
    String? fullName,
    String? role,
    String? licenseNumber,
    String? phone,
    String? hospitalName,
    DateTime? dateOfBirth,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName.trim();
    if (role != null) body['role'] = role.trim().isEmpty ? null : role.trim();
    if (licenseNumber != null)
      body['license_number'] =
          licenseNumber.trim().isEmpty ? null : licenseNumber.trim();
    if (phone != null)
      body['phone'] = phone.trim().isEmpty ? null : phone.trim();
    if (hospitalName != null)
      body['hospital_name'] =
          hospitalName.trim().isEmpty ? null : hospitalName.trim();
    if (dateOfBirth != null)
      body['date_of_birth'] =
          '${dateOfBirth.year.toString().padLeft(4, '0')}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

    final response = await _send(
      'PATCH',
      Uri.parse('$baseUrl/auth/me'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    return Doctor.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // ── Anatomy assistant (Step 7.5) ──────────────────────────────────────

  static Future<AnatomyInsight> askAnatomy({
    required String region,
    String complaint = '',
    int topK = 3,
    String? conversationId,
  }) async {
    final body = <String, dynamic>{
      'region': region,
      'complaint': complaint,
      'top_k': topK,
    };
    if (conversationId != null && conversationId.isNotEmpty) {
      body['conversation_id'] = conversationId;
    }
    final response = await _send(
      'POST',
      Uri.parse('$baseUrl/anatomy/ask'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    return AnatomyInsight.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<List<AnatomyRegion>> listAnatomyRegions() async {
    final response = await _send(
      'GET',
      Uri.parse('$baseUrl/anatomy/regions'),
      headers: await _authHeaders(),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (body['regions'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(AnatomyRegion.fromJson)
        .toList();
  }
}

/// Lightweight descriptor returned by GET /anatomy/regions. Used to render
/// pickers and (optionally) to prefetch insights on screen open.
class AnatomyRegion {
  final String id;
  final String region;
  final String system;

  const AnatomyRegion(
      {required this.id, required this.region, required this.system});

  factory AnatomyRegion.fromJson(Map<String, dynamic> json) => AnatomyRegion(
        id: (json['id'] as String?) ?? '',
        region: (json['region'] as String?) ?? '',
        system: (json['system'] as String?) ?? '',
      );
}

/// One likely condition with a short rationale, as returned by the LLM
/// in /anatomy/ask.
class AnatomyCondition {
  final String name;
  final String rationale;

  const AnatomyCondition({required this.name, required this.rationale});

  factory AnatomyCondition.fromJson(Map<String, dynamic> json) =>
      AnatomyCondition(
        name: (json['name'] as String?) ?? '',
        rationale: (json['rationale'] as String?) ?? '',
      );
}

/// One retrieved chunk surfaced alongside the LLM answer, so the UI can
/// show "based on: Chest / Heart, Abdomen (Upper)...".
class AnatomySource {
  final String id;
  final String region;
  final String system;
  final double score;
  final String text;
  final List<String> structures;
  final List<String> commonConditions;
  final List<String> redFlags;
  final List<String> suggestedQuestions;

  const AnatomySource({
    required this.id,
    required this.region,
    required this.system,
    required this.score,
    required this.text,
    required this.structures,
    required this.commonConditions,
    required this.redFlags,
    required this.suggestedQuestions,
  });

  factory AnatomySource.fromJson(Map<String, dynamic> json) => AnatomySource(
        id: (json['id'] as String?) ?? '',
        region: (json['region'] as String?) ?? '',
        system: (json['system'] as String?) ?? '',
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
        text: (json['text'] as String?) ?? '',
        structures: (json['structures'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        commonConditions: (json['common_conditions'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        redFlags: (json['red_flags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        suggestedQuestions: (json['suggested_questions'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );
}

class AnatomyCitation {
  final String text;
  final String region;
  final String system;
  final String chunkId;

  const AnatomyCitation({
    required this.text,
    required this.region,
    required this.system,
    required this.chunkId,
  });

  factory AnatomyCitation.fromJson(Map<String, dynamic> json) =>
      AnatomyCitation(
        text: (json['text'] as String?) ?? '',
        region: (json['region'] as String?) ?? '',
        system: (json['system'] as String?) ?? '',
        chunkId: (json['chunk_id'] as String?) ?? '',
      );
}

/// Full response of POST /anatomy/ask. The `llmUsed` and `cached` flags let
/// the UI show an "AI" / "KB" / "Cached" badge so the clinician knows where
/// the answer came from.
class AnatomyInsight {
  final String? region;
  final String complaint;
  final bool llmUsed;
  final bool cached;
  final String summary;
  final List<String> structures;
  final List<AnatomyCondition> likelyConditions;
  final List<String> redFlags;
  final List<String> suggestedQuestions;
  final String disclaimer;
  final List<AnatomySource> sources;
  final List<AnatomyCitation> citations;

  const AnatomyInsight({
    required this.region,
    required this.complaint,
    required this.llmUsed,
    required this.cached,
    required this.summary,
    required this.structures,
    required this.likelyConditions,
    required this.redFlags,
    required this.suggestedQuestions,
    required this.disclaimer,
    required this.sources,
    required this.citations,
  });

  factory AnatomyInsight.fromJson(Map<String, dynamic> json) {
    List<String> strList(String key) {
      final v = json[key];
      if (v is List) {
        return v.whereType<String>().toList();
      }
      return const [];
    }

    return AnatomyInsight(
      region: json['region'] as String?,
      complaint: (json['complaint'] as String?) ?? '',
      llmUsed: (json['llm_used'] as bool?) ?? false,
      cached: (json['cached'] as bool?) ?? false,
      summary: (json['summary'] as String?) ?? '',
      structures: strList('structures'),
      likelyConditions: ((json['likely_conditions'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AnatomyCondition.fromJson)
          .toList(),
      redFlags: strList('red_flags'),
      suggestedQuestions: strList('suggested_questions'),
      disclaimer: (json['disclaimer'] as String?) ?? '',
      sources: ((json['sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AnatomySource.fromJson)
          .toList(),
      citations: ((json['citations'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AnatomyCitation.fromJson)
          .toList(),
    );
  }
}
