import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../model/photo_type_mode.dart';
import '../../model/scored_photo_result.dart';
import '../inference/aesthetic_inference_service.dart';
import '../ranking/a_cut_ranking_service.dart';

const String nimaAestheticModelPath =
    'assets/models/nima_aesthetic_fp16_flex.tflite';
const String nimaTechnicalModelPath =
    'assets/models/nima_technical_fp16_flex.tflite';

abstract class ImageScoreService {
  Future<void> scoreAssets({
    required List<AssetEntity> assets,
    required PhotoTypeMode photoTypeMode,
    required double topPercent,
    required void Function(
      List<ScoredPhotoResult> snapshot,
      int done,
      int total,
    )
    onProgress,
  });
}

class NimaImageScoreService implements ImageScoreService {
  NimaImageScoreService({
    PhotoInferenceService? aestheticInference,
    PhotoInferenceService? technicalInference,
    ACutRankingService? rankingService,
  }) : _aestheticInference =
           aestheticInference ??
           NimaAestheticInferenceService(
             modelAssetPath: nimaAestheticModelPath,
           ),
       _technicalInference =
           technicalInference ??
           NimaAestheticInferenceService(
             modelAssetPath: nimaTechnicalModelPath,
           ),
       _rankingService = rankingService ?? const ACutRankingService();

  final PhotoInferenceService _aestheticInference;
  final PhotoInferenceService _technicalInference;
  final ACutRankingService _rankingService;

  @override
  Future<void> scoreAssets({
    required List<AssetEntity> assets,
    required PhotoTypeMode photoTypeMode,
    required double topPercent,
    required void Function(
      List<ScoredPhotoResult> snapshot,
      int done,
      int total,
    )
    onProgress,
  }) async {
    final total = assets.length;
    final working = <ScoredPhotoResult>[];

    for (var i = 0; i < assets.length; i++) {
      final asset = assets[i];
      final name = await _resolveFilename(asset, i);
      working.add(
        ScoredPhotoResult(
          asset: asset,
          fileName: name,
          selectedIndex: i,
          status: ScoreStatus.pending,
          photoTypeMode: photoTypeMode,
        ),
      );
    }

    onProgress(
      _rankingService.rank(results: working, topPercent: topPercent),
      0,
      total,
    );

    var done = 0;
    for (var i = 0; i < working.length; i++) {
      final current = working[i];

      try {
        final originBytes = await current.asset.originBytes;
        if (originBytes == null || originBytes.isEmpty) {
          throw Exception('Cannot read image bytes.');
        }

        // Run aesthetic inference
        final aestheticOutput = await _aestheticInference.run(originBytes);
        
        // Run technical inference (sequential for stability)
        double? technicalScore;
        List<double>? technicalDistribution;
        try {
          final technicalOutput = await _technicalInference.run(originBytes);
          technicalScore = technicalOutput.meanScore;
          technicalDistribution = technicalOutput.distribution;
        } catch (e) {
          // Fallback if technical fails but aesthetic succeeded
          debugPrint('Technical inference failed for ${current.fileName}: $e');
        }

        working[i] = current.copyWith(
          status: ScoreStatus.success,
          aestheticScore: aestheticOutput.meanScore,
          aestheticDistribution: aestheticOutput.distribution,
          technicalScore: technicalScore,
          technicalDistribution: technicalDistribution,
          clearErrorMessage: true,
          photoTypeMode: photoTypeMode,
        );
      } catch (error) {
        working[i] = current.copyWith(
          status: ScoreStatus.failed,
          errorMessage: error.toString(),
          photoTypeMode: photoTypeMode,
        );
      }

      done += 1;
      onProgress(
        _rankingService.rank(results: working, topPercent: topPercent),
        done,
        total,
      );
    }
  }

  Future<String> _resolveFilename(AssetEntity asset, int index) async {
    final title = await asset.titleAsync;
    if (title.trim().isNotEmpty) {
      return title;
    }
    return 'photo_${index + 1}';
  }
}
