import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter_litert/flutter_litert.dart';

abstract class IInferenceService {
  Future<void> loadModel();
  Future<double> predict(File imageFile);
  void dispose();
}

class NimaAestheticService implements IInferenceService {
  Interpreter? _interpreter;
  FlexDelegate? _flexDelegate;

  final String modelPath = 'assets/models/nima_aesthetic_fp16_flex.tflite';

  @override
  Future<void> loadModel() async {
    if (_interpreter != null) {
      print('NIMA 이미 로드됨');
      return;
    }

    try {
      print('NIMA Flex 모델 로드 시작: $modelPath');

      // Android에서는 FlexDelegate()가 아니라 create() 사용
      _flexDelegate = await FlexDelegate.create();

      final options = InterpreterOptions()
        ..threads = 4
        ..addDelegate(_flexDelegate!);

      _interpreter = await Interpreter.fromAsset(
        modelPath,
        options: options,
      );

      print('NIMA Flex 모델 로드 성공');
      print(
        'input tensors: ${_interpreter!.getInputTensors().map((t) => t.shape).toList()}',
      );
      print(
        'output tensors: ${_interpreter!.getOutputTensors().map((t) => t.shape).toList()}',
      );
    } catch (e, st) {
      print('NIMA Flex 모델 로드 실패: $e');
      print(st);
      rethrow;
    }
  }

  @override
  Future<double> predict(File imageFile) async {
    if (_interpreter == null) {
      await loadModel();
    }
    if (_interpreter == null) {
      throw Exception('Interpreter가 초기화되지 않았습니다.');
    }

    final imageBytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw Exception('이미지 디코딩 실패');
    }

    final resizedImage = img.copyResize(decodedImage, width: 224, height: 224);

    // [1, 224, 224, 3]
    final input = List.generate(
      1,
          (_) => List.generate(
        224,
            (y) => List.generate(
          224,
              (x) {
            final pixel = resizedImage.getPixel(x, y);
            return <double>[
              (pixel.r.toDouble() / 127.5) - 1.0,
              (pixel.g.toDouble() / 127.5) - 1.0,
              (pixel.b.toDouble() / 127.5) - 1.0,
            ];
          },
        ),
      ),
    );

    // [1, 10]
    final output = List.generate(1, (_) => List.filled(10, 0.0));

    _interpreter!.run(input, output);

    double meanScore = 0.0;
    final probs = output[0];
    for (int i = 0; i < probs.length; i++) {
      meanScore += (i + 1) * probs[i];
    }

    return meanScore;
  }

  @override
  void dispose() {
    _interpreter?.close();
    _interpreter = null;

    _flexDelegate?.delete();
    _flexDelegate = null;
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
