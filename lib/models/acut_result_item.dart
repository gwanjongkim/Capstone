import 'dart:convert';

class AcutResultItem {
  final int rank;
  final String imagePath;
  final String? imageFileNameValue;
  final bool selected;
  final String status;
  final double? baseScore;
  final double? technicalScore;
  final double? aestheticScore;
  final bool aestheticScoreContributed;
  final List<String> aestheticModelsUsed;
  final String? aestheticBackend;
  final double? finalScoreAfterRerank;
  final double? vilaScoreRaw;
  final double? vilaScoreNormalizedInPool;
  final String? photoTypeMode;
  final List<String> compositionTags;
  final Map<String, dynamic>? explanationStructured;
  final String? acutShortReason;
  final String? acutDetailedReason;
  final String? acutComparisonReason;

  const AcutResultItem({
    required this.rank,
    required this.imagePath,
    required this.imageFileNameValue,
    required this.selected,
    required this.status,
    required this.baseScore,
    required this.technicalScore,
    required this.aestheticScore,
    required this.aestheticScoreContributed,
    required this.aestheticModelsUsed,
    required this.aestheticBackend,
    required this.finalScoreAfterRerank,
    required this.vilaScoreRaw,
    required this.vilaScoreNormalizedInPool,
    required this.photoTypeMode,
    required this.compositionTags,
    required this.explanationStructured,
    required this.acutShortReason,
    required this.acutDetailedReason,
    required this.acutComparisonReason,
  });

  factory AcutResultItem.fromJson(Map<String, dynamic> json) {
    final explanationStructured =
        _toMap(json['explanation_structured']) ??
        _toMap(json['acut_explanation_structured']);
    final compositionTags = _extractCompositionTags(
      json,
      explanationStructured: explanationStructured,
    );
    return AcutResultItem(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      imagePath: json['image_path'] as String? ?? '',
      imageFileNameValue: json['image_file_name'] as String?,
      selected: json['selected'] as bool? ?? false,
      status: json['status'] as String? ?? 'rejected',
      baseScore: _toDouble(json['base_score']),
      technicalScore:
          _toDouble(json['technical_score']) ??
          _toDouble(json['technical_component']),
      aestheticScore:
          _toDouble(json['aesthetic_score']) ??
          _toDouble(json['aesthetic_component']),
      aestheticScoreContributed:
          json['aesthetic_score_contributed'] as bool? ??
          _toDouble(json['aesthetic_score']) != null,
      aestheticModelsUsed: _toStringList(json['aesthetic_models_used']),
      aestheticBackend: _cleanText(json['aesthetic_backend']),
      finalScoreAfterRerank: _toDouble(json['final_score_after_rerank']),
      vilaScoreRaw: _toDouble(json['vila_score_raw']),
      vilaScoreNormalizedInPool: _toDouble(
        json['vila_score_normalized_in_pool'],
      ),
      photoTypeMode:
          _cleanText(json['photoTypeMode']) ??
          _cleanText(json['photo_type_mode']),
      compositionTags: compositionTags,
      explanationStructured: explanationStructured,
      acutShortReason: json['acut_short_reason'] as String?,
      acutDetailedReason: json['acut_detailed_reason'] as String?,
      acutComparisonReason: json['acut_comparison_reason'] as String?,
    );
  }

