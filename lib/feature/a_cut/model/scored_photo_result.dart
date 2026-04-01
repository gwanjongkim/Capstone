import 'package:photo_manager/photo_manager.dart';

import 'photo_type_mode.dart';

enum ScoreStatus { pending, success, failed }

class ScoredPhotoResult {
  final AssetEntity asset;
  final String fileName;
  final int selectedIndex;
  final ScoreStatus status;
  final double? aestheticScore;
  final List<double>? aestheticDistribution;
  final double? technicalScore;
  final List<double>? technicalDistribution;
  final int? rank;
  final bool isACut;
  final String? errorMessage;
  final PhotoTypeMode photoTypeMode;

  const ScoredPhotoResult({
    required this.asset,
    required this.fileName,
    required this.selectedIndex,
    required this.status,
    required this.photoTypeMode,
    this.aestheticScore,
    this.aestheticDistribution,
    this.technicalScore,
    this.technicalDistribution,
    this.rank,
    this.isACut = false,
    this.errorMessage,
  });

  /// wA * aestheticScore + wT * technicalScore
  double? get finalScore {
    if (aestheticScore == null && technicalScore == null) return null;

    final wA = photoTypeMode.aestheticWeight;
    final wT = photoTypeMode.technicalWeight;

    // Fallback: 한쪽 점수만 있는 경우 해당 점수 반환 혹은 가중치 조정
    if (aestheticScore != null && technicalScore != null) {
      return (wA * aestheticScore!) + (wT * technicalScore!);
    }
    return aestheticScore ?? technicalScore;
  }

  ScoredPhotoResult copyWith({
    ScoreStatus? status,
    double? aestheticScore,
    List<double>? aestheticDistribution,
    double? technicalScore,
    List<double>? technicalDistribution,
    int? rank,
    bool? isACut,
    String? errorMessage,
    bool clearErrorMessage = false,
    PhotoTypeMode? photoTypeMode,
  }) {
    return ScoredPhotoResult(
      asset: asset,
      fileName: fileName,
      selectedIndex: selectedIndex,
      status: status ?? this.status,
      aestheticScore: aestheticScore ?? this.aestheticScore,
      aestheticDistribution:
          aestheticDistribution ?? this.aestheticDistribution,
      technicalScore: technicalScore ?? this.technicalScore,
      technicalDistribution:
          technicalDistribution ?? this.technicalDistribution,
      rank: rank,
      isACut: isACut ?? this.isACut,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      photoTypeMode: photoTypeMode ?? this.photoTypeMode,
    );
  }
}
