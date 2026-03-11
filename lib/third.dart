import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

// third.dart에서 사용할 전역 변수
List<CameraDescription> cameras = [];

// ---------------------------------------------------------
// 1. MathStabilizer (Python의 Stabilizer 포팅)
// ---------------------------------------------------------
class MathStabilizer {
  final double alpha;
  final double stickyMarginRatio;

  double? smoothedX;
  double? smoothedY;
  Point<int>? currentBestPoint;

  MathStabilizer({this.alpha = 0.25, this.stickyMarginRatio = 0.08});

  Point<int> update(double rawX, double rawY) {
    if (smoothedX == null || smoothedY == null) {
      smoothedX = rawX;
      smoothedY = rawY;
    } else {
      smoothedX = smoothedX! * (1 - alpha) + rawX * alpha;
      smoothedY = smoothedY! * (1 - alpha) + rawY * alpha;
    }
    return Point<int>(smoothedX!.toInt(), smoothedY!.toInt());
  }

  Map<String, dynamic> getStickyTarget(
    List<Point<int>> intersections,
    int screenWidth,
  ) {
    if (smoothedX == null || smoothedY == null || intersections.isEmpty) {
      return {'point': null, 'distance': double.infinity};
    }

    if (currentBestPoint == null) {
      double minDist = double.infinity;
      for (var p in intersections) {
        double dist = sqrt(pow(smoothedX! - p.x, 2) + pow(smoothedY! - p.y, 2));
        if (dist < minDist) {
          minDist = dist;
          currentBestPoint = p;
        }
      }
    } else {
      double currDist = sqrt(
        pow(smoothedX! - currentBestPoint!.x, 2) +
            pow(smoothedY! - currentBestPoint!.y, 2),
      );
      double stickyMargin = screenWidth * stickyMarginRatio;

      for (var p in intersections) {
        double newDist = sqrt(
          pow(smoothedX! - p.x, 2) + pow(smoothedY! - p.y, 2),
        );
        if (newDist < currDist - stickyMargin) {
          currentBestPoint = p;
          currDist = newDist;
        }
      }
    }

    double finalDist = sqrt(
      pow(smoothedX! - currentBestPoint!.x, 2) +
          pow(smoothedY! - currentBestPoint!.y, 2),
    );
    return {'point': currentBestPoint, 'distance': finalDist};
  }

  void reset() {
    smoothedX = null;
    smoothedY = null;
    currentBestPoint = null;
  }
}

// ---------------------------------------------------------
// 2. RuleOfThirdsCoach (3분할법 코칭)
// ---------------------------------------------------------
class RuleOfThirdsCoach {
  static const double perfectThresholdRatio = 0.1;

  int width = 0;
  int height = 0;
  int x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  List<Point<int>> intersections = [];

  void calculateGrid(int screenWidth, int screenHeight) {
    width = screenWidth;
    height = screenHeight;

    // 3분할 지점 계산 (1/3, 2/3)
    x1 = width ~/ 3;
    x2 = (width * 2) ~/ 3;
    y1 = height ~/ 3;
    y2 = (height * 2) ~/ 3;

    // 4개의 교차점
    intersections = [
      Point<int>(x1, y1), // 좌상
      Point<int>(x2, y1), // 우상
      Point<int>(x1, y2), // 좌하
      Point<int>(x2, y2), // 우하
    ];
  }

  bool isPerfect(double distance) {
    return distance < (width * perfectThresholdRatio);
  }
}

// ---------------------------------------------------------
// 3. UI 렌더링 (CustomPainter)
// ---------------------------------------------------------
class RuleOfThirdsPainter extends CustomPainter {
  final RuleOfThirdsCoach coach;
  final Point<int>? currentSubjectPos;
  final Point<int>? targetPos;
  final bool isPerfect;
  final Rect? personBoundingBox;

