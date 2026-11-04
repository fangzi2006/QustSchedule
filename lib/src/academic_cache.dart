/// 考试与成绩本地离线缓存。
///
/// 将考试与成绩按学期索引落盘持久化至应用程序私有数据目录：
///  - 考试缓存：`zf-exam-cache.json`
///  - 成绩缓存：`zf-grades-cache.json`
/// 支持按学期多版本持久化与冷启动 0 延迟秒开读取。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:zf_academic/zf_academic.dart';

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
  FileExamCache._(this._file);
  FileExamCache.fromFile(this._file);

  final File _file;

  static Future<FileExamCache> open({
    String fileName = 'zf-exam-cache.json',
  }) async {
    final directory = await getApplicationSupportDirectory();
    return FileExamCache._(File('${directory.path}/$fileName'));
  }

  @override
  Future<CachedTermExams?> load(String termId) async {
    final all = await loadAll();
    return all[termId];
  }

  @override
  Future<Map<String, CachedTermExams>> loadAll() async {
    try {
      if (!await _file.exists()) return const <String, CachedTermExams>{};
      final text = await _file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return const <String, CachedTermExams>{};
      }
      final termsMap = decoded['terms'] as Map<String, dynamic>?;
      if (termsMap == null) return const <String, CachedTermExams>{};

      final result = <String, CachedTermExams>{};
      termsMap.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          result[key] = CachedTermExams.fromJson(value);
        }
      });
      return result;
    } catch (_) {
      return const <String, CachedTermExams>{};
    }
  }

  @override
  Future<void> save(String termId, List<ExamItem> items) async {
    try {
      final current = Map<String, CachedTermExams>.from(await loadAll());
      current[termId] = CachedTermExams(
        termId: termId,
        items: items,
        fetchedAt: DateTime.now(),
      );

      await _file.parent.create(recursive: true);
      final jsonPayload = <String, dynamic>{
        'updatedAt': DateTime.now().toIso8601String(),
        'terms': current.map((key, value) => MapEntry(key, value.toJson())),
      };
      await _file.writeAsString(jsonEncode(jsonPayload));
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }
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
  FileGradesCache._(this._file);
  FileGradesCache.fromFile(this._file);

  final File _file;

  static Future<FileGradesCache> open({
    String fileName = 'zf-grades-cache.json',
  }) async {
    final directory = await getApplicationSupportDirectory();
    return FileGradesCache._(File('${directory.path}/$fileName'));
  }

  @override
  Future<CachedTermGrades?> load(String termId) async {
    final all = await loadAll();
    return all[termId];
  }

  @override
  Future<Map<String, CachedTermGrades>> loadAll() async {
    try {
      if (!await _file.exists()) return const <String, CachedTermGrades>{};
      final text = await _file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return const <String, CachedTermGrades>{};
      }
      final termsMap = decoded['terms'] as Map<String, dynamic>?;
      if (termsMap == null) return const <String, CachedTermGrades>{};

      final result = <String, CachedTermGrades>{};
      termsMap.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          result[key] = CachedTermGrades.fromJson(value);
        }
      });
      return result;
    } catch (_) {
      return const <String, CachedTermGrades>{};
    }
  }

  @override
  Future<void> save(
    String termId,
    List<GradeItem> items, {
    bool isNotEvaluated = false,
  }) async {
    try {
      final current = Map<String, CachedTermGrades>.from(await loadAll());
      current[termId] = CachedTermGrades(
        termId: termId,
        items: items,
        fetchedAt: DateTime.now(),
        isNotEvaluated: isNotEvaluated,
      );

      await _file.parent.create(recursive: true);
      final jsonPayload = <String, dynamic>{
        'updatedAt': DateTime.now().toIso8601String(),
        'terms': current.map((key, value) => MapEntry(key, value.toJson())),
      };
      await _file.writeAsString(jsonEncode(jsonPayload));
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }
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
