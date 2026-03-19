import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'package:flutter/services.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';

List<CameraDescription> cameras = [];

// ---------------------------------------------------------
// 1. MathStabilizer
// ---------------------------------------------------------
class MathStabilizer {
  final double alpha;
  final double stickyMarginRatio;

  double? smoothedX;
  double? smoothedY;
  math.Point<int>? currentBestPoint;

  MathStabilizer({this.alpha = 0.25, this.stickyMarginRatio = 0.08});

  math.Point<int> update(double rawX, double rawY) {
    if (smoothedX == null || smoothedY == null) {
      smoothedX = rawX;
      smoothedY = rawY;
    } else {
      smoothedX = smoothedX! * (1 - alpha) + rawX * alpha;
      smoothedY = smoothedY! * (1 - alpha) + rawY * alpha;
    }
    return math.Point<int>(smoothedX!.toInt(), smoothedY!.toInt());
  }

  Map<String, dynamic> getStickyTarget(
    List<math.Point<int>> intersections,
    int screenWidth,
  ) {
    if (smoothedX == null || smoothedY == null || intersections.isEmpty) {
      return {'point': null, 'distance': double.infinity};
    }

    if (currentBestPoint == null) {
      double minDist = double.infinity;
      for (var p in intersections) {
        double dist = math.sqrt(
          math.pow(smoothedX! - p.x, 2) + math.pow(smoothedY! - p.y, 2),
        );
        if (dist < minDist) {
          minDist = dist;
          currentBestPoint = p;
        }
      }
    } else {
      double currDist = math.sqrt(
        math.pow(smoothedX! - currentBestPoint!.x, 2) +
            math.pow(smoothedY! - currentBestPoint!.y, 2),
      );
      double stickyMargin = screenWidth * stickyMarginRatio;
      for (var p in intersections) {
        double newDist = math.sqrt(
          math.pow(smoothedX! - p.x, 2) + math.pow(smoothedY! - p.y, 2),
        );
        if (newDist < currDist - stickyMargin) {
          currentBestPoint = p;
          currDist = newDist;
        }
      }
    }

    double finalDist = math.sqrt(
      math.pow(smoothedX! - currentBestPoint!.x, 2) +
          math.pow(smoothedY! - currentBestPoint!.y, 2),
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
// 2. GoldenCoach
// ---------------------------------------------------------
class GoldenCoach {
  static const double perfectThresholdRatio = 0.1;
  static const double phi = 1.6180339887;
  static const double ratio = 1 / phi;

  int width = 0;
  int height = 0;
  List<math.Point<int>> intersections = [];

  void calculateGrid(int screenWidth, int screenHeight) {
    width = screenWidth;
    height = screenHeight;

    double xr3 = width.toDouble(), xl3 = 0, yt3 = 0, yb3 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr3 - xl3, h = yb3 - yt3;
      int dir = i % 4;
      if (dir == 0)
        xl3 += w * ratio;
      else if (dir == 1)
        yt3 += h * ratio;
      else if (dir == 2)
        xr3 -= w * ratio;
      else
        yb3 -= h * ratio;
    }

    double xr1 = width.toDouble(), xl1 = 0, yt1 = 0, yb1 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr1 - xl1, h = yb1 - yt1;
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

    double xr2 = width.toDouble(), xl2 = 0, yt2 = 0, yb2 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr2 - xl2, h = yb2 - yt2;
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

    double xr0 = width.toDouble(), xl0 = 0, yt0 = 0, yb0 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr0 - xl0, h = yb0 - yt0;
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
      math.Point<int>((xl0 + xr0) ~/ 2, (yt0 + yb0) ~/ 2),
      math.Point<int>((xl1 + xr1) ~/ 2, (yt1 + yb1) ~/ 2),
      math.Point<int>((xl2 + xr2) ~/ 2, (yt2 + yb2) ~/ 2),
      math.Point<int>((xl3 + xr3) ~/ 2, (yt3 + yb3) ~/ 2),
    ];
  }

  bool isPerfect(double distance) => distance < (width * perfectThresholdRatio);
}

// ---------------------------------------------------------
// 3. GoldenCoachPainter
// ---------------------------------------------------------
class GoldenCoachPainter extends CustomPainter {
  final GoldenCoach coach;
  final math.Point<int>? currentSubjectPos;
  final math.Point<int>? targetPos;
  final bool isPerfect;
  final Rect? personBoundingBox; // Kept for constructor compatibility but unused

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
      // 1. 나선형 방향 고정 (사람에 따라 팽글팽글 돌지 않도록 3번 인덱스로 완전 고정)
      int activeTargetIdx = 3;