  String get imageFileName {
    final explicitName = imageFileNameValue?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }
    final normalized = imagePath.replaceAll('\\', '/');
    if (normalized.isEmpty) {
      return '';
    }
    return normalized.split('/').last;
  }

  bool get isBestShot => rank == 1;

  bool get isTopThree => rank > 0 && rank <= 3;

  bool get isRecommendedPick => selected || isTopThree;

  String get rankLabel => rank > 0 ? '#$rank' : '-';

  String get selectedBadgeLabel => selected ? '선택됨' : '후보 아님';

  String get primaryReason {
    final shortReason = acutShortReason?.trim();
    if (shortReason != null && shortReason.isNotEmpty) {
      return shortReason;
    }
    final detailedReason = acutDetailedReason?.trim();
    if (detailedReason != null && detailedReason.isNotEmpty) {
      return detailedReason;
    }
    return '분석 이유가 아직 도착하지 않았어요.';
  }

  double? get finalScore {
    return finalScoreAfterRerank ?? baseScore;
  }

  double? get normalizedDisplayScore {
    final rawScore = finalScore ?? vilaScoreNormalizedInPool;
    if (rawScore == null) {
      return null;
    }
    final normalized = rawScore > 1.0 && rawScore <= 100.0
        ? rawScore / 100.0
        : rawScore;
    return normalized.clamp(0.0, 1.0).toDouble();
  }

  int? get displayScorePercent {
    final normalized = normalizedDisplayScore;
    if (normalized == null) {
      return null;
    }
    return (normalized * 100).round();
  }

  String get scoreLabel {
    final pct = displayScorePercent;
    if (pct == null) {
      return '점수 없음';
    }
    return '종합 $pct점';
  }

  String get verdictLabel {
    final normalized = normalizedDisplayScore;
    if (normalized == null) {
      return selected ? '선택 컷' : '후보';
    }
    if (normalized >= 0.85) {
      return '매우 좋음';
    }
    if (normalized >= 0.70) {
      return '좋음';
    }
    if (normalized >= 0.50) {
      return '보통';
    }
    return '아쉬움';
  }

  String get statusLabel {
    switch (status.trim().toLowerCase()) {
      case 'selected':
        return '선택';
      case 'rejected':
        return '제외';
      case 'error':
        return '오류';
      default:
        return status.trim().isEmpty ? (selected ? '선택' : '후보') : status;
    }
  }

  String get highlightLabel {
    if (isBestShot) {
      return 'BEST';
    }
    if (isTopThree) {
      return 'TOP $rank';
    }
    if (selected) {
      return '추천 컷';
    }
    return statusLabel;
  }

  String get recommendationLabel {
    if (isBestShot) {
      return '가장 추천하는 베스트 컷';
    }
    if (isTopThree) {
      return '상위 추천 컷';
    }
    if (selected) {
      return 'A컷 후보';
    }
    return '후보에서 제외된 컷';
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

  static String? _cleanText(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, dynamic>? _toMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static List<String> _toStringList(Object? value) {
    if (value == null) {
      return const [];
    }
    if (value is List) {
      final values = value
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
      return values;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return const [];
      }
      if ((trimmed.startsWith('[') && trimmed.endsWith(']')) ||
          (trimmed.startsWith('{') && trimmed.endsWith('}'))) {
        try {
          final decoded = jsonDecode(trimmed);
          return _toStringList(decoded);
        } catch (_) {
          // Keep fallback split path.
        }
      }
      return trimmed
          .split(RegExp(r'[,|/]'))
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static List<String> _extractCompositionTags(
    Map<String, dynamic> json, {
    required Map<String, dynamic>? explanationStructured,
  }) {
    final tags = <String>{};
    void addTagCandidates(Object? source) {
      for (final tag in _toStringList(source)) {
        final normalized = tag.trim();
        if (normalized.isNotEmpty) {
          tags.add(normalized);
        }
      }
    }

    addTagCandidates(json['composition_tags']);
    addTagCandidates(json['compositionTags']);
    addTagCandidates(json['composition_tag']);
    addTagCandidates(json['compositionTag']);

    final structured = explanationStructured;
    if (structured != null) {
      addTagCandidates(structured['composition_tags']);
      final signals = _toMap(structured['signals']);
      if (signals != null) {
        addTagCandidates(signals['top_strengths']);
        addTagCandidates(signals['top_weaknesses']);
        addTagCandidates(signals['strengths']);
        addTagCandidates(signals['weaknesses']);
      }
      final vila = _toMap(structured['vila']);
      if (vila != null) {
        addTagCandidates(vila['top_strengths']);
        addTagCandidates(vila['top_weaknesses']);
      }
    }

    if (tags.isEmpty) {
      final reasonText = [
        _cleanText(json['acut_short_reason']) ?? '',
        _cleanText(json['acut_detailed_reason']) ?? '',
      ].join(' ').toLowerCase();
      final fallbackMap = <String, String>{
        'composition': 'composition',
        'subject clarity': 'subject_clarity',
        'background cleanliness': 'background_cleanliness',
        'lighting': 'lighting',
        'technical quality': 'technical_quality',
        'aesthetic score': 'aesthetic_score',
        'overall image appeal': 'overall_image_appeal',
      };
      for (final entry in fallbackMap.entries) {
        if (reasonText.contains(entry.key)) {
          tags.add(entry.value);
        }
      }
    }

    return tags.take(10).toList(growable: false);
  }
}
