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

class RuleOfThirdsCoach {
  static const double perfectThresholdRatio = 0.1;
  int width = 0, height = 0, x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  List<math.Point<int>> intersections = [];

  void calculateGrid(int screenWidth, int screenHeight) {
    width = screenWidth;
    height = screenHeight;
    x1 = width ~/ 3;
    x2 = (width * 2) ~/ 3;
    y1 = height ~/ 3;
    y2 = (height * 2) ~/ 3;
    intersections = [
      math.Point<int>(x1, y1),
      math.Point<int>(x2, y1),
      math.Point<int>(x1, y2),
      math.Point<int>(x2, y2),
    ];
  }

  bool isPerfect(double distance) => distance < (width * perfectThresholdRatio);
}

class RuleOfThirdsPainter extends CustomPainter {
  final RuleOfThirdsCoach coach;
  final math.Point<int>? currentSubjectPos;
  final math.Point<int>? targetPos;
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
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
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
    final iPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    for (var p in coach.intersections) {
      canvas.drawCircle(Offset(p.x.toDouble(), p.y.toDouble()), 4.0, iPaint);
    }

    if (personBoundingBox != null) {
      canvas.drawRect(
        personBoundingBox!,
        Paint()
          ..color = Colors.black.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
      canvas.drawRect(
        personBoundingBox!,
        Paint()
          ..color = Colors.cyanAccent.withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
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

    if (currentSubjectPos != null && targetPos != null) {
      Color c = isPerfect ? Colors.greenAccent : Colors.amber;
      canvas.drawLine(
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPerfect ? 3.0 : 2.0,
      );
      canvas.drawCircle(
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        isPerfect ? 8.0 : 6.0,
        Paint()
          ..color = isPerfect ? Colors.greenAccent : Colors.redAccent
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        8.0,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPerfect ? 3.0 : 2.0,
      );
      if (isPerfect) {
        final tp = TextPainter(
          text: const TextSpan(
            text: "PERFECT!",
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, const Offset(20, 100));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class RuleOfThirdsScreen extends StatefulWidget {
  const RuleOfThirdsScreen({super.key});
  @override
  State<RuleOfThirdsScreen> createState() => _RuleOfThirdsScreenState();
}

class _RuleOfThirdsScreenState extends State<RuleOfThirdsScreen> {
  final MathStabilizer _stabilizer = MathStabilizer();
  final RuleOfThirdsCoach _coach = RuleOfThirdsCoach();
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
    
    debugPrint('YOLO Third Detections: ${results.length}');
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
              painter: RuleOfThirdsPainter(
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

