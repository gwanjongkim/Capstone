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
    final pipelineConfig =
        _toMap(summaryJson['pipeline_config']) ??
        _toMap(summaryJson['pipelineConfig']) ??
        const <String, dynamic>{};
    final fallbackPhotoTypeMode =
        _cleanText(pipelineConfig['photo_type_mode']) ??
        _cleanText(pipelineConfig['photoTypeMode']);
    final fallbackExplanationSource =
        _cleanText(summaryJson['explanation_source']) ??
        _cleanText(summaryJson['explanationSource']) ??
        _cleanText(pipelineConfig['explanation_source']) ??
        _cleanText(pipelineConfig['explanationSource']) ??
        _cleanText(pipelineConfig['multimodal_explanation_backend']) ??
        _cleanText(pipelineConfig['multimodalExplanationBackend']);
    final parsedItems = itemsJson
        .whereType<Map>()
        .map(
          (item) => AcutResultItem.fromJson(
            Map<String, dynamic>.from(item),
            fallbackPhotoTypeMode: fallbackPhotoTypeMode,
            fallbackExplanationSource: fallbackExplanationSource,
          ),
        )
        .toList(growable: false);
    final diversityEnabled =
        _toBoolOrNull(summaryJson['diversity_enabled']) ??
        _toBoolOrNull(summaryJson['diversityEnabled']) ??
        false;
    final selectedCount =
        _toInt(summaryJson['selected_count']) ??
        _toInt(summaryJson['selectedCount']) ??
        parsedItems.where((item) => item.selected).length;
    final rejectedCount =
        _toInt(summaryJson['rejected_count']) ??
        _toInt(summaryJson['rejectedCount']) ??
        parsedItems.where((item) => !item.selected).length;

    return AcutResult(
      schemaVersion:
          _cleanText(summaryJson['schema_version']) ??
          _cleanText(summaryJson['schemaVersion']) ??
          'unknown',
      generatedAt: DateTime.tryParse(
        _cleanText(summaryJson['generated_at']) ??
            _cleanText(summaryJson['generatedAt']) ??
            '',
      ),
      rankingStage:
          _cleanText(summaryJson['ranking_stage']) ??
          _cleanText(summaryJson['rankingStage']) ??
          'unknown',
      scoreSemantics:
          _cleanText(summaryJson['score_semantics']) ??
          _cleanText(summaryJson['scoreSemantics']) ??
          '',
      diversityEnabled: diversityEnabled,
      finalOrderingUsesDiversity:
          _toBoolOrNull(summaryJson['final_ordering_uses_diversity']) ??
          _toBoolOrNull(summaryJson['finalOrderingUsesDiversity']) ??
          ((_cleanText(summaryJson['ranking_stage']) ??
                  _cleanText(summaryJson['rankingStage']) ??
                  '') ==
              'post_diversity'),
      finalScoreMatchesFinalRanking:
          _toBoolOrNull(summaryJson['final_score_matches_final_ranking']) ??
          _toBoolOrNull(summaryJson['finalScoreMatchesFinalRanking']) ??
          !diversityEnabled,
      items: parsedItems,
      selectedCount: selectedCount,
      rejectedCount: rejectedCount,
      pipelineConfig: pipelineConfig,
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

  String? get primaryExplanationSource {
    final fromConfig =
        _cleanText(pipelineConfig['explanation_source']) ??
        _cleanText(pipelineConfig['explanationSource']) ??
        _cleanText(pipelineConfig['multimodal_explanation_backend']) ??
        _cleanText(pipelineConfig['multimodalExplanationBackend']);
    if (fromConfig != null) {
      return fromConfig;
    }
    for (final item in rankedItems) {
      final source = item.explanationSource?.trim();
      if (source != null && source.isNotEmpty) {
        return source;
      }
    }
    return null;
  }

  String? get resolvedPhotoTypeMode {
    return _cleanText(pipelineConfig['photo_type_mode']) ??
        _cleanText(pipelineConfig['photoTypeMode']);
  }

  String get displaySummary {
    if (selectedItems.isEmpty) {
      return '아직 선택 결과가 도착하지 않았어요.';
    }
    return '선택된 컷 $selectedCount장과 제외된 컷 $rejectedCount장을 정리했어요.';
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
    return null;
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

  static int? _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
