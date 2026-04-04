import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/a_cut_controller.dart';
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AcutResultDetailScreen(
          item: item,
          asset: _controller.assetForItem(item),
          generatedAt: result?.generatedAt,
          rankingStage: result?.rankingStage,
          scoreSemantics: result?.scoreSemantics,
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
                    title: 'A컷 분석',
                    onBack: () => Navigator.of(context).pop(),
                    trailingWidth: 90,
                    trailing: GestureDetector(
                      onTap: _controller.isBusy ? null : () { _startAnalysis(); },
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
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _StatusBanner(
                    controller: _controller,
                    selectedCount: widget.selectedAssets.length,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _buildBody(result),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(AcutResult? result) {
    if (widget.selectedAssets.isEmpty) {
      return const _StateCard(
        icon: Icons.photo_library_outlined,
        title: '선택된 사진이 없어요',
        description: '갤러리에서 사진을 2장 이상 선택하면 A컷 분석을 시작할 수 있어요.',
      );
    }

    if (result == null) {
      if (_controller.status == AcutControllerStatus.error) {
        return _StateCard(
          icon: Icons.error_outline_rounded,
          title: '분석을 완료하지 못했어요',
          description: _controller.errorMessage ?? 'Firebase 작업을 다시 시작해 주세요.',
          actionLabel: '다시 시도',
          onAction: () { _startAnalysis(); },
        );
      }

      return _StateCard(
        icon: Icons.auto_awesome_rounded,
        title: _controller.statusLabel,
        description: _controller.statusDescription,
        loading: true,
      );
    }

    final selectedItems = result.selectedItems;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
      children: [
        _ResultSummaryCard(result: result),
        const SizedBox(height: 14),
        _MetadataCard(result: result),
        if (selectedItems.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _SectionHeader(
            title: '선택된 컷',
            subtitle: '앱에서 바로 보여줄 최종 A컷 결과예요.',
          ),
          const SizedBox(height: 10),
          ...selectedItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ResultCard(
                item: item,
                asset: _controller.assetForItem(item),
                onTap: () => _openDetail(item),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        const _SectionHeader(
          title: '전체 결과',
          subtitle: '순위와 짧은 이유를 함께 확인할 수 있어요.',
        ),
        const SizedBox(height: 10),
        ...result.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ResultCard(
              item: item,
              asset: _controller.assetForItem(item),
              onTap: () => _openDetail(item),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final AcutController controller;
  final int selectedCount;

  const _StatusBanner({
    required this.controller,
    required this.selectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _progressValue(controller);
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
                  controller.statusLabel,
                  style: AppTextStyles.title16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$selectedCount장',
                  style: AppTextStyles.caption12.copyWith(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(controller.statusDescription, style: AppTextStyles.body13),
          if (controller.job != null) ...[
            const SizedBox(height: 8),
            Text(
              'Job ID: ${controller.job!.id}',
              style: AppTextStyles.caption12,
            ),
          ],
          const SizedBox(height: 12),
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
        ],
      ),
    );
  }

  double? _progressValue(AcutController controller) {
    switch (controller.status) {
      case AcutControllerStatus.idle:
        return 0.0;
      case AcutControllerStatus.uploading:
        return controller.uploadProgress.clamp(0.0, 1.0).toDouble();
      case AcutControllerStatus.queued:
        return 0.35;
      case AcutControllerStatus.running:
        return 0.72;
      case AcutControllerStatus.done:
        return 1.0;
      case AcutControllerStatus.error:
        return 1.0;
    }
  }
}

class _ResultSummaryCard extends StatelessWidget {
  final AcutResult result;

  const _ResultSummaryCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final bestItem = result.bestItem;
    return Container(
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
              const Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.primaryText,
              ),
              const SizedBox(width: 8),
              Text('A컷 분석 완료', style: AppTextStyles.title18),
            ],
          ),
          const SizedBox(height: 10),
          Text(result.displaySummary, style: AppTextStyles.body14),
          if (bestItem != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BEST #${bestItem.rank}',
                    style: AppTextStyles.caption12.copyWith(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(bestItem.primaryReason, style: AppTextStyles.body14),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final AcutResult result;

  const _MetadataCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final generatedAt = result.generatedAt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MetadataChip(label: result.schemaVersion),
              const SizedBox(width: 8),
              _MetadataChip(label: result.rankingStage),
              const SizedBox(width: 8),
              _MetadataChip(label: result.diversityEnabled ? 'diversity on' : 'diversity off'),
            ],
          ),
          if (generatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '생성 시각: ${generatedAt.toLocal()}',
              style: AppTextStyles.caption12,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            result.scoreSemantics,
            style: AppTextStyles.body13.copyWith(color: AppColors.primaryText),
          ),
        ],
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  final String label;

  const _MetadataChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption12.copyWith(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.title16),
        const SizedBox(height: 4),
        Text(subtitle, style: AppTextStyles.body13),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final AcutResultItem item;
  final AssetEntity? asset;
  final VoidCallback onTap;

  const _ResultCard({
    required this.item,
    required this.asset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppShadows.card,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AssetPreview(asset: asset, fallbackLabel: item.imageFileName),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(item.rankLabel, style: AppTextStyles.title16),
                          const SizedBox(width: 8),
                          _ResultBadge(item: item),
                          const Spacer(),
                          Text(item.scoreLabel, style: AppTextStyles.caption12),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.imageFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption12.copyWith(
                          color: AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.primaryReason,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body14,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final AcutResultItem item;

  const _ResultBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    final isSelected = item.selected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE9FFF5) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        item.selectedBadgeLabel,
        style: AppTextStyles.caption12.copyWith(
          color: isSelected ? AppColors.pass : AppColors.primaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AssetPreview extends StatelessWidget {
  final AssetEntity? asset;
  final String fallbackLabel;

  const _AssetPreview({
    required this.asset,
    required this.fallbackLabel,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = _PreviewPlaceholder(label: fallbackLabel);
    if (asset == null) {
      return placeholder;
    }

    return FutureBuilder<Uint8List?>(
      future: asset!.thumbnailDataWithSize(const ThumbnailSize(240, 240)),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return placeholder;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 88,
            height: 88,
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  final String label;

  const _PreviewPlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          label.isEmpty ? 'IMG' : label,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption12,
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.description,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryText,
                  ),
                )
              else
                Icon(icon, size: 44, color: AppColors.secondaryText),
              const SizedBox(height: 16),
              Text(title, style: AppTextStyles.title18, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: AppTextStyles.body13,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.buttonDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
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
        children: PhotoTypeMode.values.map((mode) {
          final isSelected = mode == selected;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: mode == PhotoTypeMode.values.last ? 0 : 8,
              ),
              child: GestureDetector(
                onTap: enabled ? () => onSelected(mode) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryText : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppShadows.card,
                  ),
                  child: Center(
                    child: Text(
                      mode.label,
                      style: AppTextStyles.body14.copyWith(
                        color: isSelected ? Colors.white : AppColors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
