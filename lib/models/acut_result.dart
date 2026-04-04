import 'acut_result_item.dart';

class AcutResult {
  final String schemaVersion;
  final DateTime? generatedAt;
  final String rankingStage;
  final String scoreSemantics;
  final bool diversityEnabled;
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
      generatedAt: DateTime.tryParse(summaryJson['generated_at'] as String? ?? ''),
      rankingStage: summaryJson['ranking_stage'] as String? ?? 'unknown',
      scoreSemantics: summaryJson['score_semantics'] as String? ?? '',
      diversityEnabled: summaryJson['diversity_enabled'] as bool? ?? false,
      items: itemsJson
          .whereType<Map<String, dynamic>>()
          .map(AcutResultItem.fromJson)
          .toList(growable: false),
      selectedCount: (summaryJson['selected_count'] as num?)?.toInt() ?? 0,
      rejectedCount: (summaryJson['rejected_count'] as num?)?.toInt() ?? 0,
      pipelineConfig: (summaryJson['pipeline_config'] as Map<String, dynamic>?) ?? const {},
    );
  }

  List<AcutResultItem> get selectedItems =>
      items.where((item) => item.selected).toList(growable: false);

  AcutResultItem? get bestItem {
    for (final item in items) {
      if (item.rank == 1) {
        return item;
      }
    }
    return null;
  }

  String get displaySource => 'Firebase 비동기 분석';

  String get displaySummary {
    if (selectedItems.isEmpty) {
      return '아직 선택 결과가 도착하지 않았어요.';
    }
    return '선택된 컷 ${selectedCount}장과 제외된 컷 ${rejectedCount}장을 정리했어요.';
  }
}
