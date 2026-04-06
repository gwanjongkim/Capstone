import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

class FirebaseBootstrap {
  static String? _lastErrorMessage;

  static String? get lastErrorMessage => _lastErrorMessage;

  static bool get isInitialized => Firebase.apps.isNotEmpty;

  static Future<void> initialize() async {
    if (Firebase.apps.isNotEmpty) {
      _lastErrorMessage = null;
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _lastErrorMessage = null;
      return;
    } on UnsupportedError catch (optionsError) {
      await _initializeFromNativeConfig(fallbackError: optionsError);
      return;
    } catch (error) {
      if (Firebase.apps.isNotEmpty) {
        _lastErrorMessage = null;
        return;
      }
      await _initializeFromNativeConfig(fallbackError: error);
    }
  }

  static Never throwIfUnavailable() {
    throw StateError(
      _lastErrorMessage ??
          'Firebase가 아직 초기화되지 않았어요. Firebase 프로젝트 설정을 먼저 추가해 주세요.',
    );
  }

  static Future<void> _initializeFromNativeConfig({
    required Object fallbackError,
  }) async {
    try {
      await Firebase.initializeApp();
      _lastErrorMessage = null;
    } catch (nativeError) {
      _lastErrorMessage = _buildMissingConfigurationMessage(
        generatedOptionsError: fallbackError,
        nativeConfigError: nativeError,
      );
      debugPrint('Firebase bootstrap error: $_lastErrorMessage');
    }
  }

  static String _buildMissingConfigurationMessage({
    required Object generatedOptionsError,
    required Object nativeConfigError,
  }) {
    final details = <String>[
      _compactError(generatedOptionsError),
      _compactError(nativeConfigError),
    ].where((message) => message.isNotEmpty).join(' | ');

    final suffix = details.isEmpty ? '' : ' 세부 정보: $details';
    return 'Firebase 프로젝트 설정이 아직 연결되지 않았어요. '
        '`android/app/google-services.json`, '
        '`ios/Runner/GoogleService-Info.plist`, '
        '그리고 FlutterFire를 사용하는 경우 `lib/firebase_options.dart`를 '
        '실제 프로젝트 값으로 추가한 뒤 다시 실행해 주세요.$suffix';
  }

  static String _compactError(Object error) {
    final raw = error.toString().trim();
    return raw
        .replaceFirst('Unsupported operation: ', '')
        .replaceFirst('Bad state: ', '')
        .replaceAll('\n', ' ')
        .trim();
  }
}
