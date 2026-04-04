import 'package:cloud_firestore/cloud_firestore.dart';

enum AcutJobStatus { queued, running, done, error, unknown }

class AcutInputFile {
  final String uploadFileName;
  final String displayName;
  final String storagePath;
  final int selectedIndex;

  const AcutInputFile({
    required this.uploadFileName,
    required this.displayName,
    required this.storagePath,
    required this.selectedIndex,
  });

  factory AcutInputFile.fromMap(Map<String, dynamic> json) {
    return AcutInputFile(
      uploadFileName: json['uploadFileName'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      storagePath: json['storagePath'] as String? ?? '',
      selectedIndex: (json['selectedIndex'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'uploadFileName': uploadFileName,
        'displayName': displayName,
        'storagePath': storagePath,
        'selectedIndex': selectedIndex,
      };
}

class AcutJob {
  final String id;
  final AcutJobStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? userId;
  final int imageCount;
  final String inputStoragePrefix;
  final String outputStoragePrefix;
  final String? errorMessage;
  final Map<String, dynamic>? summary;
  final int? topK;
  final List<AcutInputFile> inputFiles;
  final Map<String, dynamic> outputs;
  final String? schemaVersion;
  final String? rankingStage;
  final String? scoreSemantics;
  final bool diversityEnabled;

  const AcutJob({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    required this.imageCount,
    required this.inputStoragePrefix,
    required this.outputStoragePrefix,
    required this.errorMessage,
    required this.summary,
    required this.topK,
    required this.inputFiles,
    required this.outputs,
    required this.schemaVersion,
    required this.rankingStage,
    required this.scoreSemantics,
    required this.diversityEnabled,
  });

  factory AcutJob.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return AcutJob(
      id: snapshot.id,
      status: _parseStatus(data['status'] as String?),
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
      userId: data['userId'] as String?,
      imageCount: (data['imageCount'] as num?)?.toInt() ?? 0,
      inputStoragePrefix: data['inputStoragePrefix'] as String? ?? '',
      outputStoragePrefix: data['outputStoragePrefix'] as String? ?? '',
      errorMessage: data['errorMessage'] as String?,
      summary: _toStringDynamicMap(data['summary']),
      topK: _toIntOrNull(data['topK']),
      inputFiles: ((data['inputFiles'] as List<dynamic>?) ?? const [])
          .map(_toStringDynamicMap)
          .whereType<Map<String, dynamic>>()
          .map(AcutInputFile.fromMap)
          .toList(growable: false),
      outputs: _toStringDynamicMap(data['outputs']) ?? const {},
      schemaVersion: data['schemaVersion'] as String?,
      rankingStage: data['rankingStage'] as String?,
      scoreSemantics: data['scoreSemantics'] as String?,
      diversityEnabled: data['diversityEnabled'] as bool? ?? false,
    );
  }

  bool get isDone => status == AcutJobStatus.done;

  bool get isError => status == AcutJobStatus.error;

  bool get isRunning => status == AcutJobStatus.running;

  bool get isQueued => status == AcutJobStatus.queued;

  String? get appResultsJsonPath => outputs['appResultsJsonPath'] as String?;

  String? get topKSummaryJsonPath => outputs['topKSummaryJsonPath'] as String?;

  String? get reviewSheetCsvPath => outputs['reviewSheetCsvPath'] as String?;

  static AcutJobStatus _parseStatus(String? value) {
    switch (value) {
      case 'queued':
        return AcutJobStatus.queued;
      case 'running':
        return AcutJobStatus.running;
      case 'done':
        return AcutJobStatus.done;
      case 'error':
        return AcutJobStatus.error;
      default:
        return AcutJobStatus.unknown;
    }
  }

  static DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static Map<String, dynamic>? _toStringDynamicMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static int? _toIntOrNull(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
