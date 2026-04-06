import 'package:photo_manager/photo_manager.dart';

import '../../models/acut_job.dart';
import '../../models/acut_result.dart';
import '../../services/acut_firebase_service.dart';
import 'model/photo_type_mode.dart';

class AcutRepository {
  AcutRepository({AcutFirebaseService? service})
    : _service = service ?? AcutFirebaseService();

  final AcutFirebaseService _service;

  Future<AcutJob> startAnalysis({
    required List<AssetEntity> assets,
    required PhotoTypeMode photoTypeMode,
    required int topK,
    required bool enableDiversity,
    void Function(int uploaded, int total)? onUploadProgress,
  }) {
    return _service.submitAnalysisJob(
      assets: assets,
      topK: topK,
      enableDiversity: enableDiversity,
      photoTypeMode: photoTypeMode.backendValue,
      onUploadProgress: onUploadProgress,
    );
  }

  Stream<AcutJob> watchJob(String jobId) => _service.watchJob(jobId);

  Future<AcutResult> fetchResult(AcutJob job) => _service.fetchResult(job);

  Future<AcutJob> cancelJob(String jobId) => _service.cancelAnalysisJob(jobId);
}
