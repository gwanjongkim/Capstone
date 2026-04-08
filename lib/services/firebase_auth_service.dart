import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';

class FirebaseAuthService {
  FirebaseAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  static final FirebaseAuthService instance = FirebaseAuthService();

  final FirebaseAuth _auth;

  String? _lastErrorMessage;

  String? get lastErrorMessage => _lastErrorMessage;

  User? get currentUser => _auth.currentUser;

  String? get currentUid => currentUser?.uid;

  bool get isSignedIn => currentUser != null;

  Future<User> initialize() => ensureSignedIn();

  Future<User> ensureSignedIn() async {
    if (!FirebaseBootstrap.isInitialized) {
      FirebaseBootstrap.throwIfUnavailable();
    }

    debugPrint(
      '[AUTH] currentUser(before)=${FirebaseAuth.instance.currentUser?.uid}',
    );

    final existingUser = _auth.currentUser;
    if (existingUser != null) {
      _lastErrorMessage = null;
      return existingUser;
    }

    try {
      final credential = await _auth.signInAnonymously();
      debugPrint(
        '[AUTH] signInAnonymously success uid=${credential.user?.uid}',
      );
      final user = credential.user;
      if (user == null) {
        throw StateError('Firebase 익명 로그인 사용자 정보를 확인하지 못했어요.');
      }
      _lastErrorMessage = null;
      return user;
    } on FirebaseAuthException catch (error, st) {
      debugPrint('[AUTH][ERROR] signInAnonymously failed: $error');
      debugPrint('$st');
      final message = _userFacingAuthError(error);
      _lastErrorMessage = message;
      throw StateError(message);
    } catch (error, st) {
      debugPrint('[AUTH][ERROR] signInAnonymously failed: $error');
      debugPrint('$st');
      final message = error.toString().replaceFirst('Bad state: ', '');
      _lastErrorMessage = message;
      throw StateError(message);
    }
  }

  String _userFacingAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'operation-not-allowed':
        return 'Firebase Anonymous Auth가 비활성화되어 있어요. Firebase Console에서 Anonymous 로그인 제공자를 켜 주세요.';
      case 'network-request-failed':
        return 'Firebase 인증 네트워크 요청에 실패했어요. 연결 상태를 확인해 주세요.';
      case 'too-many-requests':
        return 'Firebase 인증 요청이 잠시 제한되었어요. 잠시 후 다시 시도해 주세요.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
        return 'Firebase 인증을 완료하지 못했어요. 코드: ${error.code}';
    }
  }
}
