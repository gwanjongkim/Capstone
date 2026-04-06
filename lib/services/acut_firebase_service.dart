import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:photo_manager/photo_manager.dart';

import '../firebase_bootstrap.dart';
import '../models/acut_job.dart';
import '../models/acut_result.dart';
import 'firebase_auth_service.dart';

class AcutFirebaseService {
  AcutFirebaseService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
    FirebaseAuthService? authService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: _functionsRegion),
       _authService = authService ?? FirebaseAuthService.instance;

  static const String _jobsCollection = 'jobs';
  static const String _functionsRegion = 'asia-northeast3';

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final FirebaseAuthService _authService;

  Future<AcutJob> submitAnalysisJob({
    required List<AssetEntity> assets,
    required int topK,
    required bool enableDiversity,
    required String photoTypeMode,
    void Function(int uploaded, int total)? onUploadProgress,
  }) async {
    _ensureFirebaseConfigured();

    return _runGuarded(() async {
      final user = await _authService.ensureSignedIn();
      final docRef = _firestore.collection(_jobsCollection).doc();
      final jobId = docRef.id;
      final inputStoragePrefix = 'acut_jobs/$jobId/inputs';
      final outputStoragePrefix = 'acut_jobs/$jobId/outputs';
      final inputFiles = <AcutInputFile>[];

      for (var index = 0; index < assets.length; index++) {
        final uploaded = await _uploadAsset(
          asset: assets[index],
          selectedIndex: index,
          jobId: jobId,
          inputStoragePrefix: inputStoragePrefix,
          ownerUid: user.uid,
        );
        inputFiles.add(uploaded);
        onUploadProgress?.call(index + 1, assets.length);
      }

      final callable = _functions.httpsCallable('enqueueAcutAnalysis');
      await callable.call(<String, dynamic>{
        'jobId': jobId,
        'imageCount': assets.length,
        'inputStoragePrefix': inputStoragePrefix,
        'outputStoragePrefix': outputStoragePrefix,
        'topK': topK,
        'enableDiversity': enableDiversity,
        'inputFiles': inputFiles.map((file) => file.toMap()).toList(),
        'clientContext': <String, dynamic>{'photoTypeMode': photoTypeMode},
        'pipelineConfig': <String, dynamic>{
          'topK': topK,
          'enableDiversity': enableDiversity,
        },
      });

      final snapshot = await docRef.get();
      if (snapshot.exists) {
        return AcutJob.fromSnapshot(snapshot);
      }

      return AcutJob(
        id: jobId,
        status: AcutJobStatus.queued,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        userId: user.uid,
        imageCount: assets.length,
        inputStoragePrefix: inputStoragePrefix,
        outputStoragePrefix: outputStoragePrefix,
        errorMessage: null,
        summary: null,
        topK: topK,
        inputFiles: inputFiles,
        outputs: {
          'appResultsJsonPath': '$outputStoragePrefix/app_results.json',
          'topKSummaryJsonPath': '$outputStoragePrefix/top_k_summary.json',
          'reviewSheetCsvPath': '$outputStoragePrefix/review_sheet.csv',
        },
        schemaVersion: null,
        rankingStage: null,
        scoreSemantics: null,
        diversityEnabled: enableDiversity,
        errorCode: null,
        errorDetails: null,
        finalOrderingUsesDiversity: enableDiversity,
        finalScoreMatchesFinalRanking: !enableDiversity,
      );
    });
  }

  Stream<AcutJob> watchJob(String jobId) {
    _ensureFirebaseConfigured();
    return _watchJobAuthenticated(jobId);
  }

  Future<AcutResult> fetchResult(AcutJob job) async {
    _ensureFirebaseConfigured();
    return _runGuarded(() async {
      await _authService.ensureSignedIn();
      final appResultsPath =
          job.appResultsJsonPath ??
          '${job.outputStoragePrefix}/app_results.json';
      final topKSummaryPath =
          job.topKSummaryJsonPath ??
          '${job.outputStoragePrefix}/top_k_summary.json';

      final appResultsBytes = await _storage
          .ref(appResultsPath)
          .getData(5 * 1024 * 1024);
      final topKSummaryBytes = await _storage
          .ref(topKSummaryPath)
          .getData(2 * 1024 * 1024);
      if (appResultsBytes == null || topKSummaryBytes == null) {
        throw StateError(
          '분석은 완료되었지만 결과 파일을 아직 읽지 못했어요. '
          'Firebase Storage 경로와 워커 업로드 상태를 확인해 주세요.',
        );
      }

      final itemsJson =
          jsonDecode(utf8.decode(appResultsBytes)) as List<dynamic>;
      final summaryJson =
          jsonDecode(utf8.decode(topKSummaryBytes)) as Map<String, dynamic>;
      return AcutResult.fromPayload(
        itemsJson: itemsJson,
        summaryJson: summaryJson,
      );
    });
  }

  Future<AcutJob> cancelAnalysisJob(String jobId) async {
    _ensureFirebaseConfigured();
    return _runGuarded(() async {
      await _authService.ensureSignedIn();
      final callable = _functions.httpsCallable('cancelAcutAnalysis');
      await callable.call(<String, dynamic>{'jobId': jobId});
      final snapshot = await _firestore
          .collection(_jobsCollection)
          .doc(jobId)
          .get();
      if (!snapshot.exists) {
        throw StateError('취소 후 작업 문서를 다시 읽지 못했어요.');
      }
      return AcutJob.fromSnapshot(snapshot);
    });
  }

  Future<AcutInputFile> _uploadAsset({
    required AssetEntity asset,
    required int selectedIndex,
    required String jobId,
    required String inputStoragePrefix,
    required String ownerUid,
  }) async {
    final bytes = await asset.originBytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('선택한 이미지 원본을 읽지 못했어요.');
    }

    final title = await asset.titleAsync;
    final fileName = _buildUploadFileName(
      selectedIndex: selectedIndex,
      originalTitle: title,
      fallbackId: asset.id,
    );
    final storagePath = '$inputStoragePrefix/$fileName';

    await _storage
        .ref(storagePath)
        .putData(
          bytes,
          SettableMetadata(
            contentType: _contentTypeForFileName(fileName),
            customMetadata: {
              'selectedIndex': '$selectedIndex',
              'assetId': asset.id,
              'displayName': title,
              'ownerUid': ownerUid,
              'jobId': jobId,
            },
          ),
        );

    return AcutInputFile(
      uploadFileName: fileName,
      displayName: title.trim().isEmpty ? fileName : title,
      storagePath: storagePath,
      selectedIndex: selectedIndex,
    );
  }

  void _ensureFirebaseConfigured() {
    if (Firebase.apps.isEmpty) {
      FirebaseBootstrap.throwIfUnavailable();
    }
  }

  Stream<AcutJob> _watchJobAuthenticated(String jobId) async* {
    await _runGuarded(() => _authService.ensureSignedIn());
    yield* _firestore
        .collection(_jobsCollection)
        .doc(jobId)
        .snapshots()
        .where((snapshot) => snapshot.exists)
        .map(AcutJob.fromSnapshot)
        .handleError((Object error) {
          throw StateError(_userFacingFirebaseError(error));
        });
  }

  Future<T> _runGuarded<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseFunctionsException catch (error) {
      throw StateError(_userFacingFunctionsError(error));
    } on FirebaseException catch (error) {
      throw StateError(_userFacingFirebaseException(error));
    }
  }

  String _buildUploadFileName({
    required int selectedIndex,
    required String originalTitle,
    required String fallbackId,
  }) {
    final trimmed = originalTitle.trim();
    final rawName = trimmed.isEmpty ? fallbackId : trimmed;
    final sanitized = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final extension = sanitized.contains('.')
        ? sanitized.substring(sanitized.lastIndexOf('.'))
        : '.jpg';
    final baseName = sanitized.contains('.')
        ? sanitized.substring(0, sanitized.lastIndexOf('.'))
        : sanitized;
    final prefix = selectedIndex.toString().padLeft(3, '0');
    return '${prefix}_${baseName.isEmpty ? 'photo' : baseName}$extension';
  }

  String _contentTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  String _userFacingFunctionsError(FirebaseFunctionsException error) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return _userFacingFirebaseException(error);
  }

  String _userFacingFirebaseException(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Firebase 권한이 없어요. Storage/Firestore 규칙과 로그인 상태를 확인해 주세요.';
      case 'unauthenticated':
        return 'Firebase 인증이 필요해요. 실제 프로젝트 연결 후 로그인 경로를 확인해 주세요.';
      case 'object-not-found':
        return '필요한 Firebase Storage 파일을 찾지 못했어요.';
      case 'unavailable':
        return 'Firebase 서비스에 연결하지 못했어요. 네트워크와 프로젝트 설정을 확인해 주세요.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
        return 'Firebase 요청을 처리하지 못했어요. 코드: ${error.code}';
    }
  }

  String _userFacingFirebaseError(Object error) {
    if (error is FirebaseFunctionsException) {
      return _userFacingFunctionsError(error);
    }
    if (error is FirebaseException) {
      return _userFacingFirebaseException(error);
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }
}
