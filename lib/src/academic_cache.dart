/// 考试与成绩本地离线缓存。
///
/// 将考试与成绩按学期索引落盘持久化至应用程序私有数据目录：
///  - 考试缓存：`zf-exam-cache.json`
///  - 成绩缓存：`zf-grades-cache.json`
/// 支持按学期多版本持久化与冷启动 0 延迟秒开读取。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:zf_academic/zf_academic.dart';

import 'safe_json_file.dart';

/// 按学期分桶持久化学业数据的共享安全文件读写器（消除考试与成绩缓存重复逻辑）。
class _TermJsonCacheStore<T> {
  _TermJsonCacheStore(File file, {required this.fromJson, required this.toJson})
    : _store = SafeJsonFile(file);

  final SafeJsonFile _store;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T value) toJson;

  static bool _isValidRoot(Object? decoded) =>
      decoded is Map<String, dynamic> &&
      decoded['terms'] is Map<String, dynamic>;

  Map<String, T> _decodeMap(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return <String, T>{};
    final termsMap = decoded['terms'];
    if (termsMap is! Map<String, dynamic>) return <String, T>{};
    final result = <String, T>{};
    termsMap.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        try {
          result[key] = fromJson(value);
        } catch (_) {}
      }
    });
    return result;
  }

  Future<T?> load(String termId) async {
    final all = await loadAll();
    return all[termId];
  }

  Future<Map<String, T>> loadAll() async {
    try {
      final res = await _store.readJson(isValid: _isValidRoot);
      if (res.data == null) {
        if (res.hadUnrecoverableCorruption) {
          await _store.clear();
        }
        return <String, T>{};
      }
      return _decodeMap(res.data);
    } catch (_) {
      return <String, T>{};
    }
  }

  Future<void> saveTerm(String termId, T item) async {
    try {
      await _store.updateJson(
        isValid: _isValidRoot,
        transform: (current) {
          final merged = _decodeMap(current);
          merged[termId] = item;
          return <String, dynamic>{
            'updatedAt': DateTime.now().toIso8601String(),
            'terms': merged.map((key, value) => MapEntry(key, toJson(value))),
          };
        },
      );
    } catch (_) {}
  }

  Future<void> clear() => _store.clear();
}

/// 已缓存的单学期考试数据。
class CachedTermExams {
  const CachedTermExams({
    required this.termId,
    required this.items,
    required this.fetchedAt,
  });

