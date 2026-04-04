import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/acut_job.dart';
import '../../models/acut_result.dart';
import '../../models/acut_result_item.dart';
import 'a_cut_repository.dart';
import 'model/photo_type_mode.dart';

enum AcutControllerStatus { idle, uploading, queued, running, done, error }

class AcutController extends ChangeNotifier {
  AcutController({
    AcutRepository? repository,
  }) : _repository = repository ?? AcutRepository();

  final AcutRepository _repository;

  StreamSubscription<AcutJob>? _jobSubscription;
  final Map<String, AssetEntity> _assetsByUploadFileName = {};

  List<AssetEntity> _selectedAssets = const [];
  PhotoTypeMode _photoTypeMode = PhotoTypeMode.auto;
  int _topK = 5;
  bool _enableDiversity = false;
  bool _fetchingResult = false;

  AcutControllerStatus _status = AcutControllerStatus.idle;
  AcutJob? _job;
  AcutResult? _result;
  String? _errorMessage;
  double _uploadProgress = 0.0;

  AcutControllerStatus get status => _status;

  AcutJob? get job => _job;

  AcutResult? get result => _result;

  String? get errorMessage => _errorMessage;

  double get uploadProgress => _uploadProgress;

  bool get isBusy =>
      _status == AcutControllerStatus.uploading ||
      _status == AcutControllerStatus.queued ||
      _status == AcutControllerStatus.running;

  String get statusLabel {
    switch (_status) {
      case AcutControllerStatus.idle:
        return '대기 중';
      case AcutControllerStatus.uploading:
        return '업로드 중';
      case AcutControllerStatus.queued:
        return '분석 대기 중';
      case AcutControllerStatus.running:
        return '분석 중';
      case AcutControllerStatus.done:
        return '분석 완료';
      case AcutControllerStatus.error:
        return '오류';
    }
  }

  String get statusDescription {
    switch (_status) {
      case AcutControllerStatus.idle:
        return '분석을 시작하면 Firebase 작업이 만들어져요.';
      case AcutControllerStatus.uploading:
        return '선택한 사진을 Firebase Storage로 업로드하고 있어요.';
      case AcutControllerStatus.queued:
        return '작업이 큐에 등록되었어요. 백엔드 워커가 순서대로 분석을 시작합니다.';
      case AcutControllerStatus.running:
        return 'A-cut 선택과 설명 생성이 진행 중이에요.';
      case AcutControllerStatus.done:
        return '최종 A컷 결과와 설명이 준비되었어요.';
      case AcutControllerStatus.error:
        return _errorMessage ?? '분석을 완료하지 못했어요.';
    }
  }

  Future<void> startAnalysis({
    required List<AssetEntity> assets,
    required PhotoTypeMode photoTypeMode,
    int topK = 5,
    bool enableDiversity = false,
  }) async {
    await _jobSubscription?.cancel();
    _selectedAssets = assets;
    _photoTypeMode = photoTypeMode;
    _topK = topK;
    _enableDiversity = enableDiversity;
    _assetsByUploadFileName.clear();

    _status = AcutControllerStatus.uploading;
    _job = null;
    _result = null;
    _errorMessage = null;
    _uploadProgress = 0.0;
    _fetchingResult = false;
    notifyListeners();

    try {
      final job = await _repository.startAnalysis(
        assets: assets,
        photoTypeMode: photoTypeMode,
        topK: topK,
        enableDiversity: enableDiversity,
        onUploadProgress: (uploaded, total) {
          _uploadProgress = total == 0 ? 0.0 : uploaded / total;
          notifyListeners();
        },
      );

      for (final inputFile in job.inputFiles) {
        if (inputFile.selectedIndex >= 0 && inputFile.selectedIndex < assets.length) {
          _assetsByUploadFileName[inputFile.uploadFileName] =
              assets[inputFile.selectedIndex];
        }
      }

      _job = job;
      _status = _mapJobStatus(job.status);
      notifyListeners();

      if (job.isDone) {
        _loadResult(job);
      }

      _jobSubscription = _repository.watchJob(job.id).listen(
        _handleJobUpdate,
        onError: (Object error) {
          _status = AcutControllerStatus.error;
          _errorMessage = error.toString();
          notifyListeners();
        },
      );
    } catch (error) {
      _status = AcutControllerStatus.error;
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> retry() {
    if (_selectedAssets.isEmpty) {
      return Future<void>.value();
    }
    return startAnalysis(
      assets: _selectedAssets,
      photoTypeMode: _photoTypeMode,
      topK: _topK,
      enableDiversity: _enableDiversity,
    );
  }

  AssetEntity? assetForItem(AcutResultItem item) {
    return _assetsByUploadFileName[item.imageFileName];
  }

  void _handleJobUpdate(AcutJob job) {
    _job = job;
    if (job.isError) {
      _status = AcutControllerStatus.error;
      _errorMessage = job.errorMessage ?? '분석 작업이 실패했어요.';
      notifyListeners();
      return;
    }

    _status = _mapJobStatus(job.status);
    notifyListeners();

    if (job.isDone) {
      _loadResult(job);
    }
  }

  Future<void> _loadResult(AcutJob job) async {
    if (_fetchingResult) {
      return;
    }
    _fetchingResult = true;
    try {
      final result = await _repository.fetchResult(job);
      _result = result;
      _status = AcutControllerStatus.done;
      notifyListeners();
    } catch (error) {
      _status = AcutControllerStatus.error;
      _errorMessage = error.toString();
      notifyListeners();
    } finally {
      _fetchingResult = false;
    }
  }

  AcutControllerStatus _mapJobStatus(AcutJobStatus status) {
    switch (status) {
      case AcutJobStatus.queued:
        return AcutControllerStatus.queued;
      case AcutJobStatus.running:
        return AcutControllerStatus.running;
      case AcutJobStatus.done:
        return AcutControllerStatus.done;
      case AcutJobStatus.error:
        return AcutControllerStatus.error;
      case AcutJobStatus.unknown:
        return AcutControllerStatus.idle;
    }
  }

  @override
  void dispose() {
    _jobSubscription?.cancel();
    super.dispose();
  }
}
