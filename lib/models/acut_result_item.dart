class AcutResultItem {
  final int rank;
  final String imagePath;
  final String? imageFileNameValue;
  final bool selected;
  final String status;
  final double? baseScore;
  final double? finalScoreAfterRerank;
  final double? vilaScoreRaw;
  final double? vilaScoreNormalizedInPool;
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
    required this.finalScoreAfterRerank,
    required this.vilaScoreRaw,
    required this.vilaScoreNormalizedInPool,
    required this.acutShortReason,
    required this.acutDetailedReason,
    required this.acutComparisonReason,
  });

  factory AcutResultItem.fromJson(Map<String, dynamic> json) {
    return AcutResultItem(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      imagePath: json['image_path'] as String? ?? '',
      imageFileNameValue: json['image_file_name'] as String?,
      selected: json['selected'] as bool? ?? false,
      status: json['status'] as String? ?? 'rejected',
      baseScore: _toDouble(json['base_score']),
      finalScoreAfterRerank: _toDouble(json['final_score_after_rerank']),
      vilaScoreRaw: _toDouble(json['vila_score_raw']),
      vilaScoreNormalizedInPool: _toDouble(
        json['vila_score_normalized_in_pool'],
      ),
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

  double? get normalizedDisplayScore {
    final rawScore =
        finalScoreAfterRerank ?? baseScore ?? vilaScoreNormalizedInPool;
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
}
