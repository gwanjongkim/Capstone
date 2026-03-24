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
      final options = InterpreterOptions();
      // Flex ops are necessary for NIMA models
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

    final resizedImage = img.copyResize(decodedImage, width: 224, height: 224);

    // image 4.2.0 API: Using pixel.r, pixel.g, pixel.b directly
    var input = Float32List(1 * 224 * 224 * 3);
    int pixelIndex = 0;
    
    for (final pixel in resizedImage) {
      // Normalize to [-1, 1] using value / 127.5 - 1.0
      input[pixelIndex++] = (pixel.r / 127.5) - 1.0;
      input[pixelIndex++] = (pixel.g / 127.5) - 1.0;
      input[pixelIndex++] = (pixel.b / 127.5) - 1.0;
    }

    // Explicitly shape the output
    var output = List<double>.filled(1 * 10, 0).reshape([1, 10]);
    
    // Convert Float32List to List<double> for the .reshape extension
    final reshapedInput = (input as List<double>).reshape([1, 224, 224, 3]);
    
    _interpreter!.run(reshapedInput, output);

    double meanScore = 0.0;
    List<dynamic> results = output[0];
    for (int i = 0; i < 10; i++) {
      meanScore += (i + 1) * results[i];
    }

    return meanScore;
  }

  @override
  void dispose() {
    _interpreter?.close();
  }
}

class NimaTechnicalService implements IInferenceService {
  @override
  Future<void> loadModel() async {}
  @override
  Future<double> predict(File imageFile) async => 0.0;
  @override
  void dispose() {}
}
