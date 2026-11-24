import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/exceptions.dart';
import 'package:passkeys/types.dart';

/// Passkey-only authentication backed by server-verified WebAuthn ceremonies.
class PasskeyAuthService {
  PasskeyAuthService({
    required this.app,
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
    PasskeyAuthenticator? authenticator,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _http = httpClient ?? http.Client(),
        _authenticator = authenticator ?? PasskeyAuthenticator(debugMode: kDebugMode);

  static const String _baseUrl =
      'https://us-central1-tabibek-2f25e.cloudfunctions.net';

  final String app;
  final FirebaseAuth _firebaseAuth;
  final http.Client _http;
  final PasskeyAuthenticator _authenticator;

  Map<String, dynamic> accountData = {};

  Future<UserCredential> registerAccount({
    required String displayName,
    required String pin,
    String phone = '',
    String professionalId = '',
  }) async {
    if (pin.length != 6 || !pin.codeUnits.every((c) => c >= 48 && c <= 57)) {
      throw const PasskeyAuthException('أدخل PIN صحيحاً من 6 أرقام.');
    }
    final name = displayName.trim();
    if (name.isEmpty || name.length > 80) {
      throw const PasskeyAuthException('أدخل اسماً صحيحاً.');
    }

    final start = await _post('passkeyRegisterOptions', {
      'app': app,
      'displayName': name,
      'phone': phone,
      'professionalId': professionalId,
      'pin': pin,
    });
    final options = Map<String, dynamic>.from(start['options'] as Map);
    final selection = Map<String, dynamic>.from(
      (options['authenticatorSelection'] as Map?) ?? const {},
    );
    selection['requireResidentKey'] ??= true;
    selection['residentKey'] ??= 'required';
    selection['userVerification'] ??= 'required';
    options['authenticatorSelection'] = selection;
    final challenge = options['challenge'] as String;

    late final RegisterResponseType platformCredential;
    try {
      platformCredential = await _authenticator.register(
        RegisterRequestType.fromJson(options),
      );
    } on MissingGoogleSignInException {
      throw const PasskeyAuthException('سجّل الدخول إلى حساب Google على الجهاز حتى يتمكن مدير كلمات المرور من حفظ مفتاح المرور.');
    } on DomainNotAssociatedException {
      throw const PasskeyAuthException('لم يتم تفعيل ربط التطبيق بنطاق مفاتيح المرور بعد. أعد المحاولة بعد نشر ملف الربط.');
    } on PasskeyUnsupportedException {
      throw const PasskeyAuthException('هذا الجهاز لا يدعم مفاتيح المرور. يلزم Android 9 أو أحدث مع قفل شاشة.');
    }
    final raw = platformCredential.toJson();
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
      'app': app,
      'challenge': challenge,
      'credential': credential,
    });
    return _signInWithToken(finish);
  }

  Future<UserCredential> signIn({required String pin}) async {
    if (pin.length != 6 || !pin.codeUnits.every((c) => c >= 48 && c <= 57)) {
      throw const PasskeyAuthException('أدخل PIN صحيحاً من 6 أرقام.');
    }
    final start = await _post('passkeyLoginOptions', {'app': app});
    final options = Map<String, dynamic>.from(start['options'] as Map);
    final challenge = start['challenge'] as String;

    final platformCredential = await _authenticate(options);
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

    final passkeyResult = await _post('passkeyLoginVerify', {
      'app': app,
      'challenge': challenge,
      'credential': credential,
    });
    final ticket = passkeyResult['loginTicket'];
    if (ticket is! String || ticket.isEmpty) {
      throw const PasskeyAuthException('لم يكتمل التحقق من مفتاح المرور.');
    }
    final finish = await _post('passkeyPinVerify', {
      'app': app,
      'loginTicket': ticket,
      'pin': pin,
    });
    return _signInWithToken(finish);
  }

  Future<AuthenticateResponseType> _authenticate(Map<String, dynamic> options) async {
    try {
      return await _authenticator.authenticate(
        AuthenticateRequestType.fromJson(
          options,
          mediation: MediationType.Optional,
          preferImmediatelyAvailableCredentials: false,
        ),
      );
    } on NoCredentialsAvailableException {
      throw const PasskeyAuthException(
        'لا يوجد مفتاح مرور محفوظ لهذا الحساب على الجهاز أو حساب Google.',
        code: 'passkey-not-found',
      );
    } on MissingGoogleSignInException {
      throw const PasskeyAuthException('سجّل الدخول إلى حساب Google على الجهاز لاستخدام مفاتيح المرور.');
    } on DomainNotAssociatedException {
      throw const PasskeyAuthException('لم يتم تفعيل ربط التطبيق بنطاق مفاتيح المرور بعد. أعد المحاولة لاحقاً.');
    } on PasskeyUnsupportedException {
      throw const PasskeyAuthException('هذا الجهاز لا يدعم مفاتيح المرور. يلزم Android 9 أو أحدث مع قفل شاشة.');
    }
  }

  Future<UserCredential> _signInWithToken(Map<String, dynamic> response) async {
    final token = response['customToken'];
    if (token is! String || token.isEmpty) {
      throw const PasskeyAuthException('لم يرجع الخادم رمز تسجيل دخول صالحاً.');
    }
    final account = response['account'];
    accountData = account is Map ? Map<String, dynamic>.from(account) : {};
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
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Non-JSON responses are reported as a generic service failure below.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = data['error'];
      throw PasskeyAuthException(_messageFor(code is String ? code : 'unknown'), code: code is String ? code : 'unknown');
    }
    return data;
  }

  String _messageFor(String code) {
    switch (code) {
      case 'rate-limited':
      case 'pin-locked':
        return 'تم إيقاف المحاولات مؤقتاً. انتظر 15 دقيقة ثم أعد المحاولة.';
      case 'invalid-pin':
        return 'PIN غير صحيح. حاول مرة أخرى.';
      case 'login-ticket-expired':
        return 'انتهت مهلة تسجيل الدخول. أعد المحاولة.';
      case 'pin-setup-required':
        return 'هذا الحساب يحتاج إلى إعداد PIN. تواصل مع الدعم لإكمال تفعيله.';
      case 'passkey-not-found':
        return 'لم نعثر على مفتاح مرور لهذا الحساب. إذا كانت هذه أول مرة، اختر إنشاء حساب.';
      case 'professional-account-claim-required':
        return 'هذا الرقم المهني مرتبط بملف سابق. يلزم مراجعة الدعم لربط الحساب بأمان.';
      case 'professional-verification-required':
        return 'يتطلب هذا الحساب مراجعة بياناته المهنية قبل تفعيله.';
      case 'challenge-expired':
        return 'انتهت مهلة العملية. أعد المحاولة.';
      default:
        return 'تعذر إكمال العملية بالمفتاح. تأكد من اتصال الإنترنت وإعداد قفل الجهاز.';
    }
  }

  void close() => _http.close();
}

class PasskeyAuthException implements Exception {
  const PasskeyAuthException(this.message, {this.code = 'unknown'});
  final String message;
  final String code;
  @override
  String toString() => message;
}
