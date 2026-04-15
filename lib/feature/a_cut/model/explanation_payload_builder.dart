import 'package:photo_manager/photo_manager.dart';

import '../../../models/acut_result.dart';
import '../../../models/acut_result_item.dart';
import 'explanation_request.dart';
import 'photo_type_mode.dart';
import 'scored_photo_result.dart';

class ExplanationPayloadBuilder {
  static const String schemaVersion = 'acut_multimodal_explanation.v1';

  /// Primary app-side normalization path for Firebase-delivered A-cut results.
  ///
  /// The UI should consume backend result payloads first and only use this
  /// object as a stable display/debug envelope around those server results.
  static ExplanationRequest fromFirebaseResult({
    required AcutResult result,
    required AcutResultItem item,
    required PhotoTypeMode photoTypeMode,
    AssetEntity? asset,
    String? storagePath,
    String? localUri,
    String? imageMimeType,
  }) {
    final pipelineConfig = result.pipelineConfig;
    final effectivePhotoTypeMode =
        _cleanText(item.photoTypeMode) ??
        _cleanText(result.resolvedPhotoTypeMode) ??
        _cleanText(pipelineConfig['photoTypeMode']) ??
        _cleanText(pipelineConfig['photo_type_mode']) ??
        photoTypeMode.backendValue;
    final effectiveExplanationSource =
        _cleanText(item.explanationSource) ??
        _cleanText(result.primaryExplanationSource);
    final aestheticEnabled =
        _toBool(pipelineConfig['aesthetic_enabled']) ||
        item.aestheticScore != null ||
        item.aestheticModelsUsed.isNotEmpty;
    final vilaEnabled =
        _toBool(pipelineConfig['enable_vila_rerank']) ||
        _toBool(pipelineConfig['enable_vila_explanations']) ||
        item.vilaScoreRaw != null;
    final metadata = <String, dynamic>{
      'ranking_stage': result.rankingStage,
      'score_semantics': result.scoreSemantics,
      'aesthetic_enabled': aestheticEnabled,
      'enable_vila_rerank': _toBool(pipelineConfig['enable_vila_rerank']),
      'enable_vila_explanations': _toBool(
        pipelineConfig['enable_vila_explanations'],
      ),
      'aesthetic_weight': _toDouble(pipelineConfig['aesthetic_weight']),
      'result_schema_version': result.schemaVersion,
      'result_explanation_source': effectiveExplanationSource,
    };

    return ExplanationRequest(
      schemaVersion: schemaVersion,
      createdAtUtc: DateTime.now().toUtc(),
      source: ExplanationSource.firebaseServer,
      image: ExplanationImageContext(
        imagePath: item.imagePath,
        imageFileName: item.imageFileName,
        assetId: asset?.id,
        storagePath: storagePath,
        localUri: localUri,
        imageMimeType: imageMimeType,
      ),
      scores: ExplanationScoreContext(
        technicalScore: item.technicalScore,
        aestheticScore: item.aestheticScore,
        finalScore: item.finalScore ?? item.baseScore,
        baseScore: item.baseScore,
        vilaScoreRaw: item.vilaScoreRaw,
        vilaScoreNormalizedInPool: item.vilaScoreNormalizedInPool,
      ),
      rank: item.rank > 0 ? item.rank : null,
      selected: item.selected,
      status: item.status,
      compositionTags: item.tags,
      photoTypeMode: effectivePhotoTypeMode,
      provenance: ExplanationScoreProvenance(
        technicalSource: 'server',
        aestheticSource: aestheticEnabled ? 'server' : null,
        finalScoreSource: 'server',
        aestheticBackend:
            _cleanText(item.aestheticBackend) ??
            _cleanText(pipelineConfig['aesthetic_backend']),
        aestheticModelsUsed: item.aestheticModelsUsed,
        vilaEnabled: vilaEnabled,
      ),
      reasons: ExplanationReasonContext(
        shortReason: _cleanText(item.shortReason),
        detailedReason: _cleanText(item.detailedReason),
        comparisonReason: _cleanText(item.comparisonReason),
      ),
      metadata: metadata,
    );
  }

  /// Transitional legacy path kept for older on-device evaluation flows.
  ///
  /// This remains useful for local scoring/debug screens, but the current
  /// A-cut product flow is Firebase-result-driven rather than VLM-on-device.
  static ExplanationRequest fromOnDeviceResult({
    required ScoredPhotoResult result,
    String? localUri,
    String? imageMimeType,
    List<String> compositionTags = const [],
  }) {
    final evaluation = result.evaluation;
    return ExplanationRequest(
      schemaVersion: schemaVersion,
      createdAtUtc: DateTime.now().toUtc(),
      source: ExplanationSource.onDevice,
      image: ExplanationImageContext(
        imagePath: result.fileName,
        imageFileName: result.fileName,
        assetId: result.asset.id,
        storagePath: null,
        localUri: localUri,
        imageMimeType: imageMimeType,
      ),
      scores: ExplanationScoreContext(
        technicalScore: evaluation?.technicalScore,
        aestheticScore: evaluation?.aestheticScore,
        finalScore: evaluation?.finalScore,
        baseScore: evaluation?.finalScore,
        vilaScoreRaw: null,
        vilaScoreNormalizedInPool: null,
      ),
      rank: result.rank,
      selected: result.isACut,
      status: result.status.name,
      compositionTags: compositionTags,
      photoTypeMode: result.photoTypeMode.backendValue,
      provenance: ExplanationScoreProvenance(
        technicalSource: 'on_device',
        aestheticSource: evaluation?.aestheticScore == null
            ? null
            : 'on_device',
        finalScoreSource: 'on_device',
        aestheticBackend: null,
        aestheticModelsUsed: const [],
        vilaEnabled: false,
      ),
      reasons: ExplanationReasonContext(
        shortReason: evaluation?.notes.isNotEmpty == true
            ? evaluation!.notes.first
            : null,
        detailedReason: evaluation?.qualitySummary,
        comparisonReason: null,
      ),
      metadata: {
        'uses_technical_score_as_final':
            evaluation?.usesTechnicalScoreAsFinal ?? false,
        'warnings': evaluation?.warnings ?? const <String>[],
      },
    );
  }

  static Map<String, dynamic> buildMultimodalApiInput(
    ExplanationRequest request, {
    String promptVersion = 'acut-comment-v1',
  }) {
    return {
      'prompt_version': promptVersion,
      'explanation_request': request.toJson(),
      'integration_todo': {
        'image_input':
            'Attach either signed Storage URL or inline bytes before API call.',
        'llm_call_site':
            'Use this payload in the future multimodal explanation API client.',
      },
    };
  }

  static String? _cleanText(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool _toBool(Object? value) {
    if (value is bool) {
      return value;
    }
    return false;
  }

  static double? _toDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
