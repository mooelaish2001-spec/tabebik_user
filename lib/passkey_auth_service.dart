import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

/// Client for the Firebase WebAuthn endpoints.
///
/// The server verifies every ceremony and returns a Firebase Custom Token.
/// This class intentionally exposes patient registration only: doctor and
/// center enrollment must first be bound to their licence/approval workflows.
class PasskeyAuthService {
  PasskeyAuthService({
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
    PasskeyAuthenticator? authenticator,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _http = httpClient ?? http.Client(),
        _authenticator = authenticator ?? PasskeyAuthenticator();

  static const String _baseUrl =
      'https://us-central1-tabibek-2f25e.cloudfunctions.net';
  static const String _app = 'tabebik_user';

  final FirebaseAuth _firebaseAuth;
  final http.Client _http;
  final PasskeyAuthenticator _authenticator;

  Future<UserCredential> registerPatient({
    required String displayName,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty || name.length > 80) {
      throw const PasskeyAuthException('أدخل اسماً صحيحاً.');
    }

    final start = await _post('passkeyRegisterOptions', {
      'app': _app,
      'displayName': name,
    });
    final options = Map<String, dynamic>.from(start['options'] as Map);
    final challenge = options['challenge'] as String;

    final platformCredential = await _authenticator.register(
      RegisterRequestType.fromJson(options),
    );
    final raw = platformCredential.toJson();
    // Convert the Flutter plugin's flattened response to the standard
    // PublicKeyCredential JSON shape expected by SimpleWebAuthn.
    final credential = <String, dynamic>{
      'id': raw['id'],
      'rawId': raw['rawId'],
      'type': 'public-key',
      'response': {
        'clientDataJSON': raw['clientDataJSON'],
        'attestationObject': raw['attestationObject'],
        'transports': raw['transports'] ?? <String>[],
      },
      'clientExtensionResults': raw['clientExtensionResults'] ?? <String, dynamic>{},
    };

    final finish = await _post('passkeyRegisterVerify', {
      'app': _app,
      'challenge': challenge,
      'displayName': name,
      'credential': credential.toJson(),
    });
    return _signInWithToken(finish);
  }

  Future<UserCredential> signIn() async {
    final start = await _post('passkeyLoginOptions', {'app': _app});
    final options = Map<String, dynamic>.from(start['options'] as Map);
    final challenge = start['challenge'] as String;

    final platformCredential = await _authenticator.authenticate(
      AuthenticateRequestType.fromJson(
        options,
        mediation: MediationType.Optional,
        preferImmediatelyAvailableCredentials: false,
      ),
    );
    final raw = platformCredential.toJson();
    final credential = <String, dynamic>{
      'id': raw['id'],
      'rawId': raw['rawId'],
      'type': 'public-key',
      'response': {
        'clientDataJSON': raw['clientDataJSON'],
        'authenticatorData': raw['authenticatorData'],
        'signature': raw['signature'],
        'userHandle': raw['userHandle'],
      },
      'clientExtensionResults': raw['clientExtensionResults'] ?? <String, dynamic>{},
    };

    final finish = await _post('passkeyLoginVerify', {
      'app': _app,
      'challenge': challenge,
      'credential': credential.toJson(),
    });
    return _signInWithToken(finish);
  }

  Future<UserCredential> _signInWithToken(Map<String, dynamic> response) {
    final token = response['customToken'];
    if (token is! String || token.isEmpty) {
      throw const PasskeyAuthException('لم يرجع الخادم رمز تسجيل دخول صالحاً.');
    }
    return _firebaseAuth.signInWithCustomToken(token);
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final response = await _http
        .post(
          Uri.parse('$_baseUrl/$endpoint'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      // A non-JSON response is handled below as a generic server error.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = data['error'];
      throw PasskeyAuthException(
        _messageFor(code is String ? code : 'unknown'),
      );
    }
    return data;
  }

  String _messageFor(String code) {
    switch (code) {
      case 'rate-limited':
        return 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة.';
      case 'passkey-not-found':
        return 'لا يوجد مفتاح مرور لهذا الحساب على هذا الجهاز أو حساب Google.';
      case 'professional-verification-required':
        return 'تسجيل الطبيب والمركز يحتاج إلى إكمال التحقق المهني أولاً.';
      case 'challenge-expired':
        return 'انتهت مهلة العملية. أعد المحاولة.';
      default:
        return 'تعذر إكمال تسجيل الدخول بالمفتاح. حاول مرة أخرى.';
    }
  }

  void close() => _http.close();
}

class PasskeyAuthException implements Exception {
  const PasskeyAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
