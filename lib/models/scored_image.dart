import 'dart:io';

class ScoredImage {
  final File file;
  final String fileName;
  double aestheticScore;
  double technicalScore;
  int rank;
  bool isACut;
  bool hasError;
  String? errorMessage;

  ScoredImage({
    required this.file,
    required this.fileName,
    this.aestheticScore = 0.0,
    this.technicalScore = 0.0,
    this.rank = 0,
    this.isACut = false,
    this.hasError = false,
    this.errorMessage,
  });

  double get totalScore => aestheticScore; // Currently only using aesthetic
}