  RuleOfThirdsPainter({
    required this.coach,
    this.currentSubjectPos,
    this.targetPos,
    this.isPerfect = false,
    this.personBoundingBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    coach.calculateGrid(size.width.toInt(), size.height.toInt());

    // 3분할 그리드 선 그리기
    final Paint gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 세로선 2개
    canvas.drawLine(
      Offset(coach.x1.toDouble(), 0),
      Offset(coach.x1.toDouble(), size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(coach.x2.toDouble(), 0),
      Offset(coach.x2.toDouble(), size.height),
      gridPaint,
    );

    // 가로선 2개
    canvas.drawLine(
      Offset(0, coach.y1.toDouble()),
      Offset(size.width, coach.y1.toDouble()),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, coach.y2.toDouble()),
      Offset(size.width, coach.y2.toDouble()),
      gridPaint,
    );

    // 교차점 표시
    final Paint intersectionPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    for (var point in coach.intersections) {
      canvas.drawCircle(
        Offset(point.x.toDouble(), point.y.toDouble()),
        4.0,
        intersectionPaint,
      );
    }

    // 바운딩 박스 그리기
    if (personBoundingBox != null) {
      final Paint boxPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final Paint boxShadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRect(personBoundingBox!, boxShadowPaint);
      canvas.drawRect(personBoundingBox!, boxPaint);

      const detectedTextStyle = TextStyle(
        color: Colors.cyanAccent,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(color: Colors.black, blurRadius: 3)],
      );
      final detectedTextPainter = TextPainter(
        text: const TextSpan(text: "Person Detected", style: detectedTextStyle),
        textDirection: TextDirection.ltr,
      );
      detectedTextPainter.layout();
      detectedTextPainter.paint(
        canvas,
        Offset(personBoundingBox!.left, personBoundingBox!.top - 20),
      );
    }

    // 타겟과 피사체 연결 선
    if (currentSubjectPos != null && targetPos != null) {
      Color stateColor = isPerfect ? Colors.greenAccent : Colors.amber;

      final Paint connectionPaint = Paint()
        ..color = stateColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isPerfect ? 3.0 : 2.0;

      final Paint subjectPaint = Paint()
        ..color = isPerfect ? Colors.greenAccent : Colors.redAccent
        ..style = PaintingStyle.fill;

      canvas.drawLine(
        Offset(currentSubjectPos!.x.toDouble(), currentSubjectPos!.y.toDouble()),
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        connectionPaint,
      );

      canvas.drawCircle(
        Offset(currentSubjectPos!.x.toDouble(), currentSubjectPos!.y.toDouble()),
        isPerfect ? 8.0 : 6.0,
        subjectPaint,
      );
      canvas.drawCircle(
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        8.0,
        connectionPaint,
      );

      if (isPerfect) {
        const perfectTextStyle = TextStyle(
          color: Colors.greenAccent,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        );
        final perfectTextPainter = TextPainter(
          text: const TextSpan(text: "PERFECT!", style: perfectTextStyle),
          textDirection: TextDirection.ltr,
        );
        perfectTextPainter.layout();
        perfectTextPainter.paint(canvas, const Offset(20, 100));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---------------------------------------------------------
// 4. Rule of Thirds Screen (3분할법 코칭 화면)
// ---------------------------------------------------------
class RuleOfThirdsScreen extends StatefulWidget {
  const RuleOfThirdsScreen({super.key});

  @override
  State<RuleOfThirdsScreen> createState() => _RuleOfThirdsScreenState();
}

class _RuleOfThirdsScreenState extends State<RuleOfThirdsScreen> {
  CameraController? _controller;
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  bool _isDetecting = false;
  String? _screenError;

  final MathStabilizer _stabilizer = MathStabilizer();
  final RuleOfThirdsCoach _coach = RuleOfThirdsCoach();

  Point<int>? _smoothPos;
  Point<int>? _targetPos;
  bool _isPerfect = false;
  Rect? _personBoundingBox;
  
  // 디버그 정보
  String _debugInfo = "";
  double _rawX640 = 0;
  double _rawY640 = 0;

  @override
  void initState() {
    super.initState();
    _loadModel();
    if (cameras.isNotEmpty) {
      _initializeCamera();
    } else {
      _screenError = "카메라를 찾을 수 없습니다.";
    }
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/yolov8n-pose_float16.tflite',
      );
      if (!mounted) return;
      
      // 모델 입력/출력 형식 확인
      debugPrint('Model loaded successfully!');
      debugPrint('Input tensors: ${_interpreter!.getInputTensors()}');
      debugPrint('Output tensors: ${_interpreter!.getOutputTensors()}');
      
      setState(() {
        _isModelLoaded = true;
      });
      debugPrint('모델 로드 성공!');
    } catch (e) {
      debugPrint('모델 로드 실패: $e');
      if (mounted) {
        setState(() {
          _screenError = '모델 로드 실패:\n$e';
        });
      }
    }
  }

  void _initializeCamera() {
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});

      if (Theme.of(context).platform == TargetPlatform.windows ||
          Theme.of(context).platform == TargetPlatform.macOS ||
          Theme.of(context).platform == TargetPlatform.linux) {
        setState(() {
          _screenError = "데스크톱 플랫폼은 실시간 카메라 추론을 미지원하므로 가상 모드로 동작합니다.";
        });
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _mockProcessLoop();
        });
        return;
      }

      try {
        _controller!.startImageStream((CameraImage image) {
          if (!_isDetecting && _isModelLoaded) {
            _isDetecting = true;
            _processCameraImage(image).then((_) {
              _isDetecting = false;
            });
          }
        });
      } catch (e) {
        debugPrint('Image Stream Error: $e');
        setState(() {
          _screenError = '카메라 스트림을 시작할 수 없습니다:\n$e';
        });
      }
    }).catchError((e) {
      debugPrint('Camera Init Error: $e');
      if (mounted) {
        setState(() {
          _screenError = '카메라 초기화 실패:\n$e';
        });
      }
    });
  }

  void _mockProcessLoop() async {
    while (mounted && _screenError != null && _screenError!.contains("가상 모드")) {
      if (_isModelLoaded && _interpreter != null) {
        await _processCameraImage(null);
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  bool _isProcessingFrame = false;

  static Map<String, dynamic>? _isolateImageProcessing(Map<String, dynamic> params) {
    try {
      final CameraImage image = params['image'];
      img.Image? convertedImage;

      if (image.format.group == ImageFormatGroup.yuv420) {
        final int width = image.width;
        final int height = image.height;
        final int uvRowStride = image.planes[1].bytesPerRow;
        final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

        convertedImage = img.Image(width: width, height: height);

        for (int y = 0; y < height; y++) {
          int pY = y * image.planes[0].bytesPerRow;
          int pUV = (y >> 1) * uvRowStride;

          for (int x = 0; x < width; x++) {
            final int uvOffset = pUV + (x >> 1) * uvPixelStride;

            if (pY < image.planes[0].bytes.length &&
                uvOffset < image.planes[1].bytes.length &&
                uvOffset < image.planes[2].bytes.length) {
              final int yp = image.planes[0].bytes[pY];
              final int up = image.planes[1].bytes[uvOffset];
              final int vp = image.planes[2].bytes[uvOffset];

              int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
              int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
                  .round()
                  .clamp(0, 255);
              int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

              convertedImage.setPixelRgb(x, y, r, g, b);
            }
            pY++;
          }
        }
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        convertedImage = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
      }

      if (convertedImage != null) {
        // 이미지를 90도 회전 (카메라가 세로 모드이므로)
        convertedImage = img.copyRotate(convertedImage, angle: 90);
        debugPrint("After rotation: ${convertedImage.width}x${convertedImage.height}");
        
        // 4:3 비율로 크롭 (640x480 - 가로로 긴 이미지)
        int targetWidth = 640;
        int targetHeight = 480;
        
        // 중앙 기준으로 크롭
        double scaleW = convertedImage.width / targetWidth;
        double scaleH = convertedImage.height / targetHeight;
        double scale = scaleW < scaleH ? scaleW : scaleH;
        
        int cropWidth = (targetWidth * scale).round();
        int cropHeight = (targetHeight * scale).round();
        int cropOffsetX = (convertedImage.width - cropWidth) ~/ 2;
        int cropOffsetY = (convertedImage.height - cropHeight) ~/ 2;
        
        debugPrint("Cropping: offset=($cropOffsetX, $cropOffsetY), size=${cropWidth}x$cropHeight");
        convertedImage = img.copyCrop(convertedImage, 
            x: cropOffsetX, y: cropOffsetY, width: cropWidth, height: cropHeight);
        debugPrint("After crop: ${convertedImage.width}x${convertedImage.height}");
        
        // 640x480으로 리사이즈
        convertedImage = img.copyResize(convertedImage, width: targetWidth, height: targetHeight);
        debugPrint("After resize: ${convertedImage.width}x${convertedImage.height}");
        
        return {
          'image': convertedImage,
          'cropOffsetX': cropOffsetX,
          'cropOffsetY': cropOffsetY,
          'cropWidth': cropWidth,
          'cropHeight': cropHeight,
        };
      }
    } catch (e) {
      debugPrint("Isolate conversion error: $e");
    }
    return null;
  }

  Future<void> _processCameraImage(CameraImage? image) async {
    if (_interpreter == null || _isProcessingFrame) return;

    _isProcessingFrame = true;

    try {
      final Size screenSize = MediaQuery.of(context).size;
      double rawX = screenSize.width / 2;
      double rawY = screenSize.height / 2;
      bool personDetected = false;

      if (image != null) {
        final result = await compute(_isolateImageProcessing, {
          'image': image,
        });

        if (result != null) {
          final img.Image resized = result['image'];
          final int cropOffsetX = result['cropOffsetX'];
          final int cropOffsetY = result['cropOffsetY'];
          
          debugPrint("Image processed: cropOffsetX=$cropOffsetX, cropOffsetY=$cropOffsetY");
          debugPrint("Final image size: ${resized.width}x${resized.height}");
          
          // 640x480 입력 텐서 생성
          // TFLite 형식: batch x height x width x channels
          // 하지만 YOLO는 width x height 순서를 사용할 수 있음
          var input = List.generate(
            1,
            (i) => List.generate(
              640,  // 첫 번째 차원
              (j) => List.generate(480, (k) => List.filled(3, 0.0)),  // 두 번째 차원
            ),
          );
          
          // 이미지 크기 검증
          if (resized.width != 640 || resized.height != 480) {
            debugPrint("ERROR: Image size mismatch! Expected 640x480, got ${resized.width}x${resized.height}");
            return;
          }
          
          for (int y = 0; y < 480; y++) {
            for (int x = 0; x < 640; x++) {
              final pixel = resized.getPixel(x, y);
              input[0][x][y][0] = pixel.r / 255.0;
              input[0][x][y][1] = pixel.g / 255.0;
              input[0][x][y][2] = pixel.b / 255.0;
            }
          }

          var output = List.generate(
            1,
            (i) => List.generate(56, (j) => List.filled(6300, 0.0)),
          );

          try {
            _interpreter!.run(input, output);
            debugPrint("Inference complete");
          } catch (e) {
            debugPrint("Inference Error: $e");
            return;
          }

          double bestScore = -double.infinity;
          int bestAnchor = -1;
          final double frameCenterX = 320;  // 640 / 2
          final double frameCenterY = 240;  // 480 / 2

          for (int a = 0; a < 6300; a++) {
            double conf = output[0][4][a];
            if (conf > 0.5) {
              double cx = output[0][0][a];
              double cy = output[0][1][a];
              double w = output[0][2][a];
              double h = output[0][3][a];

              double area = w * h;
              double distToCenter = sqrt(
                pow(cx - frameCenterX, 2) + pow(cy - frameCenterY, 2),
              );
              double score = area / (distToCenter + 1e-6);

              if (score > bestScore) {
                bestScore = score;
                bestAnchor = a;
              }
            }
          }

          if (bestAnchor != -1) {
            personDetected = true;
            
            debugPrint("Person detected at anchor $bestAnchor with score $bestScore");

            // YOLO 출력은 정규화된 좌표 (0~1 범위)
            // 이미지를 90도 회전시켰으므로 좌표도 변환 필요
            double cxNorm = output[0][0][bestAnchor];
            double cyNorm = output[0][1][bestAnchor];
            double wNorm = output[0][2][bestAnchor];
            double hNorm = output[0][3][bestAnchor];
            
            // 90도 회전 변환: (x, y) → (y, 1 - x)
            double cx = cyNorm * 640;
            double cy = (1 - cxNorm) * 480;
            double w = hNorm * 640;  // width와 height도 스왑
            double h = wNorm * 480;
            
            debugPrint("BBox (pixels): cx=$cx, cy=$cy, w=$w, h=$h");

            // 화면 비율 계산
            double scaleX = screenSize.width / 640;
            double scaleY = screenSize.height / 480;
            
            // 바운딩 박스 좌표 변환
            double boxLeft = (cx - w / 2) * scaleX;
            double boxTop = (cy - h / 2) * scaleY;
            double boxRight = (cx + w / 2) * scaleX;
            double boxBottom = (cy + h / 2) * scaleY;

            Rect boundingBox = Rect.fromLTRB(
              boxLeft.clamp(0, screenSize.width),
              boxTop.clamp(0, screenSize.height),
              boxRight.clamp(0, screenSize.width),
              boxBottom.clamp(0, screenSize.height),
            );

            double targetX = cx;
            double targetY = (cy - h / 2) + (h * 0.2);
            String keypointMethod = "head_box";

            // 코 키포인트 확인 (인덱스 0)
            double noseConf = output[0][5 + 2][bestAnchor];
            debugPrint("Keypoints (normalized): nose_x=${output[0][5][bestAnchor]}, nose_y=${output[0][6][bestAnchor]}, nose_conf=$noseConf");
            
            if (noseConf > 0.5) {
              // 정규화된 좌표를 픽셀 좌표로 변환
              // 이미지를 90도 회전시켰으므로 좌표도 변환 필요
              // 원본 (x_norm, y_norm) → 회전 후 (y_norm * 640, (1 - x_norm) * 480)
              double noseXNorm = output[0][5][bestAnchor];
              double noseYNorm = output[0][6][bestAnchor];
              
              // 90도 회전 변환: (x, y) → (y, width - x)
              targetX = noseYNorm * 640;
              targetY = (1 - noseXNorm) * 480;
              keypointMethod = "nose";
            } else {
              // 얼굴 키포인트 평균 (눈, 귀)
              List<double> faceX = [];
              List<double> faceY = [];
              for (int k = 1; k <= 4; k++) {
                int baseIdx = 5 + k * 3;
                double kpConf = output[0][baseIdx + 2][bestAnchor];
                if (kpConf > 0.5) {
                  double xNorm = output[0][baseIdx][bestAnchor];
                  double yNorm = output[0][baseIdx + 1][bestAnchor];
                  
                  // 90도 회전 변환
                  faceX.add(yNorm * 640);
                  faceY.add((1 - xNorm) * 480);
                }
              }
              if (faceX.isNotEmpty) {
                targetX = faceX.reduce((a, b) => a + b) / faceX.length;
                targetY = faceY.reduce((a, b) => a + b) / faceY.length;
                keypointMethod = "face_avg(${faceX.length})";
              }
            }

            // 최종 화면 좌표
            rawX = targetX * scaleX;
            rawY = targetY * scaleY;
            
            // 디버그 정보 저장
            if (mounted) {
              setState(() {
                _personBoundingBox = boundingBox;
                _rawX640 = targetX;
                _rawY640 = targetY;
                _debugInfo = "Method: $keypointMethod\n"
                    "Nose conf: ${noseConf.toStringAsFixed(2)}\n"
                    "640x480 coords: (${targetX.toInt()}, ${targetY.toInt()})\n"
                    "Screen: (${rawX.toInt()}, ${rawY.toInt()})\n"
                    "BBox: (${cx.toInt()}, ${cy.toInt()}, ${w.toInt()}x${h.toInt()})";
              });
            }
          }
        }
      }

      if (!personDetected && image == null) {
        rawX = screenSize.width / 2 +
            sin(DateTime.now().millisecondsSinceEpoch / 1000) * 100;
        rawY = screenSize.height / 2 +
            cos(DateTime.now().millisecondsSinceEpoch / 1300) * 150;
        personDetected = true;
      }

      if (personDetected) {
        Point<int> smoothed = _stabilizer.update(rawX, rawY);
        var targetInfo = _stabilizer.getStickyTarget(
          _coach.intersections,
          screenSize.width.toInt(),
        );

        if (mounted) {
          setState(() {
            _smoothPos = smoothed;
            _targetPos = targetInfo['point'];
            _isPerfect = targetInfo['point'] != null
                ? _coach.isPerfect(targetInfo['distance'])
                : false;
          });
        }
      } else {
        _stabilizer.reset();
        if (mounted) {
          setState(() {
            _smoothPos = null;
            _targetPos = null;
            _isPerfect = false;
            _personBoundingBox = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Inference Error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_screenError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              _screenError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_isModelLoaded ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 카메라 프리뷰
          CameraPreview(_controller!),

          // 2. 3분할법 가이드 및 UI 렌더링
          CustomPaint(
            painter: RuleOfThirdsPainter(
              coach: _coach,
              currentSubjectPos: _smoothPos,
              targetPos: _targetPos,
              isPerfect: _isPerfect,
              personBoundingBox: _personBoundingBox,
            ),
          ),

          // 3. 상태 표시 텍스트
          Positioned(
            top: 50,
            left: 20,
            child: Text(
              _isPerfect ? "PERFECT 구도입니다!" : "타겟을 향해 카메라를 이동하세요",
              style: TextStyle(
                color: _isPerfect ? Colors.greenAccent : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),

          // 4. 뒤로가기 버튼
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          
          // 5. 디버그 정보
          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _debugInfo,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
