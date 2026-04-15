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
  final double? finalScore;
  final double? vilaScoreRaw;
  final double? vilaScoreNormalizedInPool;
  final String? photoTypeMode;
  final List<String> tags;
  final Map<String, dynamic>? explanationStructured;
  final String? shortReason;
  final String? detailedReason;
  final String? comparisonReason;
  final String? explanationSource;

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
    required this.finalScore,
    required this.vilaScoreRaw,
    required this.vilaScoreNormalizedInPool,
    required this.photoTypeMode,
    required this.tags,
    required this.explanationStructured,
    required this.shortReason,
    required this.detailedReason,
    required this.comparisonReason,
    required this.explanationSource,
  });

  /// Primary normalization layer for Firebase `app_results.json` rows.
  ///
  /// Accepts current snake_case export fields, camelCase variants, older
  /// `acut_*` explanation keys, and richer nested explanation payloads.
  factory AcutResultItem.fromJson(
    Map<String, dynamic> json, {
    String? fallbackPhotoTypeMode,
    String? fallbackExplanationSource,
  }) {
    final imageContext = _toMap(json['image']) ?? _toMap(json['image_context']);
    final scorePayload = _toMap(json['scores']) ?? _toMap(json['score']);
    final activeExplanation = _resolveActiveExplanation(json);
    final activeReasons =
        _toMap(activeExplanation?['reasons']) ??
        _toMap(activeExplanation?['reason_context']);
    final explanationStructured =
        _toMap(json['explanation_structured']) ??
        _toMap(json['explanationStructured']) ??
        _toMap(json['acut_explanation_structured']) ??
        _toMap(activeExplanation?['explanation_structured']) ??
        _toMap(activeExplanation?['explanationStructured']);
    final normalizedStatus = _readSelectionStatus(json);
    final selected =
        _toBoolOrNull(json['selected']) ??
        _toBoolOrNull(json['is_selected']) ??
        _toBoolOrNull(json['isSelected']) ??
        (normalizedStatus == 'selected'
            ? true
            : normalizedStatus == 'rejected'
            ? false
            : null) ??
        false;
    final aestheticModelsUsed = _preferredStringList(
      json['aesthetic_models_used'],
      json['aestheticModelsUsed'],
    );
    final tags = _extractTags(
      json,
      explanationStructured: explanationStructured,
      activeExplanation: activeExplanation,
    );

    return AcutResultItem(
      rank:
          _toInt(json['rank']) ??
          _toInt(json['position']) ??
          _toInt(json['order']) ??
          0,
      imagePath:
          _firstText([
            json['image_path'],
            json['imagePath'],
            imageContext?['image_path'],
            imageContext?['imagePath'],
            imageContext?['path'],
            json['path'],
          ]) ??
          '',
      imageFileNameValue: _firstText([
        json['image_file_name'],
        json['imageFileName'],
        imageContext?['image_file_name'],
        imageContext?['imageFileName'],
        imageContext?['file_name'],
        imageContext?['fileName'],
      ]),
      selected: selected,
      status: normalizedStatus ?? (selected ? 'selected' : 'rejected'),
      baseScore:
          _toDouble(json['base_score']) ??
          _toDouble(json['baseScore']) ??
          _toDouble(scorePayload?['base_score']) ??
          _toDouble(scorePayload?['baseScore']),
      technicalScore:
          _toDouble(json['technical_score']) ??
          _toDouble(json['technicalScore']) ??
          _toDouble(json['technical_component']) ??
          _toDouble(json['technicalComponent']) ??
          _toDouble(scorePayload?['technical_score']) ??
          _toDouble(scorePayload?['technicalScore']),
      aestheticScore:
          _toDouble(json['aesthetic_score']) ??
          _toDouble(json['aestheticScore']) ??
          _toDouble(json['aesthetic_component']) ??
          _toDouble(json['aestheticComponent']) ??
          _toDouble(scorePayload?['aesthetic_score']) ??
          _toDouble(scorePayload?['aestheticScore']),
      aestheticScoreContributed:
          _toBoolOrNull(json['aesthetic_score_contributed']) ??
          _toBoolOrNull(json['aestheticScoreContributed']) ??
          (_toDouble(json['aesthetic_score']) != null ||
              _toDouble(json['aestheticScore']) != null ||
              _toDouble(scorePayload?['aesthetic_score']) != null ||
              _toDouble(scorePayload?['aestheticScore']) != null),
      aestheticModelsUsed: aestheticModelsUsed,
      aestheticBackend:
          _cleanText(json['aesthetic_backend']) ??
          _cleanText(json['aestheticBackend']),
      finalScore:
          _toDouble(json['final_score']) ??
          _toDouble(json['finalScore']) ??
          _toDouble(json['final_score_after_rerank']) ??
          _toDouble(json['finalScoreAfterRerank']) ??
          _toDouble(scorePayload?['final_score']) ??
          _toDouble(scorePayload?['finalScore']),
      vilaScoreRaw:
          _toDouble(json['vila_score_raw']) ??
          _toDouble(json['vilaScoreRaw']) ??
          _toDouble(scorePayload?['vila_score_raw']) ??
          _toDouble(scorePayload?['vilaScoreRaw']),
      vilaScoreNormalizedInPool:
          _toDouble(json['vila_score_normalized_in_pool']) ??
          _toDouble(json['vilaScoreNormalizedInPool']) ??
          _toDouble(scorePayload?['vila_score_normalized_in_pool']) ??
          _toDouble(scorePayload?['vilaScoreNormalizedInPool']),
      photoTypeMode: _firstText([
        json['photoTypeMode'],
        json['photo_type_mode'],
        json['photo_type'],
        json['photoType'],
        fallbackPhotoTypeMode,
      ]),
      tags: tags,
      explanationStructured: explanationStructured,
      shortReason: _firstText([
        json['short_reason'],
        json['shortReason'],
        json['acut_short_reason'],
        activeExplanation?['short_reason'],
        activeExplanation?['shortReason'],
        activeReasons?['short_reason'],
        activeReasons?['shortReason'],
      ]),
      detailedReason: _firstText([
        json['detailed_reason'],
        json['detailedReason'],
        json['acut_detailed_reason'],
        activeExplanation?['detailed_reason'],
        activeExplanation?['detailedReason'],
        activeReasons?['detailed_reason'],
        activeReasons?['detailedReason'],
      ]),
      comparisonReason: _firstText([
        json['comparison_reason'],
        json['comparisonReason'],
        json['acut_comparison_reason'],
        activeExplanation?['comparison_reason'],
        activeExplanation?['comparisonReason'],
        activeReasons?['comparison_reason'],
        activeReasons?['comparisonReason'],
      ]),
      explanationSource: _firstText([
        json['active_explanation_source'],
        json['activeExplanationSource'],
        json['explanation_source'],
        json['explanationSource'],
        activeExplanation?['explanation_source'],
        activeExplanation?['explanationSource'],
        fallbackExplanationSource,
      ]),
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

  String get selectedBadgeLabel {
    if (selected) {
      return '선택됨';
    }
    final normalizedStatusLabel = statusLabel;
    return normalizedStatusLabel == '제외' ? '후보 아님' : normalizedStatusLabel;
  }

  String get primaryReason {
    final short = shortReason?.trim();
    if (short != null && short.isNotEmpty) {
      return short;
    }
    final detailed = detailedReason?.trim();
    if (detailed != null && detailed.isNotEmpty) {
      return detailed;
    }
    return '분석 이유가 아직 도착하지 않았어요.';
  }

  bool get hasReasonDetails =>
      (detailedReason ?? '').trim().isNotEmpty ||
      (comparisonReason ?? '').trim().isNotEmpty;

  double? get displayScore {
    return finalScore ?? baseScore;
  }

  double? get normalizedDisplayScore {
    final rawScore = displayScore ?? vilaScoreNormalizedInPool;
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

  String? get finalScoreChipLabel => _scoreChipLabel('최종', displayScore);

  String? get technicalScoreChipLabel => _scoreChipLabel('기술', technicalScore);

  String? get aestheticScoreChipLabel => _scoreChipLabel('미적', aestheticScore);

  List<String> get previewTags => tags.take(2).toList(growable: false);

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
      case 'candidate':
        return '후보';
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
    if (status.trim().toLowerCase() == 'error') {
      return '결과 확인이 필요한 컷';
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

  static int? _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool? _toBoolOrNull(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = _cleanText(value)?.toLowerCase();
    if (text == 'true') {
      return true;
    }
    if (text == 'false') {
      return false;
    }
    return null;
  }

  static String? _cleanText(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String? _firstText(Iterable<Object?> candidates) {
    for (final candidate in candidates) {
      final text = _cleanText(candidate);
      if (text != null) {
        return text;
      }
    }
    return null;
  }

  static String? _readSelectionStatus(Map<String, dynamic> json) {
    final raw = _firstText([
      json['selection_status'],
      json['selectionStatus'],
      json['status'],
    ])?.toLowerCase();
    switch (raw) {
      case 'selected':
      case 'rejected':
      case 'error':
      case 'candidate':
        return raw;
      default:
        return null;
    }
  }

  static Map<String, dynamic>? _resolveActiveExplanation(
    Map<String, dynamic> json,
  ) {
    final direct =
        _toMap(json['active_explanation']) ?? _toMap(json['activeExplanation']);
    if (direct != null) {
      return direct;
    }
    final explanations = _toMap(json['explanations']);
    if (explanations == null || explanations.isEmpty) {
      return null;
    }
    final activeSource =
        _cleanText(json['active_explanation_source']) ??
        _cleanText(json['activeExplanationSource']);
    if (activeSource != null) {
      final sourced = _toMap(explanations[activeSource]);
      if (sourced != null) {
        return sourced;
      }
    }
    if (explanations.length == 1) {
      return _toMap(explanations.values.first);
    }
    return null;
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

  static List<String> _preferredStringList(Object? primary, Object? secondary) {
    final primaryList = _toStringList(primary);
    if (primaryList.isNotEmpty) {
      return primaryList;
    }
    return _toStringList(secondary);
  }

  static List<String> _toStringList(Object? value) {
    if (value == null) {
      return const [];
    }
    if (value is List) {
      return value
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
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

  static List<String> _extractTags(
    Map<String, dynamic> json, {
    required Map<String, dynamic>? explanationStructured,
    required Map<String, dynamic>? activeExplanation,
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

    addTagCandidates(json['tags']);
    addTagCandidates(json['composition_tags']);
    addTagCandidates(json['compositionTags']);
    addTagCandidates(json['composition_tag']);
    addTagCandidates(json['compositionTag']);
    addTagCandidates(activeExplanation?['tags']);
    addTagCandidates(activeExplanation?['composition_tags']);

    final structured = explanationStructured;
    if (structured != null) {
      addTagCandidates(structured['tags']);
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
        _cleanText(json['short_reason']) ?? '',
        _cleanText(json['shortReason']) ?? '',
        _cleanText(json['detailed_reason']) ?? '',
        _cleanText(json['detailedReason']) ?? '',
        _cleanText(json['acut_short_reason']) ?? '',
        _cleanText(json['acut_detailed_reason']) ?? '',
        _cleanText(activeExplanation?['short_reason']) ?? '',
        _cleanText(activeExplanation?['detailed_reason']) ?? '',
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

  static String? _scoreChipLabel(String label, double? score) {
    final normalized = _normalizeScore(score);
    if (normalized == null) {
      return null;
    }
    return '$label ${(normalized * 100).round()}점';
  }

  static double? _normalizeScore(double? score) {
    if (score == null) {
      return null;
    }
    final normalized = score > 1.0 && score <= 100.0 ? score / 100.0 : score;
    return normalized.clamp(0.0, 1.0).toDouble();
  }
}
