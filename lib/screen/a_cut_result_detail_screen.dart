import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

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

  const AcutResultDetailScreen({
    super.key,
    required this.item,
    required this.asset,
    this.generatedAt,
    this.rankingStage,
    this.scoreSemantics,
  });

  @override
  Widget build(BuildContext context) {
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
                    const SizedBox(height: 18),
                    _HeaderCard(item: item),
                    const SizedBox(height: 12),
                    _ReasonCard(
                      title: '짧은 이유',
                      body: item.acutShortReason ?? '짧은 설명이 아직 없어요.',
                    ),
                    const SizedBox(height: 12),
                    _ReasonCard(
                      title: '상세 이유',
                      body: item.acutDetailedReason ?? '상세 설명이 아직 없어요.',
                    ),
                    if ((item.acutComparisonReason ?? '')
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ReasonCard(
                        title: '비교 이유',
                        body: item.acutComparisonReason!,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _ScoreCard(item: item),
                    if ((scoreSemantics ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ReasonCard(
                        title: '점수 해석',
                        body: scoreSemantics!,
                        icon: Icons.info_outline_rounded,
                      ),
                    ],
                    if (generatedAt != null ||
                        (rankingStage ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(_buildFooterText(), style: AppTextStyles.caption12),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildFooterText() {
    final parts = <String>[];
    if ((rankingStage ?? '').trim().isNotEmpty) {
      parts.add('stage: $rankingStage');
    }
    if (generatedAt != null) {
      parts.add('generated: ${generatedAt!.toLocal()}');
    }
    return parts.join(' | ');
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

  const _HeaderCard({required this.item});

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
              _InfoChip(label: item.scoreLabel),
            ],
          ),
          const SizedBox(height: 12),
          Text(item.imageFileName, style: AppTextStyles.caption12),
          const SizedBox(height: 8),
          Text(item.primaryReason, style: AppTextStyles.title16),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final AcutResultItem item;

  const _ScoreCard({required this.item});

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
          Text('점수 정보', style: AppTextStyles.title16),
          const SizedBox(height: 12),
          _MetricRow(label: 'base_score', value: _formatDouble(item.baseScore)),
          _MetricRow(
            label: 'final_score_after_rerank',
            value: _formatDouble(item.finalScoreAfterRerank),
          ),
          _MetricRow(
            label: 'vila_score_raw',
            value: _formatDouble(item.vilaScoreRaw),
          ),
          _MetricRow(
            label: 'vila_score_normalized_in_pool',
            value: _formatDouble(item.vilaScoreNormalizedInPool),
          ),
        ],
      ),
    );
  }

  String _formatDouble(double? value) {
    if (value == null) {
      return '-';
    }
    return value.toStringAsFixed(3);
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
  final IconData icon;

  const _ReasonCard({
    required this.title,
    required this.body,
    this.icon = Icons.auto_awesome_outlined,
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
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryText),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.title16),
            ],
          ),
          const SizedBox(height: 12),
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