  final String termId;
  final List<ExamItem> items;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'termId': termId,
    'fetchedAt': fetchedAt.toIso8601String(),
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory CachedTermExams.fromJson(Map<String, dynamic> json) {
    final termId = (json['termId'] as String?) ?? '';
    final fetchedAt =
        DateTime.tryParse((json['fetchedAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final rawItems = json['items'] as List<dynamic>? ?? const <dynamic>[];
    final items = <ExamItem>[
      for (final raw in rawItems)
        if (raw is Map<String, dynamic>) ExamItem.fromJson(raw),
    ];
    return CachedTermExams(termId: termId, items: items, fetchedAt: fetchedAt);
  }
}

/// 考试缓存存取契约。
abstract class ExamCache {
  Future<CachedTermExams?> load(String termId);

  Future<Map<String, CachedTermExams>> loadAll();

  Future<void> save(String termId, List<ExamItem> items);

  Future<void> clear();
}

/// 文件实现：app 私有目录下的 JSON 文件。
class FileExamCache implements ExamCache {
  FileExamCache._(File file) : this.fromFile(file);

  FileExamCache.fromFile(File file)
    : _store = _TermJsonCacheStore<CachedTermExams>(
        file,
        fromJson: CachedTermExams.fromJson,
        toJson: (item) => item.toJson(),
      );

  final _TermJsonCacheStore<CachedTermExams> _store;

  static Future<FileExamCache> open({
    String fileName = 'zf-exam-cache.json',
  }) async {
    final directory = await getApplicationSupportDirectory();
    return FileExamCache._(File('${directory.path}/$fileName'));
  }

  @override
  Future<CachedTermExams?> load(String termId) => _store.load(termId);

  @override
  Future<Map<String, CachedTermExams>> loadAll() => _store.loadAll();

  @override
  Future<void> save(String termId, List<ExamItem> items) => _store.saveTerm(
    termId,
    CachedTermExams(termId: termId, items: items, fetchedAt: DateTime.now()),
  );

  @override
  Future<void> clear() => _store.clear();
}

/// 占位实现：目录未初始化前使用。
class LateExamCache implements ExamCache {
  @override
  Future<CachedTermExams?> load(String termId) async => null;

  @override
  Future<Map<String, CachedTermExams>> loadAll() async =>
      const <String, CachedTermExams>{};

  @override
  Future<void> save(String termId, List<ExamItem> items) async {}

  @override
  Future<void> clear() async {}
}

/// 内存实现：测试用。
class InMemoryExamCache implements ExamCache {
  final Map<String, CachedTermExams> _data = <String, CachedTermExams>{};

  @override
  Future<CachedTermExams?> load(String termId) async => _data[termId];

  @override
  Future<Map<String, CachedTermExams>> loadAll() async =>
      Map<String, CachedTermExams>.unmodifiable(_data);

  @override
  Future<void> save(String termId, List<ExamItem> items) async {
    _data[termId] = CachedTermExams(
      termId: termId,
      items: items,
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Future<void> clear() async => _data.clear();
}

// ---------------------------------------------------------------------------
// 成绩离线缓存
// ---------------------------------------------------------------------------

/// 已缓存的单学期成绩数据。
class CachedTermGrades {
  const CachedTermGrades({
    required this.termId,
    required this.items,
    required this.fetchedAt,
    this.isNotEvaluated = false,
  });

  final String termId;
  final List<GradeItem> items;
  final DateTime fetchedAt;
  final bool isNotEvaluated;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'termId': termId,
    'fetchedAt': fetchedAt.toIso8601String(),
    'isNotEvaluated': isNotEvaluated,
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory CachedTermGrades.fromJson(Map<String, dynamic> json) {
    final termId = (json['termId'] as String?) ?? '';
    final fetchedAt =
        DateTime.tryParse((json['fetchedAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final isNotEvaluated = json['isNotEvaluated'] == true;
    final rawItems = json['items'] as List<dynamic>? ?? const <dynamic>[];
    final items = <GradeItem>[
      for (final raw in rawItems)
        if (raw is Map<String, dynamic>) GradeItem.fromJson(raw),
    ];
    return CachedTermGrades(
      termId: termId,
      items: items,
      fetchedAt: fetchedAt,
      isNotEvaluated: isNotEvaluated,
    );
  }
}

/// 成绩缓存存取契约。
abstract class GradesCache {
  Future<CachedTermGrades?> load(String termId);

  Future<Map<String, CachedTermGrades>> loadAll();

  Future<void> save(
    String termId,
    List<GradeItem> items, {
    bool isNotEvaluated = false,
  });

  Future<void> clear();
}

/// 文件实现：app 私有目录下的 JSON 文件。
class FileGradesCache implements GradesCache {
  FileGradesCache._(File file) : this.fromFile(file);

  FileGradesCache.fromFile(File file)
    : _store = _TermJsonCacheStore<CachedTermGrades>(
        file,
        fromJson: CachedTermGrades.fromJson,
        toJson: (item) => item.toJson(),
      );

  final _TermJsonCacheStore<CachedTermGrades> _store;

  static Future<FileGradesCache> open({
    String fileName = 'zf-grades-cache.json',
  }) async {
    final directory = await getApplicationSupportDirectory();
    return FileGradesCache._(File('${directory.path}/$fileName'));
  }

  @override
  Future<CachedTermGrades?> load(String termId) => _store.load(termId);

  @override
  Future<Map<String, CachedTermGrades>> loadAll() => _store.loadAll();

  @override
  Future<void> save(
    String termId,
    List<GradeItem> items, {
    bool isNotEvaluated = false,
  }) => _store.saveTerm(
    termId,
    CachedTermGrades(
      termId: termId,
      items: items,
      fetchedAt: DateTime.now(),
      isNotEvaluated: isNotEvaluated,
    ),
  );

  @override
  Future<void> clear() => _store.clear();
}

/// 占位实现：目录未初始化前使用。
class LateGradesCache implements GradesCache {
  @override
  Future<CachedTermGrades?> load(String termId) async => null;

  @override
  Future<Map<String, CachedTermGrades>> loadAll() async =>
      const <String, CachedTermGrades>{};

  @override
  Future<void> save(
    String termId,
    List<GradeItem> items, {
    bool isNotEvaluated = false,
  }) async {}

  @override
  Future<void> clear() async {}
}

/// 内存实现：测试用。
class InMemoryGradesCache implements GradesCache {
  final Map<String, CachedTermGrades> _data = <String, CachedTermGrades>{};

  @override
  Future<CachedTermGrades?> load(String termId) async => _data[termId];

  @override
  Future<Map<String, CachedTermGrades>> loadAll() async =>
      Map<String, CachedTermGrades>.unmodifiable(_data);

  @override
  Future<void> save(
    String termId,
    List<GradeItem> items, {
    bool isNotEvaluated = false,
  }) async {
    _data[termId] = CachedTermGrades(
      termId: termId,
      items: items,
      fetchedAt: DateTime.now(),
      isNotEvaluated: isNotEvaluated,
    );
  }

  @override
  Future<void> clear() async => _data.clear();
}
