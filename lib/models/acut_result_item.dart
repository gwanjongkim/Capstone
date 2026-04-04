class AcutResultItem {
  final int rank;
  final String imagePath;
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
      selected: json['selected'] as bool? ?? false,
      status: json['status'] as String? ?? 'rejected',
      baseScore: _toDouble(json['base_score']),
      finalScoreAfterRerank: _toDouble(json['final_score_after_rerank']),
      vilaScoreRaw: _toDouble(json['vila_score_raw']),
      vilaScoreNormalizedInPool: _toDouble(json['vila_score_normalized_in_pool']),
      acutShortReason: json['acut_short_reason'] as String?,
      acutDetailedReason: json['acut_detailed_reason'] as String?,
      acutComparisonReason: json['acut_comparison_reason'] as String?,
    );
  }

  String get imageFileName {
    final normalized = imagePath.replaceAll('\\', '/');
    if (normalized.isEmpty) {
      return '';
    }
    return normalized.split('/').last;
  }

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

  String get scoreLabel {
    final score = finalScoreAfterRerank;
    if (score == null) {
      return '점수 없음';
    }
    return '점수 ${score.toStringAsFixed(3)}';
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
