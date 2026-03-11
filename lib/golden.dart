import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

// golden.dart에서 사용할 전역 변수
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
// 2. GoldenCoach (Python의 GoldenCoach 포팅)
// ---------------------------------------------------------
class GoldenCoach {
  static const double perfectThresholdRatio = 0.1;
  static const double phi = 1.6180339887;
  static const double ratio = 1 / phi; // 0.618
  static const double invRatio = 1 - ratio; // 0.382

  int width = 0;
  int height = 0;

  List<Point<int>> intersections = [];
  int activeTargetIdx = 3;

  void calculateGrid(int screenWidth, int screenHeight) {
    width = screenWidth;
    height = screenHeight;

    // The exact vortex (pole) of a golden spiral in a rectangle of W x H
    // is the intersection of the main diagonal and the diagonal of the first cut square.
    // For a spiral converging to the Bottom-Right (activeTargetIdx = 3):
    // Vortex X = W * (phi + 1) / (2 * phi + 1)  (~0.618 W)
    // Vortex Y = H * phi / (2 * phi + 1)        (~0.382 H)  WAIT, if it's Bottom-Right, Y is ~0.618 H?

    // Actually, the simple 1:1.618 ratio *is* mathematically the exact vortex for a true golden rectangle.
    // For a 16:9 screen, it's slightly squashed but the code draws proportional squares.
    // Let's stick to the drawn spiral's exact convergence point.
    // The previous intersections were [x1, y1], [x2, y1], [x1, y2], [x2, y2]
    // which corresponds to ~38.2% and 61.8%.

    // Let's refine the intersections so they exactly match where the 8-arc spiral ends.
    // We already use RATIO (0.618) and INV_RATIO (0.382) to draw the arcs.
    // The spiral arcs converge EXACTLY at the intersections defined below IF the screen was a golden rectangle.
    // If not, the arcs still converge very close to these points.

    // To make sure the target line perfectly hits the "eye" of the spiral,
    // we trace the mathematical center of the spiral based on the 8 loops.
    // For Bottom-Right (3):
    double xr3 = width.toDouble(), xl3 = 0, yt3 = 0, yb3 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr3 - xl3;
      double h = yb3 - yt3;
      int dir = i % 4; // L, T, R, B
      if (dir == 0)
        xl3 += w * ratio;
      else if (dir == 1)
        yt3 += h * ratio;
      else if (dir == 2)
        xr3 -= w * ratio;
      else
        yb3 -= h * ratio;
    }

    // For Top-Right (1): (dir = 0, 3, 2, 1)
    double xr1 = width.toDouble(), xl1 = 0, yt1 = 0, yb1 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr1 - xl1;
      double h = yb1 - yt1;
      int dir = [0, 3, 2, 1][i % 4];
      if (dir == 0)
        xl1 += w * ratio;
      else if (dir == 1)
        yt1 += h * ratio;
      else if (dir == 2)
        xr1 -= w * ratio;
      else
        yb1 -= h * ratio;
    }

    // For Bottom-Left (2): (dir = 2, 1, 0, 3)
    double xr2 = width.toDouble(), xl2 = 0, yt2 = 0, yb2 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr2 - xl2;
      double h = yb2 - yt2;
      int dir = [2, 1, 0, 3][i % 4];
      if (dir == 0)
        xl2 += w * ratio;
      else if (dir == 1)
        yt2 += h * ratio;
      else if (dir == 2)
        xr2 -= w * ratio;
      else
        yb2 -= h * ratio;
    }

    // For Top-Left (0): (dir = 2, 3, 0, 1)
    double xr0 = width.toDouble(), xl0 = 0, yt0 = 0, yb0 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr0 - xl0;
      double h = yb0 - yt0;
      int dir = [2, 3, 0, 1][i % 4];
      if (dir == 0)
        xl0 += w * ratio;
      else if (dir == 1)
        yt0 += h * ratio;
      else if (dir == 2)
        xr0 -= w * ratio;
      else
        yb0 -= h * ratio;
    }

    intersections = [
      Point<int>((xl0 + xr0) ~/ 2, (yt0 + yb0) ~/ 2), // 0: 좌상 정확한 소실점
      Point<int>((xl1 + xr1) ~/ 2, (yt1 + yb1) ~/ 2), // 1: 우상 정확한 소실점
      Point<int>((xl2 + xr2) ~/ 2, (yt2 + yb2) ~/ 2), // 2: 좌하 정확한 소실점
      Point<int>((xl3 + xr3) ~/ 2, (yt3 + yb3) ~/ 2), // 3: 우하 정확한 소실점
    ];
  }

  bool isPerfect(double distance) {
    return distance < (width * perfectThresholdRatio);
  }
}

