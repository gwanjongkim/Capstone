import 'package:camera/camera.dart';
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
      await FirebaseAuthService.instance.initialize();
    }
  } catch (error) {
    debugPrint('Firebase initialization error: $error');
  }

  runApp(const PozyApp());
}
