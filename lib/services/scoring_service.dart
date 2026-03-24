import 'dart:io';
import 'dart:math' as math;
import '../models/scored_image.dart';
import 'inference_service.dart';

class ScoringService {
  final IInferenceService _inferenceService;
  
  ScoringService(this._inferenceService);

  Future<void> init() async {
    await _inferenceService.loadModel();
  }

  /// Processes multiple images and returns a list of ScoredImage.
  /// [onProgress] returns the number of images processed so far.
  Future<List<ScoredImage>> processImages(
    List<File> files, {
    double topPercent = 0.2,
    Function(int)? onProgress,
  }) async {
    List<ScoredImage> results = [];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final scoredImage = ScoredImage(
        file: file,
        fileName: file.path.split(Platform.pathSeparator).last,
      );
      
      try {
        scoredImage.aestheticScore = await _inferenceService.predict(file);
      } catch (e) {
        scoredImage.hasError = true;
        scoredImage.errorMessage = e.toString();
        print('Error scoring ${file.path}: $e');
      }
      
      results.add(scoredImage);
      if (onProgress != null) onProgress(i + 1);
    }

    // Rank and select A-cuts
    _rankAndSelect(results, topPercent);
    return results;
  }

  void _rankAndSelect(List<ScoredImage> results, double topPercent) {
    // Only rank results that didn't have an error
    final validResults = results.where((img) => !img.hasError).toList();
    
    // Sort descending by score
    validResults.sort((a, b) => b.totalScore.compareTo(a.totalScore));

    // Select top X% (at least 1 if there are any valid images)
    int aCutCount = 0;
    if (validResults.isNotEmpty) {
      aCutCount = math.max(1, (validResults.length * topPercent).ceil());
    }

    for (int i = 0; i < validResults.length; i++) {
      validResults[i].rank = i + 1;
      validResults[i].isACut = i < aCutCount;
    }
  }

  void dispose() {
    _inferenceService.dispose();
  }
}
