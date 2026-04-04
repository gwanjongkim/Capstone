import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/acut_job.dart';
import '../models/acut_result.dart';

class AcutFirebaseService {
  AcutFirebaseService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functions = functions ?? FirebaseFunctions.instanceFor(region: _functionsRegion);

  static const String _jobsCollection = 'jobs';
  static const String _functionsRegion = 'asia-northeast3';

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  Future<AcutJob> submitAnalysisJob({
    required List<AssetEntity> assets,
    required int topK,
    required bool enableDiversity,
    required String photoTypeMode,
    void Function(int uploaded, int total)? onUploadProgress,
  }) async {
    _ensureFirebaseConfigured();

    final docRef = _firestore.collection(_jobsCollection).doc();
    final jobId = docRef.id;
    final inputStoragePrefix = 'acut_jobs/$jobId/inputs';
    final outputStoragePrefix = 'acut_jobs/$jobId/outputs';
    final inputFiles = <AcutInputFile>[];

    for (var index = 0; index < assets.length; index++) {
      final uploaded = await _uploadAsset(
        asset: assets[index],
        selectedIndex: index,
        inputStoragePrefix: inputStoragePrefix,
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
      'clientContext': <String, dynamic>{
        'photoTypeMode': photoTypeMode,
      },
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
      userId: null,
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
    );
  }

  Stream<AcutJob> watchJob(String jobId) {
    _ensureFirebaseConfigured();
    return _firestore
        .collection(_jobsCollection)
        .doc(jobId)
        .snapshots()
        .where((snapshot) => snapshot.exists)
        .map(AcutJob.fromSnapshot);
  }

  Future<AcutResult> fetchResult(AcutJob job) async {
    _ensureFirebaseConfigured();
    final appResultsPath =
        job.appResultsJsonPath ?? '${job.outputStoragePrefix}/app_results.json';
    final topKSummaryPath =
        job.topKSummaryJsonPath ?? '${job.outputStoragePrefix}/top_k_summary.json';

    final appResultsBytes = await _storage.ref(appResultsPath).getData(5 * 1024 * 1024);
    final topKSummaryBytes = await _storage.ref(topKSummaryPath).getData(2 * 1024 * 1024);
    if (appResultsBytes == null || topKSummaryBytes == null) {
      throw StateError('분석 결과 파일을 Firebase Storage에서 읽지 못했어요.');
    }

    final itemsJson = jsonDecode(utf8.decode(appResultsBytes)) as List<dynamic>;
    final summaryJson =
        jsonDecode(utf8.decode(topKSummaryBytes)) as Map<String, dynamic>;
    return AcutResult.fromPayload(
      itemsJson: itemsJson,
      summaryJson: summaryJson,
    );
  }

  Future<AcutInputFile> _uploadAsset({
    required AssetEntity asset,
    required int selectedIndex,
    required String inputStoragePrefix,
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

    await _storage.ref(storagePath).putData(
          bytes,
          SettableMetadata(
            contentType: _contentTypeForFileName(fileName),
            customMetadata: {
              'selectedIndex': '$selectedIndex',
              'assetId': asset.id,
              'displayName': title,
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
      throw StateError(
        'Firebase가 초기화되지 않았어요. firebase_core 초기화와 플랫폼 설정 파일을 먼저 추가해 주세요.',
      );
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
}
