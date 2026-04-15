import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/model/explanation_request.dart';
import '../models/acut_result_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

class AcutResultDetailScreen extends StatelessWidget {
  final AcutResultItem item;
  final AssetEntity? asset;
  final DateTime? generatedAt;
  final String? rankingStage;
  final String? scoreSemantics;
  final String? photoTypeMode;
  final ExplanationRequest? explanationRequest;

  const AcutResultDetailScreen({
    super.key,
    required this.item,
    required this.asset,
    this.generatedAt,
    this.rankingStage,
    this.scoreSemantics,
    this.photoTypeMode,
    this.explanationRequest,
  });

  @override
  Widget build(BuildContext context) {
    final scores = explanationRequest?.scores;
    final provenance = explanationRequest?.provenance;
    final finalScore = scores?.finalScore ?? item.finalScore ?? item.baseScore;
    final technicalScore = scores?.technicalScore ?? item.technicalScore;
    final aestheticScore = scores?.aestheticScore ?? item.aestheticScore;
    final tags = explanationRequest?.compositionTags.isNotEmpty == true
        ? explanationRequest!.compositionTags
        : item.tags;
    final resolvedPhotoTypeMode =
        explanationRequest?.photoTypeMode ??
        item.photoTypeMode ??
        photoTypeMode;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: 'A컷 상세',
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailImage(
                      asset: asset,
                      fallbackLabel: item.imageFileName,
                    ),
                    const SizedBox(height: 16),
                    _HeaderCard(
                      item: item,
                      finalScore: finalScore,
                      explanationSource: item.explanationSource,
                    ),
                    const SizedBox(height: 12),
                    _ScoreGridCard(
                      finalScore: finalScore,
                      technicalScore: technicalScore,
                      aestheticScore: aestheticScore,
                      baseScore: item.baseScore,
                      vilaScoreRaw: item.vilaScoreRaw,
                    ),
                    if (tags.isNotEmpty ||
                        (resolvedPhotoTypeMode ?? '').trim().isNotEmpty ||
                        item.aestheticModelsUsed.isNotEmpty ||
                        (provenance?.aestheticBackend ?? '')
                            .trim()
                            .isNotEmpty ||
                        (item.explanationSource ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _TagCard(
                        tags: tags,
                        photoTypeMode: resolvedPhotoTypeMode,
                        aestheticModels: item.aestheticModelsUsed,
                        aestheticBackend:
                            provenance?.aestheticBackend ??
                            item.aestheticBackend,
                        explanationSource: item.explanationSource,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _ReasonCard(
                      title: '짧은 이유',
                      body: item.shortReason ?? '짧은 설명이 아직 없어요.',
                    ),
                    const SizedBox(height: 12),
                    _ReasonCard(
                      title: '상세 이유',
                      body: item.detailedReason ?? '상세 설명이 아직 없어요.',
                    ),
                    if ((item.comparisonReason ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ReasonCard(title: '비교 이유', body: item.comparisonReason!),
                    ],
                    const SizedBox(height: 12),
                    _MetadataCard(
                      rankingStage: rankingStage,
                      generatedAt: generatedAt,
                      scoreSemantics: scoreSemantics,
                      technicalSource: provenance?.technicalSource,
                      aestheticSource: provenance?.aestheticSource,
                      finalScoreSource: provenance?.finalScoreSource,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailImage extends StatelessWidget {
  final AssetEntity? asset;
  final String fallbackLabel;

  const _DetailImage({required this.asset, required this.fallbackLabel});

  @override
  Widget build(BuildContext context) {
    if (asset == null) {
      return _ImagePlaceholder(label: fallbackLabel);
    }

    return FutureBuilder<Uint8List?>(
      future: asset!.thumbnailDataWithSize(const ThumbnailSize(1600, 1600)),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _ImagePlaceholder(label: fallbackLabel);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final String label;

  const _ImagePlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 260,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          label.isEmpty ? '이미지 미리보기를 불러오지 못했어요.' : label,
          textAlign: TextAlign.center,
          style: AppTextStyles.body13,
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final AcutResultItem item;
  final double? finalScore;
  final String? explanationSource;

  const _HeaderCard({
    required this.item,
    required this.finalScore,
    required this.explanationSource,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: item.rankLabel),
              _InfoChip(label: item.selectedBadgeLabel),
              _InfoChip(
                label: _formatScoreLabel(finalScore, fallback: item.scoreLabel),
              ),
              if ((explanationSource ?? '').trim().isNotEmpty)
                _InfoChip(
                  label: _explanationSourceChipLabel(explanationSource!),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.imageFileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption12,
          ),
          const SizedBox(height: 8),
          Text(item.primaryReason, style: AppTextStyles.title16),
        ],
      ),
    );
  }
}

class _ScoreGridCard extends StatelessWidget {
  final double? finalScore;
  final double? technicalScore;
  final double? aestheticScore;
  final double? baseScore;
  final double? vilaScoreRaw;

  const _ScoreGridCard({
    required this.finalScore,
    required this.technicalScore,
    required this.aestheticScore,
    required this.baseScore,
    required this.vilaScoreRaw,
  });

  @override
  Widget build(BuildContext context) {
    final metricRows = <Widget>[
      if (baseScore != null)
        _MetricRow(label: 'base_score', value: _formatRawScore(baseScore)),
      if (vilaScoreRaw != null)
        _MetricRow(
          label: 'vila_score_raw',
          value: _formatRawScore(vilaScoreRaw),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('점수', style: AppTextStyles.title16),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ScoreTile(
                  label: '기술',
                  score: technicalScore,
                  highlight: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ScoreTile(
                  label: '미적',
                  score: aestheticScore,
                  highlight: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ScoreTile(
                  label: '최종',
                  score: finalScore,
                  highlight: true,
                ),
              ),
            ],
          ),
          if (metricRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...metricRows,
          ],
        ],
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  final String label;
  final double? score;
  final bool highlight;

  const _ScoreTile({
    required this.label,
    required this.score,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: highlight ? Colors.white70 : AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatPercentScore(score),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: highlight ? Colors.white : AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatRawScore(score),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: highlight ? Colors.white70 : AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagCard extends StatelessWidget {
  final List<String> tags;
  final String? photoTypeMode;
  final List<String> aestheticModels;
  final String? aestheticBackend;
  final String? explanationSource;

  const _TagCard({
    required this.tags,
    required this.photoTypeMode,
    required this.aestheticModels,
    required this.aestheticBackend,
    required this.explanationSource,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if ((photoTypeMode ?? '').trim().isNotEmpty)
        '모드 · ${_photoTypeLabel(photoTypeMode!)}',
      ...tags.map((tag) => _compositionTagLabel(tag)),
      ...aestheticModels.map((model) => '모델 · $model'),
      if ((aestheticBackend ?? '').trim().isNotEmpty)
        '점수 백엔드 · ${aestheticBackend!.trim()}',
      if ((explanationSource ?? '').trim().isNotEmpty)
        _explanationSourceChipLabel(explanationSource!),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('태그 및 출처', style: AppTextStyles.title16),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map(
                  (chip) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      chip,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final String? rankingStage;
  final DateTime? generatedAt;
  final String? scoreSemantics;
  final String? technicalSource;
  final String? aestheticSource;
  final String? finalScoreSource;

  const _MetadataCard({
    required this.rankingStage,
    required this.generatedAt,
    required this.scoreSemantics,
    required this.technicalSource,
    required this.aestheticSource,
    required this.finalScoreSource,
  });

  @override
  Widget build(BuildContext context) {
    final metaRows = <String>[
      if ((rankingStage ?? '').trim().isNotEmpty)
        '랭킹 단계 · ${rankingStage!.trim()}',
      if (generatedAt != null)
        '생성 시각 · ${_formatDateTime(generatedAt!.toLocal())}',
      if ((technicalSource ?? '').trim().isNotEmpty)
        '기술 점수 출처 · ${technicalSource!.trim()}',
      if ((aestheticSource ?? '').trim().isNotEmpty)
        '미적 점수 출처 · ${aestheticSource!.trim()}',
      if ((finalScoreSource ?? '').trim().isNotEmpty)
        '최종 점수 출처 · ${finalScoreSource!.trim()}',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('메타데이터', style: AppTextStyles.title16),
          if (metaRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...metaRows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(row, style: AppTextStyles.caption12),
              ),
            ),
          ],
          if ((scoreSemantics ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(scoreSemantics!.trim(), style: AppTextStyles.body13),
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.body13)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  final String title;
  final String body;

  const _ReasonCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.title16),
          const SizedBox(height: 10),
          Text(body, style: AppTextStyles.body13),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryText,
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

String _formatScoreLabel(double? score, {required String fallback}) {
  final normalized = _normalizeScore(score);
  if (normalized == null) {
    return fallback;
  }
  return '종합 ${(normalized * 100).round()}점';
}

String _formatPercentScore(double? score) {
  final normalized = _normalizeScore(score);
  if (normalized == null) {
    return '-';
  }
  return '${(normalized * 100).round()}점';
}

String _formatRawScore(double? score) {
  if (score == null) {
    return '-';
  }
  return score.toStringAsFixed(3);
}

double? _normalizeScore(double? score) {
  if (score == null) {
    return null;
  }
  final normalized = score > 1.0 && score <= 100.0 ? score / 100.0 : score;
  return normalized.clamp(0.0, 1.0).toDouble();
}

String _photoTypeLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'portrait':
      return '인물';
    case 'snap':
      return '스냅';
    case 'auto':
      return '자동';
    default:
      return raw.trim();
  }
}

String _compositionTagLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'composition':
      return '구도';
    case 'clarity':
    case 'subject_clarity':
      return '피사체 선명도';
    case 'background':
    case 'background_cleanliness':
      return '배경 정돈';
    case 'lighting':
    case 'exposure':
      return '조명';
    case 'technical_quality':
      return '기술 완성도';
    case 'aesthetic_score':
      return '미적 점수';
    case 'overall_image_appeal':
      return '전체 인상';
    default:
      return raw;
  }
}

String _explanationSourceChipLabel(String raw) {
  final label = _explanationSourceLabel(raw);
  return label == raw.trim() ? '설명 · ${raw.trim()}' : label;
}

String _explanationSourceLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'gemini_multimodal':
    case 'gemini':
    case 'firebase_server':
      return '설명 · Gemini';
    case 'vila_full_local':
    case 'nvila':
      return '설명 · NVILA';
    case 'baseline_acut':
      return '설명 · 기본 랭킹';
    default:
      return raw.trim();
  }
}