// ---------------------------------------------------------
// 3. UI 렌더링 (CustomPainter)
// ---------------------------------------------------------
class GoldenCoachPainter extends CustomPainter {
  final GoldenCoach coach;
  final Point<int>? currentSubjectPos;
  final Point<int>? targetPos;
  final bool isPerfect;
  final Rect? personBoundingBox;

  GoldenCoachPainter({
    required this.coach,
    this.currentSubjectPos,
    this.targetPos,
    this.isPerfect = false,
    this.personBoundingBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    coach.calculateGrid(size.width.toInt(), size.height.toInt());

    final Paint spiralLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final Paint spiralShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (coach.intersections.isNotEmpty) {
      // Find which intersection is currently targeted, or default to bottom-right (idx 3)
      int activeTargetIdx = 3;
      if (targetPos != null) {
        for (int i = 0; i < coach.intersections.length; i++) {
          final pt = coach.intersections[i];
          if (pt.x == targetPos!.x && pt.y == targetPos!.y) {
            activeTargetIdx = i;
            break;
          }
        }
      }

      // Draw Fibonacci Spiral
      void drawSpiralArc(Rect rect, double startAngle, double sweepAngle) {
        canvas.drawArc(rect, startAngle, sweepAngle, false, spiralShadowPaint);
        canvas.drawArc(rect, startAngle, sweepAngle, false, spiralLinePaint);
      }

      void drawSpiralRect(Rect rect) {
        canvas.drawRect(rect, spiralShadowPaint);
        canvas.drawRect(rect, spiralLinePaint);
      }

      double xMin = 0;
      double yMin = 0;
      double xMax = size.width;
      double yMax = size.height;
      double R = GoldenCoach.ratio; // 0.6180339887

      // We determine the initial direction based on the active target corner
      // 0: top-left, 1: top-right, 2: bottom-left, 3: bottom-right(default)

      // We will loop 8 times to draw the fibonacci spiral into the vortex
      for (int i = 0; i < 8; i++) {
        double w = xMax - xMin;
        double h = yMax - yMin;
        if (w <= 2 || h <= 2) break;

        // The pattern of splitting the rect depends on which corner the vortex is in.
        // For Bottom-Right (3): Left, Top, Right, Bottom
        // For Top-Right (1): Left, Bottom, Right, Top
        // For Bottom-Left (2): Right, Top, Left, Bottom
        // For Top-Left (0): Right, Bottom, Left, Top

        int step = i % 4;

        // Define direction based on active target index
        int dir = 0; // 0:Left, 1:Top, 2:Right, 3:Bottom
        if (activeTargetIdx == 3) {
          dir = step;
        } else if (activeTargetIdx == 1) {
          dir = [0, 3, 2, 1][step];
        } else if (activeTargetIdx == 2) {
          dir = [2, 1, 0, 3][step];
        } else if (activeTargetIdx == 0) {
          dir = [2, 3, 0, 1][step];
        }

        if (dir == 0) {
          // Split Left
          Rect r = Rect.fromLTRB(xMin, yMin, xMin + w * R, yMax);
          drawSpiralRect(r);
          // center is at (xMin + w*R, yMax) if converging BR (idx=3) or TR (idx=1)
          // Wait, the center of the arc depends on the vortex!
          // We can simplify by drawing standard arcs based on dir:

          double cx, cy, startAngle;
          if (activeTargetIdx == 3 || activeTargetIdx == 2) {
            // going down
            cx = xMin + w * R;
            cy = yMax;
            startAngle = pi;
          } else {
            // going up
            cx = xMin + w * R;
            cy = yMin;
            startAngle = pi / 2;
          }
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * R * 2,
              height: h * 2,
            ),
            startAngle,
            pi / 2 * (activeTargetIdx <= 1 ? -1 : 1),
          );

          xMin += w * R;
        } else if (dir == 1) {
          // Split Top
          Rect r = Rect.fromLTRB(xMin, yMin, xMax, yMin + h * R);
          drawSpiralRect(r);

          double cx, cy, startAngle;
          if (activeTargetIdx == 3 || activeTargetIdx == 1) {
            cx = xMin;
            cy = yMin + h * R;
            startAngle = -pi / 2;
          } else {
            cx = xMax;
            cy = yMin + h * R;
            startAngle = pi;
          }
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * 2,
              height: h * R * 2,
            ),
            startAngle,
            pi / 2 * (activeTargetIdx == 0 || activeTargetIdx == 3 ? 1 : -1),
          );

          yMin += h * R;
        } else if (dir == 2) {
          // Split Right
          Rect r = Rect.fromLTRB(xMin + w * (1 - R), yMin, xMax, yMax);
          drawSpiralRect(r);

          double cx, cy, startAngle;
          if (activeTargetIdx == 3 || activeTargetIdx == 2) {
            cx = xMin + w * (1 - R);
            cy = yMin;
            startAngle = 0;
          } else {
            cx = xMin + w * (1 - R);
            cy = yMax;
            startAngle = -pi / 2;
          }

          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * R * 2,
              height: h * 2,
            ),
            startAngle,
            pi / 2 * (activeTargetIdx <= 1 ? -1 : 1),
          );

          xMax -= w * R;
        } else if (dir == 3) {
          // Split Bottom
          Rect r = Rect.fromLTRB(xMin, yMin + h * (1 - R), xMax, yMax);
          drawSpiralRect(r);

          double cx, cy, startAngle;
          if (activeTargetIdx == 3 || activeTargetIdx == 1) {
            cx = xMax;
            cy = yMin + h * (1 - R);
            startAngle = pi / 2;
          } else {
            cx = xMin;
            cy = yMin + h * (1 - R);
            startAngle = 0;
          }

          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * 2,
              height: h * R * 2,
            ),
            startAngle,
            pi / 2 * (activeTargetIdx == 0 || activeTargetIdx == 3 ? 1 : -1),
          );

          yMax -= h * R;
        }
      } // end of for-loop (spiral drawing)
    } // end of intersections check

    // Texts (38.2% / 61.8%)
    const textStyle = TextStyle(
      color: Colors.white70,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
    );
    void drawText(String text, Offset position) {
      final textPainter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, position);
    }

    if (coach.intersections.isNotEmpty) {
      // 0: Top-Left, 1: Top-Right, 2: Bottom-Left, 3: Bottom-Right
      drawText(
        "Vortex",
        Offset(
          coach.intersections[0].x.toDouble() + 5,
          coach.intersections[0].y.toDouble() + 5,
        ),
      );
      drawText(
        "Vortex",
        Offset(
          coach.intersections[1].x.toDouble() - 45,
          coach.intersections[1].y.toDouble() + 5,
        ),
      );
      drawText(
        "Vortex",
        Offset(
          coach.intersections[2].x.toDouble() + 5,
          coach.intersections[2].y.toDouble() - 20,
        ),
      );
      drawText(
        "Vortex",
        Offset(
          coach.intersections[3].x.toDouble() - 45,
          coach.intersections[3].y.toDouble() - 20,
        ),
      );
    }

    // 바운딩 박스 그리기 (사람 감지 확인용)
    if (personBoundingBox != null) {
      final Paint boxPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final Paint boxShadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      // 그림자 효과
      canvas.drawRect(personBoundingBox!, boxShadowPaint);
      // 실제 박스
      canvas.drawRect(personBoundingBox!, boxPaint);

      // 박스 상단에 "Person Detected" 텍스트
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
        Offset(
          personBoundingBox!.left,
          personBoundingBox!.top - 20,
        ),
      );
    }

    // 타겟과 피사체 연결 선 및 마커
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
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        connectionPaint,
      );

      canvas.drawCircle(
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        isPerfect ? 8.0 : 6.0,
        subjectPaint,
      );
      canvas.drawCircle(
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        8.0,
        connectionPaint,
      );

      if (isPerfect) {
        drawText("PERFECT!", const Offset(20, 100));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---------------------------------------------------------
// 4. Golden Ratio Screen (황금비 코칭 화면)
// ---------------------------------------------------------
class GoldenRatioScreen extends StatefulWidget {
  const GoldenRatioScreen({super.key});

  @override
  State<GoldenRatioScreen> createState() => _GoldenRatioScreenState();
}

class _GoldenRatioScreenState extends State<GoldenRatioScreen> {
  CameraController? _controller;
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  bool _isDetecting = false;
  String? _screenError;

  final MathStabilizer _stabilizer = MathStabilizer();
  final GoldenCoach _coach = GoldenCoach();

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
    _controller!
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});

          if (Theme.of(context).platform == TargetPlatform.windows ||
              Theme.of(context).platform == TargetPlatform.macOS ||
              Theme.of(context).platform == TargetPlatform.linux) {
            // Windows 등 데스크톱에서는 startImageStream 미지원 -> 가상 타이머로 대체
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
        })
        .catchError((e) {
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
        // Run dummy process image
        await _processCameraImage(null);
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  bool _isProcessingFrame = false;

  // Must be static or top-level for compute()
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
        
        convertedImage = img.copyCrop(convertedImage, 
            x: cropOffsetX, y: cropOffsetY, width: cropWidth, height: cropHeight);
        
        // 640x480으로 리사이즈
        convertedImage = img.copyResize(convertedImage, width: targetWidth, height: targetHeight);
        
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
        // Run heavy image conversion in isolate
        final result = await compute(_isolateImageProcessing, {
          'image': image,
        });

        if (result != null) {
          final img.Image resized = result['image'];
          final int cropOffsetX = result['cropOffsetX'];
          final int cropOffsetY = result['cropOffsetY'];
          final int cropSize = result['cropSize'];
          
          // 640x480 입력 텐서 생성
          // TFLite 형식: batch x height x width x channels
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

          _interpreter!.run(input, output);

          double bestScore = -double.infinity;
          int bestAnchor = -1;
          final double frameCenterX = 320;
          final double frameCenterY = 240;

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
            
            // YOLO 출력은 정규화된 좌표 (0~1 범위)
            // 이미지를 90도 회전시켰으므로 좌표도 변환 필요
            double cxNorm = output[0][0][bestAnchor];
            double cyNorm = output[0][1][bestAnchor];
            double wNorm = output[0][2][bestAnchor];
            double hNorm = output[0][3][bestAnchor];
            
            // 90도 회전 변환: (x, y) → (y, 1 - x)
            double cx = cyNorm * 640;
            double cy = (1 - cxNorm) * 480;
            double w = hNorm * 640;
            double h = wNorm * 480;
            
            // 화면 비율 계산
            double scaleX = screenSize.width / 640;
            double scaleY = screenSize.height / 480;
            
            // 바운딩 박스 좌표 변환
            double boxLeft = (cx - w / 2) * scaleX;
            double boxTop = (cy - h / 2) * scaleY;
            double boxRight = (cx + w / 2) * scaleX;
            double boxBottom = (cy + h / 2) * scaleY;
            
            // 바운딩 박스 저장
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
            if (noseConf > 0.5) {
              // 정규화된 좌표를 픽셀 좌표로 변환
              // 이미지를 90도 회전시켰으므로 좌표도 변환 필요
              double noseXNorm = output[0][5][bestAnchor];
              double noseYNorm = output[0][6][bestAnchor];
              
              // 90도 회전 변환: (x, y) → (y, 1 - x)
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
            
            // 바운딩 박스와 디버그 정보를 상태에 저장
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
        rawX =
            screenSize.width / 2 +
            sin(DateTime.now().millisecondsSinceEpoch / 1000) * 100;
        rawY =
            screenSize.height / 2 +
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

          // 2. 황금비율 가이드 및 UI 렌더링
          CustomPaint(
            painter: GoldenCoachPainter(
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
