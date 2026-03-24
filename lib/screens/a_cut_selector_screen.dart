import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/scored_image.dart';
import '../services/inference_service.dart';
import '../services/scoring_service.dart';

class ACutSelectorScreen extends StatefulWidget {
  const ACutSelectorScreen({super.key});

  @override
  State<ACutSelectorScreen> createState() => _ACutSelectorScreenState();
}

class _ACutSelectorScreenState extends State<ACutSelectorScreen> {
  final ImagePicker _picker = ImagePicker();
  late ScoringService _scoringService;
  
  List<ScoredImage> _results = [];
  bool _isProcessing = false;
  double _progress = 0.0;
  int _totalImages = 0;
  int _processedImages = 0;
  
  String _selectedMode = '자동';
  final List<String> _modes = ['인물', '스냅', '자동'];

  @override
  void initState() {
    super.initState();
    // Initialize with Aesthetic service
    _scoringService = ScoringService(NimaAestheticService());
    _scoringService.init().catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('모델 로드 실패: $e')),
        );
      }
    });
  }

  @override
  void dispose() {
    _scoringService.dispose();
    super.dispose();
  }

  Future<void> _pickAndProcessImages() async {
    final List<XFile>? images = await _picker.pickMultiImage();
    
    if (images == null || images.isEmpty) return;

    setState(() {
      _results = [];
      _isProcessing = true;
      _totalImages = images.length;
      _processedImages = 0;
      _progress = 0.0;
    });

    final files = images.map((xFile) => File(xFile.path)).toList();

    try {
      final results = await _scoringService.processImages(
        files,
        onProgress: (count) {
          setState(() {
            _processedImages = count;
            _progress = count / _totalImages;
          });
        },
      );

      setState(() {
        _results = results;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('처리 중 오류 발생: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI A컷 셀렉터'),
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: Column(
          children: [
            _buildModeSelector(),
            if (_isProcessing) _buildLoadingView(),
            if (!_isProcessing && _results.isEmpty) _buildEmptyView(),
            if (!_isProcessing && _results.isNotEmpty) Expanded(child: _buildResultsGrid()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _pickAndProcessImages,
        label: Text(_isProcessing ? '처리 중...' : '사진 선택하기'),
        icon: const Icon(Icons.add_photo_alternate),
        backgroundColor: Colors.deepPurpleAccent,
      ),
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _modes.map((mode) {
          bool isSelected = _selectedMode == mode;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ChoiceChip(
              label: Text(mode),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) setState(() => _selectedMode = mode);
              },
              selectedColor: Colors.deepPurpleAccent,
              labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
              backgroundColor: Colors.white10,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.deepPurpleAccent),
            const SizedBox(height: 24),
            Text(
              'AI가 사진을 분석하고 있습니다...\n($_processedImages / $_totalImages)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48.0),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white10,
                color: Colors.deepPurpleAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 80, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 16),
            const Text(
              '여러 장의 사진을 선택하면\nAI가 베스트 컷을 골라줍니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return _buildResultCard(item);
      },
    );
  }

  Widget _buildResultCard(ScoredImage item) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF0F3460),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: item.isACut 
            ? const BorderSide(color: Colors.amber, width: 2) 
            : BorderSide.none,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(item.file, fit: BoxFit.cover),
          if (item.hasError)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              ),
            ),
          // Gradient Overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
          ),
          // Rank & Score
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '#${item.rank}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  item.aestheticScore.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // A-Cut Badge
          if (item.isACut)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'A-CUT',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
