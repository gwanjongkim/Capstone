import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/a_cut_controller.dart';
import '../feature/a_cut/model/explanation_payload_builder.dart';
import '../feature/a_cut/model/photo_type_mode.dart';
import '../models/acut_result.dart';
import '../models/acut_result_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import 'a_cut_result_detail_screen.dart';

class ACutResultScreen extends StatefulWidget {
  final List<AssetEntity> selectedAssets;
  final PhotoTypeMode initialPhotoTypeMode;

  const ACutResultScreen({
    super.key,
    required this.selectedAssets,
    required this.initialPhotoTypeMode,
  });

  @override
  State<ACutResultScreen> createState() => _ACutResultScreenState();
}

class _ACutResultScreenState extends State<ACutResultScreen> {
  static const int _defaultTopK = 5;

  final AcutController _controller = AcutController();
  late PhotoTypeMode _photoTypeMode;

  @override
  void initState() {
    super.initState();
    _photoTypeMode = widget.initialPhotoTypeMode;
    _startAnalysis();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startAnalysis() {
    if (widget.selectedAssets.isEmpty) {
      return Future<void>.value();
    }
    return _controller.startAnalysis(
      assets: widget.selectedAssets,
      photoTypeMode: _photoTypeMode,
      topK: _defaultTopK,
      enableDiversity: false,
    );
  }

  void _changeType(PhotoTypeMode mode) {
    if (_photoTypeMode == mode || _controller.isBusy) {
      return;
    }
    setState(() {
      _photoTypeMode = mode;
    });
    _startAnalysis();
  }

  void _openDetail(AcutResultItem item) {
    final result = _controller.result;
    final asset = _controller.assetForItem(item);
    final explanationRequest = result == null
        ? null
        : ExplanationPayloadBuilder.fromFirebaseResult(
            result: result,
            item: item,
            photoTypeMode: _photoTypeMode,
            asset: asset,
          );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AcutResultDetailScreen(
          item: item,
          asset: asset,
          generatedAt: result?.generatedAt,
          rankingStage: result?.rankingStage,
          scoreSemantics: result?.scoreSemantics,
          photoTypeMode: _photoTypeMode.backendValue,
          explanationRequest: explanationRequest,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final result = _controller.result;
        return Scaffold(
          backgroundColor: const Color(0xFFF7F7F7),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: AppTopBar(
                    title: 'A컷 추천',
                    onBack: () => Navigator.of(context).pop(),
                    trailingWidth: 90,
                    trailing: GestureDetector(
                      onTap: _controller.isBusy ? null : _startAnalysis,
                      child: Text(
                        '재분석',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _controller.isBusy
                              ? AppColors.lightText
                              : AppColors.primaryText,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PhotoTypeRow(
                  selected: _photoTypeMode,
                  enabled: !_controller.isBusy,
                  onSelected: _changeType,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _AnalysisStatusCard(
                    controller: _controller,
                    totalSelected: widget.selectedAssets.length,
                    onCancel: _controller.canCancel
                        ? () {
                            _controller.cancelAnalysis();
                          }
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(child: _buildBody(result)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(AcutResult? result) {
    if (widget.selectedAssets.isEmpty) {
      return const _RankingStateCard(
        icon: Icons.photo_library_outlined,
        title: '선택된 사진이 없어요',
        description: '갤러리에서 사진을 2장 이상 선택하면 A컷 랭킹을 볼 수 있어요.',
      );
    }

    if (result == null) {
      if (_controller.status == AcutControllerStatus.cancelled) {
        return _RankingStateCard(
          icon: Icons.block_rounded,
          title: '분석을 취소했어요',
          description: _controller.statusDescription,
        );
      }

      if (_controller.status == AcutControllerStatus.error) {
        return _RankingStateCard(
          icon: Icons.error_outline_rounded,
          title: '분석을 완료하지 못했어요',
          description: _controller.errorMessage ?? 'Firebase 작업을 다시 시작해 주세요.',
        );
      }

      return _RankingStateCard(
        icon: Icons.auto_awesome_rounded,
        title: _controller.statusLabel,
        description: _controller.statusDescription,
        loading: true,
      );
    }

    final bestItem = result.bestItem;
    final showNotice =
        result.rejectedCount > 0 ||
        result.diversityEnabled ||
        !result.finalScoreMatchesFinalRanking;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      children: [
        _SummaryHeader(
          result: result,
          totalSelected: widget.selectedAssets.length,
          photoTypeMode: _photoTypeMode,
        ),
        if (bestItem != null) ...[
          const SizedBox(height: 14),
          _BestShotHighlight(
            item: bestItem,
            asset: _controller.assetForItem(bestItem),
            onTap: () => _openDetail(bestItem),
          ),
        ],
        if (result.topPicks.isNotEmpty) ...[
          const SizedBox(height: 18),
          _TopPickSection(
            picks: result.topPicks,
            assetForItem: _controller.assetForItem,
            onTap: _openDetail,
          ),
        ],
        if (showNotice) ...[
          const SizedBox(height: 18),
          _RankingNoticeCard(result: result),
        ],
        const SizedBox(height: 18),
        const Text(
          '전체 순위',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 10),
        ...result.rankedItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _openDetail(item),
              child: _ResultCard(
                item: item,
                asset: _controller.assetForItem(item),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalysisStatusCard extends StatelessWidget {
  final AcutController controller;
  final int totalSelected;
  final VoidCallback? onCancel;

  const _AnalysisStatusCard({
    required this.controller,
    required this.totalSelected,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = controller.estimatedProgress;
    final percent = (progress * 100).round().clamp(0, 100);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _headline,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: AppColors.track,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primaryText,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(_secondaryLine, style: AppTextStyles.body13),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaPill(label: '$totalSelected장 선택'),
              if (controller.job != null)
                _MetaPill(label: 'job ${controller.job!.id.substring(0, 8)}'),
              if (controller.result != null)
                _MetaPill(
                  label:
                      '선택 ${controller.result!.selectedCount}/$totalSelected',
                ),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('작업 취소'),
            ),
          ],
        ],
      ),
    );
  }

  String get _headline {
    switch (controller.status) {
      case AcutControllerStatus.done:
        return 'Firebase 결과를 불러왔어요';
      case AcutControllerStatus.error:
        return '분석에 문제가 생겼어요';
      case AcutControllerStatus.cancelled:
        return '분석이 취소됐어요';
      default:
        return controller.statusLabel;
    }
  }

  String get _secondaryLine {
    switch (controller.status) {
      case AcutControllerStatus.uploading:
        return 'Firebase Storage 업로드 후 Firestore 작업 생성까지 진행합니다.';
      case AcutControllerStatus.queued:
      case AcutControllerStatus.running:
        return controller.statusDescription;
      case AcutControllerStatus.done:
        return controller.result?.displaySummary ??
            controller.statusDescription;
      case AcutControllerStatus.error:
      case AcutControllerStatus.cancelled:
      case AcutControllerStatus.idle:
      case AcutControllerStatus.authenticating:
      case AcutControllerStatus.cancelling:
        return controller.statusDescription;
    }
  }
}

class _SummaryHeader extends StatelessWidget {
  final AcutResult result;
  final int totalSelected;
  final PhotoTypeMode photoTypeMode;

  const _SummaryHeader({
    required this.result,
    required this.totalSelected,
    required this.photoTypeMode,
  });

  @override
  Widget build(BuildContext context) {
    final sourceParts = <String>[result.displaySource];
    if (result.rankingStage.trim().isNotEmpty &&
        result.rankingStage.trim() != 'unknown') {
      sourceParts.add(result.rankingStage);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.displayTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              _ModeBadge(label: photoTypeMode.label),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.displaySummary,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryStatChip(
                label: 'BEST',
                value: result.bestItem == null ? '-' : '#1',
              ),
              _SummaryStatChip(
                label: 'Top 3',
                value: '${result.topPicks.length}장',
              ),
              _SummaryStatChip(
                label: '추천 컷',
                value: '${result.selectedItems.length}장',
              ),
              _SummaryStatChip(
                label: '분석 완료',
                value: '${result.items.length}/$totalSelected',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            sourceParts.join(' · '),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.lightText,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStatChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryStatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestShotHighlight extends StatelessWidget {
  final AcutResultItem item;
  final AssetEntity? asset;
  final VoidCallback onTap;

  const _BestShotHighlight({
    required this.item,
    required this.asset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: FutureBuilder<Uint8List?>(
                      future: asset?.thumbnailDataWithSize(
                        const ThumbnailSize(720, 720),
                      ),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data == null) {
                          return Container(
                            color: const Color(0xFFEDEFF3),
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.lightText,
                              size: 36,
                            ),
                          );
                        }
                        return Image.memory(snapshot.data!, fit: BoxFit.cover);
                      },
                    ),
                  ),
                  const Positioned(
                    left: 16,
                    top: 16,
                    child: _HighlightPill(
                      label: 'BEST PICK',
                      background: Color(0xFF111827),
                      foreground: Colors.white,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 16,
                    child: _HighlightPill(
                      label: item.rankLabel,
                      background: Colors.white,
                      foreground: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '가장 먼저 확인할 추천 컷',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFCA8A04),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.imageFileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.primaryReason,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HighlightPill(
                        label: item.scoreLabel,
                        background: const Color(0xFF111827),
                        foreground: Colors.white,
                      ),
                      _HighlightPill(
                        label: item.verdictLabel,
                        background: const Color(0xFFF8FAFC),
                        foreground: AppColors.primaryText,
                      ),
                      _HighlightPill(
                        label: item.selectedBadgeLabel,
                        background: const Color(0xFFFFF7CC),
                        foreground: const Color(0xFF92400E),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopPickSection extends StatelessWidget {
  final List<AcutResultItem> picks;
  final AssetEntity? Function(AcutResultItem item) assetForItem;
  final ValueChanged<AcutResultItem> onTap;

  const _TopPickSection({
    required this.picks,
    required this.assetForItem,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top 3 추천 컷',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '상위 추천 컷을 먼저 훑어본 뒤 전체 순위를 확인해 보세요.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 12),
        ...picks.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => onTap(item),
              child: _ResultCard(
                item: item,
                asset: assetForItem(item),
                compact: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RankingNoticeCard extends StatelessWidget {
  final AcutResult result;

  const _RankingNoticeCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final messages = <String>[];
    if (result.rejectedCount > 0) {
      messages.add('후보에서 제외된 사진 ${result.rejectedCount}장이 있어요.');
    }
    if (result.diversityEnabled) {
      messages.add('다양성 옵션이 적용된 결과예요.');
    }
    if (result.finalOrderingUsesDiversity &&
        !result.finalScoreMatchesFinalRanking) {
      messages.add('최종 순위는 diversity 재정렬을 반영해 점수 순서와 일부 다를 수 있어요.');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: messages
            .map(
              (message) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final AcutResultItem item;
  final AssetEntity? asset;
  final bool compact;

  const _ResultCard({
    required this.item,
    required this.asset,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final thumbSize = compact ? 82.0 : 92.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: item.isRecommendedPick
              ? const Color(0xFFE2E8F0)
              : Colors.transparent,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: thumbSize,
                  height: thumbSize,
                  child: FutureBuilder<Uint8List?>(
                    future: asset?.thumbnailDataWithSize(
                      const ThumbnailSize(320, 320),
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data == null) {
                        return Container(
                          color: const Color(0xFFEDEFF3),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.lightText,
                          ),
                        );
                      }
                      return Image.memory(snapshot.data!, fit: BoxFit.cover);
                    },
                  ),
                ),
              ),
              Positioned(left: 8, top: 8, child: _RankBadge(item: item)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.imageFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HighlightPill(
                      label: item.highlightLabel,
                      background: item.isBestShot
                          ? const Color(0xFF111827)
                          : const Color(0xFFF1F5F9),
                      foreground: item.isBestShot
                          ? Colors.white
                          : AppColors.primaryText,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.recommendationLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.primaryReason,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaPill(label: item.rankLabel),
                    _MetaPill(label: item.verdictLabel),
                    if (item.selected && !item.isTopThree)
                      const _MetaPill(label: 'A컷 후보'),
                    _MetaPill(label: item.scoreLabel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool loading;

  const _RankingStateCard({
    required this.icon,
    required this.title,
    required this.description,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryText,
                  ),
                )
              else
                Icon(icon, size: 42, color: AppColors.primaryText),
              if (!loading) const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: AppTextStyles.body13,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _HighlightPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;

  const _MetaPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final AcutResultItem item;

  const _RankBadge({required this.item});

  Color get _background {
    if (item.isBestShot) {
      return const Color(0xFF111827);
    }
    if (item.isTopThree) {
      return const Color(0xFF2563EB);
    }
    if (item.selected) {
      return const Color(0xFF0F766E);
    }
    return const Color(0xFF334155);
  }

  String get _label {
    if (item.isBestShot) {
      return 'BEST';
    }
    if (item.rank > 0) {
      return '${item.rank}위';
    }
    return item.statusLabel;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final String label;

  const _ModeBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label 모드',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryText,
        ),
      ),
    );
  }
}

class _PhotoTypeRow extends StatelessWidget {
  final PhotoTypeMode selected;
  final bool enabled;
  final ValueChanged<PhotoTypeMode> onSelected;

  const _PhotoTypeRow({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: PhotoTypeMode.values
            .map((mode) {
              final active = selected == mode;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: mode == PhotoTypeMode.values.last ? 0 : 8,
                  ),
                  child: GestureDetector(
                    onTap: enabled ? () => onSelected(mode) : null,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: enabled ? 1.0 : 0.65,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 38,
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFFEFEFEF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Center(
                          child: Text(
                            mode.label,
                            style: TextStyle(
                              color: active
                                  ? Colors.white
                                  : const Color(0xFF5A5A5A),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}
