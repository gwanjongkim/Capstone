import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (error) {
    debugPrint('Camera initialization error: $error');
  }

  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase initialization error: $error');
  }

  runApp(const PozyApp());
}
