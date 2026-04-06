import 'acut_result_item.dart';

class AcutResult {
  final String schemaVersion;
  final DateTime? generatedAt;
  final String rankingStage;
  final String scoreSemantics;
  final bool diversityEnabled;
  final bool finalOrderingUsesDiversity;
  final bool finalScoreMatchesFinalRanking;
  final List<AcutResultItem> items;
  final int selectedCount;
  final int rejectedCount;
  final Map<String, dynamic> pipelineConfig;

  const AcutResult({
    required this.schemaVersion,
    required this.generatedAt,
    required this.rankingStage,
    required this.scoreSemantics,
    required this.diversityEnabled,
    required this.finalOrderingUsesDiversity,
    required this.finalScoreMatchesFinalRanking,
    required this.items,
    required this.selectedCount,
    required this.rejectedCount,
    required this.pipelineConfig,
  });

  factory AcutResult.fromPayload({
    required List<dynamic> itemsJson,
    required Map<String, dynamic> summaryJson,
  }) {
    return AcutResult(
      schemaVersion: summaryJson['schema_version'] as String? ?? 'unknown',
      generatedAt: DateTime.tryParse(
        summaryJson['generated_at'] as String? ?? '',
      ),
      rankingStage: summaryJson['ranking_stage'] as String? ?? 'unknown',
      scoreSemantics: summaryJson['score_semantics'] as String? ?? '',
      diversityEnabled: summaryJson['diversity_enabled'] as bool? ?? false,
      finalOrderingUsesDiversity:
          summaryJson['final_ordering_uses_diversity'] as bool? ??
          (summaryJson['ranking_stage'] == 'post_diversity'),
      finalScoreMatchesFinalRanking:
          summaryJson['final_score_matches_final_ranking'] as bool? ??
          !(summaryJson['diversity_enabled'] as bool? ?? false),
      items: itemsJson
          .whereType<Map<String, dynamic>>()
          .map(AcutResultItem.fromJson)
          .toList(growable: false),
      selectedCount: (summaryJson['selected_count'] as num?)?.toInt() ?? 0,
      rejectedCount: (summaryJson['rejected_count'] as num?)?.toInt() ?? 0,
      pipelineConfig:
          (summaryJson['pipeline_config'] as Map<String, dynamic>?) ?? const {},
    );
  }

  List<AcutResultItem> get rankedItems {
    final ranked = List<AcutResultItem>.from(items);
    ranked.sort((a, b) {
      final aRank = a.rank > 0 ? a.rank : 1 << 20;
      final bRank = b.rank > 0 ? b.rank : 1 << 20;
      return aRank.compareTo(bRank);
    });
    return ranked;
  }

  List<AcutResultItem> get selectedItems =>
      rankedItems.where((item) => item.selected).toList(growable: false);

  List<AcutResultItem> get topPicks =>
      rankedItems.take(3).toList(growable: false);

  AcutResultItem? get bestItem {
    for (final item in rankedItems) {
      if (item.rank == 1) {
        return item;
      }
    }
    return null;
  }

  String get displayTitle => 'A컷 추천 결과';

  String get displaySource => 'Firebase 비동기 분석';

  String get displaySummary {
    if (selectedItems.isEmpty) {
      return '아직 선택 결과가 도착하지 않았어요.';
    }
    return '선택된 컷 $selectedCount장과 제외된 컷 $rejectedCount장을 정리했어요.';
  }
}
