import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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

  static const int _normalizedJpegQuality = 95;

  Future<AcutJob> submitAnalysisJob({
    required List<AssetEntity> assets,
    required int topK,
    required bool enableDiversity,
    required String photoTypeMode,
    void Function(int uploaded, int total)? onUploadProgress,
  }) async {
    _ensureFirebaseConfigured();

    return _runGuarded(() async {
      await _authService.ensureSignedIn();
      debugPrint(
        '[AUTH] currentUser(before upload)=${FirebaseAuth.instance.currentUser?.uid}',
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Anonymous auth not ready before upload');
      }
      debugPrint('[ACUT] auth ready uid=${user.uid}');

      final requestedJobId = _firestore.collection(_jobsCollection).doc().id;
      final inputStoragePrefix = 'acut_jobs/$requestedJobId/inputs';
      final outputStoragePrefix = 'acut_jobs/$requestedJobId/outputs';
      final inputFiles = <AcutInputFile>[];

      for (var index = 0; index < assets.length; index++) {
        final uploaded = await _uploadAsset(
          asset: assets[index],
          selectedIndex: index,
          jobId: requestedJobId,
          inputStoragePrefix: inputStoragePrefix,
          ownerUid: user.uid,
        );
        inputFiles.add(uploaded);
        onUploadProgress?.call(index + 1, assets.length);
      }

      final uploadedPaths = inputFiles
          .map((file) => file.storagePath)
          .toList(growable: false);
      debugPrint('[ACUT] upload complete jobId=$requestedJobId');
      debugPrint('[ACUT] uploadedPaths=$uploadedPaths');

      final callable = _functions.httpsCallable('enqueueAcutAnalysis');
      final enqueuePayload = <String, dynamic>{
        'jobId': requestedJobId,
        'imageCount': assets.length,
        'inputStoragePrefix': inputStoragePrefix,
        'outputStoragePrefix': outputStoragePrefix,
        'topK': topK,
        'enableDiversity': enableDiversity,
        'inputFiles': inputFiles.map((file) => file.toMap()).toList(),
        'uploadedPaths': uploadedPaths,
        'outputs': _buildOutputs(outputStoragePrefix),
        'clientContext': <String, dynamic>{'photoTypeMode': photoTypeMode},
        'pipelineConfig': <String, dynamic>{
          'topK': topK,
          'enableDiversity': enableDiversity,
        },
      };
      debugPrint('[ACUT] enqueue request payload=$enqueuePayload');
      final callableUser = FirebaseAuth.instance.currentUser;
      debugPrint('[AUTH] currentUser(before callable)=${callableUser?.uid}');
      if (callableUser == null) {
        throw Exception('Anonymous auth not ready before enqueue');
      }
      try {
        final refreshedToken = await callableUser.getIdToken(true);
        debugPrint(
          '[AUTH] getIdToken(true) success tokenPresent=${refreshedToken != null && refreshedToken.isNotEmpty}',
        );
      } catch (e, st) {
        debugPrint('[AUTH][ERROR] getIdToken(true) failed: $e');
        debugPrint('$st');
        rethrow;
      }
      debugPrint(
        '[ACUT] before enqueue callable name=enqueueAcutAnalysis region=asia-northeast3',
      );
      late final HttpsCallableResult<dynamic> result;
      try {
        result = await callable.call(enqueuePayload);
        debugPrint('[ACUT] enqueue raw result=${result.data}');
      } catch (e, st) {
        debugPrint('[ACUT][ERROR] enqueue failed: $e');
        debugPrint('$st');
        rethrow;
      }
      final responseData =
          _toStringDynamicMap(result.data) ?? const <String, dynamic>{};
      debugPrint('[ACUT] enqueue response=$responseData');

      final Map<String, dynamic> responseJobData =
          _toStringDynamicMap(responseData['job']) ?? responseData;
      final jobId =
          _readString(responseData['jobId']) ??
          _readString(responseJobData['jobId']) ??
          requestedJobId;

      final initialJobData = _buildInitialJobData(
        responseData: responseJobData,
        fallbackUserId: user.uid,
        fallbackImageCount: assets.length,
        fallbackTopK: topK,
        fallbackInputFiles: inputFiles,
        fallbackInputStoragePrefix:
            _readString(responseData['inputStoragePrefix']) ??
            inputStoragePrefix,
        fallbackOutputStoragePrefix:
            _readString(responseData['outputStoragePrefix']) ??
            outputStoragePrefix,
        fallbackEnableDiversity: enableDiversity,
      );

      return AcutJob.fromMap(id: jobId, data: initialJobData);
    });
  }

  Stream<AcutJob> watchJob(String jobId) {
    _ensureFirebaseConfigured();
    debugPrint('[ACUT] job listener start jobId=$jobId');
    return _watchJobAuthenticated(jobId);
  }

  Future<AcutResult> fetchResult(AcutJob job) async {
    _ensureFirebaseConfigured();
    debugPrint('[ACUT] result fetch start jobId=${job.id}');
    try {
      final result = await _runGuarded(() async {
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
      debugPrint(
        '[ACUT] result fetch success jobId=${job.id} selectedCount=${result.selectedCount}',
      );
      return result;
    } catch (error, st) {
      debugPrint('[ACUT][ERROR] result fetch failed jobId=${job.id}: $error');
      debugPrint('$st');
      rethrow;
    }
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
    final payload = await _prepareUploadPayload(asset);

    final title = await asset.titleAsync;
    final baseName = _buildUploadBaseName(
      selectedIndex: selectedIndex,
      originalTitle: title,
      fallbackId: asset.id,
    );
    final fileName = '$baseName.${payload.extension}';
    final storagePath = '$inputStoragePrefix/$fileName';
    final displayName = title.trim().isEmpty ? fileName : title;

    debugPrint(
      '[AcutFirebaseService] Uploading A-cut asset '
      'assetId=${asset.id} selectedIndex=$selectedIndex '
      'sourceFormat=${payload.sourceFormat} uploadFormat=${payload.uploadFormat} '
      'normalizedToJpeg=${payload.normalizedToJpeg} fileName=$fileName '
      'byteLength=${payload.bytes.length}',
    );

    await _storage
        .ref(storagePath)
        .putData(
          payload.bytes,
          SettableMetadata(
            contentType: payload.contentType,
            customMetadata: {
              'selectedIndex': '$selectedIndex',
              'assetId': asset.id,
              'displayName': displayName,
              'ownerUid': ownerUid,
              'jobId': jobId,
              'sourceFormat': payload.sourceFormat,
              'uploadedFormat': payload.uploadFormat,
              'normalizedToJpeg': payload.normalizedToJpeg ? 'true' : 'false',
              'uploadedContentType': payload.contentType,
            },
          ),
        );

    return AcutInputFile(
      uploadFileName: fileName,
      displayName: displayName,
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

  Map<String, dynamic> _buildOutputs(String outputStoragePrefix) => {
    'appResultsJsonPath': '$outputStoragePrefix/app_results.json',
    'topKSummaryJsonPath': '$outputStoragePrefix/top_k_summary.json',
    'reviewSheetCsvPath': '$outputStoragePrefix/review_sheet.csv',
  };

  Map<String, dynamic> _buildInitialJobData({
    required Map<String, dynamic> responseData,
    required String fallbackUserId,
    required int fallbackImageCount,
    required int fallbackTopK,
    required List<AcutInputFile> fallbackInputFiles,
    required String fallbackInputStoragePrefix,
    required String fallbackOutputStoragePrefix,
    required bool fallbackEnableDiversity,
  }) {
    final resolvedOutputStoragePrefix =
        _readString(responseData['outputStoragePrefix']) ??
        fallbackOutputStoragePrefix;

    return <String, dynamic>{
      'status': _readString(responseData['status']) ?? 'queued',
      'createdAt': responseData['createdAt'] ?? DateTime.now(),
      'updatedAt': responseData['updatedAt'] ?? DateTime.now(),
      'userId': _readString(responseData['userId']) ?? fallbackUserId,
      'imageCount':
          _toIntOrNull(responseData['imageCount']) ?? fallbackImageCount,
      'inputStoragePrefix':
          _readString(responseData['inputStoragePrefix']) ??
          fallbackInputStoragePrefix,
      'outputStoragePrefix': resolvedOutputStoragePrefix,
      'errorMessage': responseData['errorMessage'],
      'summary': _toStringDynamicMap(responseData['summary']),
      'topK': _toIntOrNull(responseData['topK']) ?? fallbackTopK,
      'inputFiles':
          (responseData['inputFiles'] as List<dynamic>?) ??
          fallbackInputFiles.map((file) => file.toMap()).toList(),
      'outputs':
          _toStringDynamicMap(responseData['outputs']) ??
          _buildOutputs(resolvedOutputStoragePrefix),
      'schemaVersion': _readString(responseData['schemaVersion']),
      'rankingStage': _readString(responseData['rankingStage']),
      'scoreSemantics': _readString(responseData['scoreSemantics']),
      'diversityEnabled':
          _toBoolOrNull(responseData['diversityEnabled']) ??
          _toBoolOrNull(responseData['enableDiversity']) ??
          fallbackEnableDiversity,
      'error': _toStringDynamicMap(responseData['error']),
      'finalOrderingUsesDiversity':
          _toBoolOrNull(responseData['finalOrderingUsesDiversity']) ??
          fallbackEnableDiversity,
      'finalScoreMatchesFinalRanking':
          _toBoolOrNull(responseData['finalScoreMatchesFinalRanking']) ??
          !fallbackEnableDiversity,
    };
  }

  String _buildUploadBaseName({
    required int selectedIndex,
    required String originalTitle,
    required String fallbackId,
  }) {
    final trimmed = originalTitle.trim();
    final rawName = trimmed.isEmpty ? fallbackId : trimmed;
    final sanitized = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final baseName = sanitized.contains('.')
        ? sanitized.substring(0, sanitized.lastIndexOf('.'))
        : sanitized;
    final prefix = selectedIndex.toString().padLeft(3, '0');
    return '${prefix}_${baseName.isEmpty ? 'photo' : baseName}';
  }

  Future<_PreparedUploadPayload> _prepareUploadPayload(
    AssetEntity asset,
  ) async {
    Uint8List? bytes = await asset.originBytes;
    if (bytes == null || bytes.isEmpty) {
      final originFile = await asset.originFile;
      if (originFile != null && await originFile.exists()) {
        bytes = await originFile.readAsBytes();
      }
    }
    if (bytes == null || bytes.isEmpty) {
      throw StateError('선택한 이미지 원본을 읽지 못했어요. (assetId=${asset.id})');
    }

    final sourceFormat = _detectImageFormat(bytes);
    if (sourceFormat == _UploadImageFormat.unknown) {
      throw StateError(
        '지원되지 않는 이미지 포맷이에요. '
        '(assetId=${asset.id}, headerHex=${_headerHexPreview(bytes)})',
      );
    }

    if (sourceFormat == _UploadImageFormat.jpeg) {
      return _PreparedUploadPayload(
        bytes: bytes,
        extension: 'jpg',
        contentType: 'image/jpeg',
        sourceFormat: _formatLabel(sourceFormat),
        uploadFormat: 'jpeg',
        normalizedToJpeg: false,
      );
    }

    if (sourceFormat == _UploadImageFormat.heic ||
        sourceFormat == _UploadImageFormat.heif) {
      return _PreparedUploadPayload(
        bytes: bytes,
        extension: sourceFormat == _UploadImageFormat.heif ? 'heif' : 'heic',
        contentType: sourceFormat == _UploadImageFormat.heif
            ? 'image/heif'
            : 'image/heic',
        sourceFormat: _formatLabel(sourceFormat),
        uploadFormat: _formatLabel(sourceFormat),
        normalizedToJpeg: false,
      );
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError(
        '이미지를 디코딩하지 못했어요. '
        '(assetId=${asset.id}, sourceFormat=${_formatLabel(sourceFormat)}, headerHex=${_headerHexPreview(bytes)})',
      );
    }
    final normalized = Uint8List.fromList(
      img.encodeJpg(decoded, quality: _normalizedJpegQuality),
    );
    if (normalized.isEmpty) {
      throw StateError('JPEG 변환 결과가 비어 있어 업로드를 중단했어요. (assetId=${asset.id})');
    }
    return _PreparedUploadPayload(
      bytes: normalized,
      extension: 'jpg',
      contentType: 'image/jpeg',
      sourceFormat: _formatLabel(sourceFormat),
      uploadFormat: 'jpeg',
      normalizedToJpeg: true,
    );
  }

  _UploadImageFormat _detectImageFormat(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
      if (brand.startsWith('he') || brand == 'mif1' || brand == 'msf1') {
        if (brand == 'heif') {
          return _UploadImageFormat.heif;
        }
        return _UploadImageFormat.heic;
      }
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return _UploadImageFormat.jpeg;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return _UploadImageFormat.png;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return _UploadImageFormat.webp;
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return _UploadImageFormat.bmp;
    }
    return _UploadImageFormat.unknown;
  }

  String _formatLabel(_UploadImageFormat format) {
    switch (format) {
      case _UploadImageFormat.jpeg:
        return 'jpeg';
      case _UploadImageFormat.png:
        return 'png';
      case _UploadImageFormat.webp:
        return 'webp';
      case _UploadImageFormat.bmp:
        return 'bmp';
      case _UploadImageFormat.heic:
        return 'heic';
      case _UploadImageFormat.heif:
        return 'heif';
      case _UploadImageFormat.unknown:
        return 'unknown';
    }
  }

  String _headerHexPreview(Uint8List bytes, {int maxBytes = 24}) {
    final end = bytes.length < maxBytes ? bytes.length : maxBytes;
    final sb = StringBuffer();
    for (var i = 0; i < end; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
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

  Map<String, dynamic>? _toStringDynamicMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  int? _toIntOrNull(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  bool? _toBoolOrNull(Object? value) {
    if (value is bool) {
      return value;
    }
    return null;
  }

  String? _readString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }
}

enum _UploadImageFormat { unknown, jpeg, png, webp, bmp, heic, heif }

class _PreparedUploadPayload {
  const _PreparedUploadPayload({
    required this.bytes,
    required this.extension,
    required this.contentType,
    required this.sourceFormat,
    required this.uploadFormat,
    required this.normalizedToJpeg,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
  final String sourceFormat;
  final String uploadFormat;
  final bool normalizedToJpeg;
}
