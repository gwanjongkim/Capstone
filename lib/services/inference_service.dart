import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

abstract class IInferenceService {
  Future<void> loadModel();
  Future<double> predict(File imageFile);
  void dispose();
}

class NimaAestheticService implements IInferenceService {
  Interpreter? _interpreter;
  final String modelPath = 'assets/models/nima_aesthetic_fp16_flex.tflite';

  @override
  Future<void> loadModel() async {
    try {
      // Flex ops are needed for this model
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(modelPath, options: options);
    } catch (e) {
      print('Failed to load NIMA Aesthetic model: $e');
      rethrow;
    }
  }

  @override
  Future<double> predict(File imageFile) async {
    if (_interpreter == null) await loadModel();

    final imageBytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) throw Exception('Failed to decode image');

    // Resize to 224x224 as required by the model
    final resizedImage = img.copyResize(decodedImage, width: 224, height: 224);

    // Prepare input buffer: [1, 224, 224, 3] float32, normalized to [-1, 1]
    var input = Float32List(1 * 224 * 224 * 3);
    int pixelIndex = 0;
    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        final pixel = resizedImage.getPixel(x, y);
        // Using getRed, getGreen, getBlue from image package
        input[pixelIndex++] = (img.getRed(pixel) / 127.5) - 1.0;
        input[pixelIndex++] = (img.getGreen(pixel) / 127.5) - 1.0;
        input[pixelIndex++] = (img.getBlue(pixel) / 127.5) - 1.0;
      }
    }

    var output = List<double>.filled(10, 0).reshape([1, 10]);
    _interpreter!.run(input.reshape([1, 224, 224, 3]), output);

    // Calculate mean score: sum((i+1) * p[i])
    double meanScore = 0.0;
    List<double> distribution = List<double>.from(output[0]);
    for (int i = 0; i < 10; i++) {
      meanScore += (i + 1) * distribution[i];
    }

    return meanScore;
  }

  @override
  void dispose() {
    _interpreter?.close();
  }
}

// Placeholder for future Technical model
class NimaTechnicalService implements IInferenceService {
  @override
  Future<void> loadModel() async {
    // To be implemented
  }

  @override
  Future<double> predict(File imageFile) async {
    return 0.0;
  }

  @override
  void dispose() {}
}
