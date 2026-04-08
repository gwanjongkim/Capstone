import 'package:camera/camera.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'firebase_bootstrap.dart';
import 'services/firebase_auth_service.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  try {
    cameras = await availableCameras();
  } catch (error) {
    debugPrint('Camera initialization error: $error');
  }

  try {
    await FirebaseBootstrap.initialize();
    if (FirebaseBootstrap.isInitialized) {
      await _activateFirebaseAppCheck();
      await FirebaseAuthService.instance.initialize();
    }
  } catch (error, st) {
    debugPrint('Firebase initialization error: $error');
    debugPrint('$st');
  }

  runApp(const PozyApp());
}

Future<void> _activateFirebaseAppCheck() async {
  if (kIsWeb) {
    debugPrint('[APP_CHECK] skipped on web: provider not configured');
    return;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kReleaseMode
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
      );
      debugPrint(
        '[APP_CHECK] activated androidProvider=${kReleaseMode ? 'playIntegrity' : 'debug'}',
      );
      return;
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      await FirebaseAppCheck.instance.activate(
        providerApple: kReleaseMode
            ? const AppleAppAttestWithDeviceCheckFallbackProvider()
            : const AppleDebugProvider(),
      );
      debugPrint(
        '[APP_CHECK] activated appleProvider=${kReleaseMode ? 'appAttestWithDeviceCheckFallback' : 'debug'}',
      );
      return;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      debugPrint('[APP_CHECK] skipped on unsupported platform=$defaultTargetPlatform');
      return;
  }
}
