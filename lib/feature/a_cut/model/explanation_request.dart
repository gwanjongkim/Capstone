class ExplanationRequest {
  const ExplanationRequest({
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.source,
    required this.image,
    required this.scores,
    required this.rank,
    required this.selected,
    required this.status,
    required this.compositionTags,
    required this.photoTypeMode,
    required this.provenance,
    required this.reasons,
    this.metadata = const {},
  });

  final String schemaVersion;
  final DateTime createdAtUtc;
  final ExplanationSource source;
  final ExplanationImageContext image;
  final ExplanationScoreContext scores;
  final int? rank;
  final bool selected;
  final String status;
  final List<String> compositionTags;
  final String photoTypeMode;
  final ExplanationScoreProvenance provenance;
  final ExplanationReasonContext reasons;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'created_at_utc': createdAtUtc.toIso8601String(),
      'source': source.name,
      'image': image.toJson(),
      'scores': scores.toJson(),
      'rank': rank,
      'selected': selected,
      'status': status,
      'composition_tags': compositionTags,
      'photo_type_mode': photoTypeMode,
      'provenance': provenance.toJson(),
      'reasons': reasons.toJson(),
      'metadata': metadata,
    };
  }
}

enum ExplanationSource { firebaseServer, onDevice }

class ExplanationImageContext {
  const ExplanationImageContext({
    required this.imagePath,
    required this.imageFileName,
    this.assetId,
    this.storagePath,
    this.localUri,
    this.imageMimeType,
  });

  final String imagePath;
  final String imageFileName;
  final String? assetId;
  final String? storagePath;
  final String? localUri;
  final String? imageMimeType;

  Map<String, dynamic> toJson() {
    return {
      'image_path': imagePath,
      'image_file_name': imageFileName,
      'asset_id': assetId,
      'storage_path': storagePath,
      'local_uri': localUri,
      'image_mime_type': imageMimeType,
    };
  }
}

class ExplanationScoreContext {
  const ExplanationScoreContext({
    required this.technicalScore,
    required this.aestheticScore,
    required this.finalScore,
    required this.baseScore,
    required this.vilaScoreRaw,
    required this.vilaScoreNormalizedInPool,
  });

  final double? technicalScore;
  final double? aestheticScore;
  final double? finalScore;
  final double? baseScore;
  final double? vilaScoreRaw;
  final double? vilaScoreNormalizedInPool;

  Map<String, dynamic> toJson() {
    return {
      'technical_score': technicalScore,
      'aesthetic_score': aestheticScore,
      'final_score': finalScore,
      'base_score': baseScore,
      'vila_score_raw': vilaScoreRaw,
      'vila_score_normalized_in_pool': vilaScoreNormalizedInPool,
    };
  }
}

class ExplanationScoreProvenance {
  const ExplanationScoreProvenance({
    required this.technicalSource,
    required this.aestheticSource,
    required this.finalScoreSource,
    required this.aestheticBackend,
    required this.aestheticModelsUsed,
    required this.vilaEnabled,
  });

  final String technicalSource;
  final String? aestheticSource;
  final String finalScoreSource;
  final String? aestheticBackend;
  final List<String> aestheticModelsUsed;
  final bool vilaEnabled;

  Map<String, dynamic> toJson() {
    return {
      'technical_source': technicalSource,
      'aesthetic_source': aestheticSource,
      'final_score_source': finalScoreSource,
      'aesthetic_backend': aestheticBackend,
      'aesthetic_models_used': aestheticModelsUsed,
      'vila_enabled': vilaEnabled,
    };
  }
}

class ExplanationReasonContext {
  const ExplanationReasonContext({
    required this.shortReason,
    required this.detailedReason,
    required this.comparisonReason,
  });

  final String? shortReason;
  final String? detailedReason;
  final String? comparisonReason;

  Map<String, dynamic> toJson() {
    return {
      'short_reason': shortReason,
      'detailed_reason': detailedReason,
      'comparison_reason': comparisonReason,
    };
  }
}