      void drawSpiralArc(Rect rect, double startAngle, double sweepAngle) {
        canvas.drawArc(rect, startAngle, sweepAngle, false, spiralShadowPaint);
        canvas.drawArc(rect, startAngle, sweepAngle, false, spiralLinePaint);
      }

      void drawSpiralRect(Rect rect) {
        canvas.drawRect(rect, spiralShadowPaint);
        canvas.drawRect(rect, spiralLinePaint);
      }

      double xMin = 0, yMin = 0, xMax = size.width, yMax = size.height;
      double R = GoldenCoach.ratio;

      for (int i = 0; i < 8; i++) {
        double w = xMax - xMin, h = yMax - yMin;
        if (w <= 2 || h <= 2) break;

        int step = i % 4;
        int dir = 0;
        if (activeTargetIdx == 3)
          dir = step;
        else if (activeTargetIdx == 1)
          dir = [0, 3, 2, 1][step];
        else if (activeTargetIdx == 2)
          dir = [2, 1, 0, 3][step];
        else if (activeTargetIdx == 0)
          dir = [2, 3, 0, 1][step];

        if (dir == 0) {
          drawSpiralRect(Rect.fromLTRB(xMin, yMin, xMin + w * R, yMax));
          double cx = xMin + w * R;
          double cy = (activeTargetIdx == 3 || activeTargetIdx == 2)
              ? yMax
              : yMin;
          double startAngle = (activeTargetIdx == 3 || activeTargetIdx == 2)
              ? math.pi
              : math.pi / 2;
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * R * 2,
              height: h * 2,
            ),
            startAngle,
            math.pi / 2 * (activeTargetIdx <= 1 ? -1 : 1),
          );
          xMin += w * R;
        } else if (dir == 1) {
          drawSpiralRect(Rect.fromLTRB(xMin, yMin, xMax, yMin + h * R));
          double cx = (activeTargetIdx == 3 || activeTargetIdx == 1)
              ? xMin
              : xMax;
          double cy = yMin + h * R;
          double startAngle = (activeTargetIdx == 3 || activeTargetIdx == 1)
              ? -math.pi / 2
              : math.pi;
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * 2,
              height: h * R * 2,
            ),
            startAngle,
            math.pi /
                2 *
                (activeTargetIdx == 0 || activeTargetIdx == 3 ? 1 : -1),
          );
          yMin += h * R;
        } else if (dir == 2) {
          drawSpiralRect(Rect.fromLTRB(xMin + w * (1 - R), yMin, xMax, yMax));
          double cx = xMin + w * (1 - R);
          double cy = (activeTargetIdx == 3 || activeTargetIdx == 2)
              ? yMin
              : yMax;
          double startAngle = (activeTargetIdx == 3 || activeTargetIdx == 2)
              ? 0
              : -math.pi / 2;
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * R * 2,
              height: h * 2,
            ),
            startAngle,
            math.pi / 2 * (activeTargetIdx <= 1 ? -1 : 1),
          );
          xMax -= w * R;
        } else if (dir == 3) {
          drawSpiralRect(Rect.fromLTRB(xMin, yMin + h * (1 - R), xMax, yMax));
          double cx = (activeTargetIdx == 3 || activeTargetIdx == 1)
              ? xMax
              : xMin;
          double cy = yMin + h * (1 - R);
          double startAngle = (activeTargetIdx == 3 || activeTargetIdx == 1)
              ? math.pi / 2
              : 0;
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * 2,
              height: h * R * 2,
            ),
            startAngle,
            math.pi /
                2 *
                (activeTargetIdx == 0 || activeTargetIdx == 3 ? 1 : -1),
          );
          yMax -= h * R;
        }
      }
    }

    if (personBoundingBox != null) {
      final boxShadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      final boxPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(personBoundingBox!, boxShadowPaint);
      canvas.drawRect(personBoundingBox!, boxPaint);

      final tp = TextPainter(
        text: const TextSpan(
          text: "Person Detected",
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(personBoundingBox!.left, personBoundingBox!.top - 20),
      );
    }

    // 3. 타겟 유도선 그리기
    if (currentSubjectPos != null && targetPos != null) {
      Color stateColor = isPerfect ? Colors.greenAccent : Colors.amber;
      final connectionPaint = Paint()
        ..color = stateColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isPerfect ? 3.0 : 2.0;
      final subjectPaint = Paint()
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
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---------------------------------------------------------
// 4. GoldenRatioScreen
// ---------------------------------------------------------
class GoldenRatioScreen extends StatefulWidget {
  const GoldenRatioScreen({super.key});

  @override
  State<GoldenRatioScreen> createState() => _GoldenRatioScreenState();
}

class _GoldenRatioScreenState extends State<GoldenRatioScreen> {
  final MathStabilizer _stabilizer = MathStabilizer();
  final GoldenCoach _coach = GoldenCoach();

  // Screen State
  math.Point<int>? _smoothPos;
  math.Point<int>? _targetPos;
  bool _isPerfect = false;
  Rect? _personBoundingBox;

  // Capture State
  final GlobalKey _cameraKey = GlobalKey();
  bool _isCapturing = false;
  bool _showFlash = false;
  String _selectedMode = 'PHOTO';
  final List<String> _modes = ['CINEMATIC', 'VIDEO', 'PHOTO', 'PORTRAIT', 'PANO'];

  void _handleDetections(List<YOLOResult> results) {
    if (_isCapturing) return; // Ignore detections during capture
    
    debugPrint('YOLO Detections: ${results.length}');
    if (results.isEmpty) {
      _stabilizer.reset();
      setState(() {
        _smoothPos = null;
        _targetPos = null;
        _isPerfect = false;
        _personBoundingBox = null;
      });
      return;
    }

    YOLOResult bestPerson = results[0];
    double maxArea = 0;
    for (var r in results) {
      debugPrint(
        'Detected Box: ${r.className} [${r.confidence}] - Box: ${r.boundingBox}',
      );
      double area = r.normalizedBox.width * r.normalizedBox.height;
      if (area > maxArea) {
        maxArea = area;
        bestPerson = r;
      }
    }

    if (bestPerson.keypoints == null || bestPerson.keypoints!.isEmpty) {
      debugPrint('No Keypoints for best person!');
      return;
    }

    final Size screenSize = MediaQuery.of(context).size;
    final kps = bestPerson.keypoints!;
    debugPrint('Keypoints length: ${kps.length}');

    double imageWidth =
        bestPerson.boundingBox.width / bestPerson.normalizedBox.width;
    double imageHeight =
        bestPerson.boundingBox.height / bestPerson.normalizedBox.height;

    math.Point<double> toScreen(Point kp) {
      return math.Point<double>(
        (kp.x / imageWidth) * screenSize.width,
        (kp.y / imageHeight) * screenSize.height,
      );
    }

    double targetX = screenSize.width / 2;
    double targetY = screenSize.height / 2;

    if (kps.isNotEmpty) {
      var nose = toScreen(kps.length > 0 ? kps[0] : kps.first);
      targetX = nose.x;
      targetY = nose.y;
    }

    final double rawX = targetX;
    final double rawY = targetY;

    final Rect screenBBox = Rect.fromLTRB(
      bestPerson.normalizedBox.left * screenSize.width,
      bestPerson.normalizedBox.top * screenSize.height,
      bestPerson.normalizedBox.right * screenSize.width,
      bestPerson.normalizedBox.bottom * screenSize.height,
    );

    final smoothed = _stabilizer.update(rawX, rawY);
    final targetInfo = _stabilizer.getStickyTarget(
      _coach.intersections,
      screenSize.width.toInt(),
    );

    setState(() {
      _smoothPos = smoothed;
      _targetPos = targetInfo['point'];
      _isPerfect = targetInfo['point'] != null
          ? _coach.isPerfect(targetInfo['distance'])
          : false;
      _personBoundingBox = screenBBox;
    });
  }

  Future<void> _takePhoto() async {
    if (_isCapturing) return;

    // 1. Hide guidelines
    setState(() {
      _isCapturing = true;
    });

    // 2. Wait a tick for the UI to rebuild without guidelines
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      // 3. Request permissions for saving to gallery
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final request = await Gal.requestAccess();
        if (!request) return; // Did not grant permission
      }

      // 4. Capture the RepaintBoundary
      RenderRepaintBoundary boundary =
          _cameraKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        Uint8List pngBytes = byteData.buffer.asUint8List();
        // 5. Save to gallery
        await Gal.putImageBytes(pngBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사진이 갤러리에 저장되었습니다!')),
          );
        }
      }
    } catch (e) {
      debugPrint("Capture error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진 저장 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      // 6. Show flash effect and restore guidelines
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _showFlash = true;
        });

        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            setState(() {
              _showFlash = false;
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Foreground/Background
          RepaintBoundary(
            key: _cameraKey,
            child: YOLOView(
              modelPath: 'yolov8n-pose_float16.tflite',
              task: YOLOTask.pose,
              useGpu: false,
              streamingConfig: const YOLOStreamingConfig.withPoses(),
              showOverlays: false, // Permanently disable Native YOLO lines
              onResult: _handleDetections,
            ),
          ),
          
          // 2. AI Guideline Overlays
          if (!_isCapturing)
            CustomPaint(
              painter: GoldenCoachPainter(
                coach: _coach,
                currentSubjectPos: _smoothPos,
                targetPos: _targetPos,
                isPerfect: _isPerfect,
                personBoundingBox: _personBoundingBox,
              ),
            ),
            
          if (!_isCapturing && _isPerfect)
            Positioned(
              top: 100,
              left: 20,
              child: const Text(
                "PERFECT!",
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),

          if (!_isCapturing)
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
            
          // 3. iPhone Style Top & Bottom Controls
          if (!_isCapturing)
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   _buildTopControls(),
                   _buildBottomControls(),
                ],
              ),
            ),

          // 4. White Flash Effect
          if (_showFlash)
            Container(color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(Icons.flash_off, color: Colors.white, size: 24),
          const Icon(Icons.nightlight_round, color: Colors.white54, size: 24),
          Icon(Icons.keyboard_arrow_up, color: Colors.white.withOpacity(0.8), size: 24),
          const Icon(Icons.hdr_auto, color: Colors.white54, size: 24),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      color: Colors.black.withOpacity(0.4),
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode Selector
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 30),
              children: _modes.map((mode) => _buildModeText(mode)).toList(),
            ),
          ),
          
          const SizedBox(height: 15),

          // Main Bottom Buttons (Gallery, Shutter, Switch Camera)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gallery Thumbnail Placeholder
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                ),

                // Shutter Button
                GestureDetector(
                  onTap: _takePhoto,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3.5),
                    ),
                    child: Center(
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),

                // Switch Camera Button
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.flip_camera_ios,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeText(String text) {
    final bool isSelected = _selectedMode == text;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMode = text;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? const Color(0xFFFFD50B) : Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontFamily: 'SF Compact',
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

