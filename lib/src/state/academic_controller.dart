/// 学业状态控制器：管理考试安排、课程成绩、GPA 统计、学期筛选与本地缓存同步。
library;

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:zf_academic/zf_academic.dart';

import '../academic_cache.dart';
import '../academic_service.dart';
import '../schedule_service.dart';
import 'hint_notice_controller.dart';

/// 独立管理学业页所需状态，继承 [ChangeNotifier] 以便学业页单独订阅，
/// 不受课表刷新、周次翻页或全局气泡变化影响。
class AcademicController extends ChangeNotifier {
  AcademicController({
    required ScheduleService service,
    required ExamCache examCache,
    required GradesCache gradesCache,
    required this._hints,
    required this._fallbackTermIdReader,
    required this._termsReader,
    required this._termsSetter,
    required this._isNeedLoginReader,
    required this._suppressStageHintsSetter,
    AcademicService? academicService,
  }) : _service = service,
       _examCache = examCache,
       _gradesCache = gradesCache,
       _academicService =
           academicService ??
           AcademicService(
             service: service,
             examCache: examCache,
             gradesCache: gradesCache,
           );

  final ScheduleService _service;
  ExamCache _examCache;
  GradesCache _gradesCache;
  AcademicService _academicService;
  final HintNoticeController _hints;
  final String Function() _fallbackTermIdReader;
  final Terms? Function() _termsReader;
  final void Function(Terms terms) _termsSetter;
  final bool Function() _isNeedLoginReader;
  final void Function(bool suppress) _suppressStageHintsSetter;

  AcademicService get academicService => _academicService;
  ExamCache get examCache => _examCache;
  GradesCache get gradesCache => _gradesCache;

  String _academicTermId = '';
  String _loadedAcademicTerm = '';

  String get academicTermId {
    if (_academicTermId.isNotEmpty) return _academicTermId;
    final currentScheduleTerm = _fallbackTermIdReader();
    if (currentScheduleTerm.isNotEmpty) return currentScheduleTerm;
    final terms = _termsReader();
    if (terms != null && terms.currentId.isNotEmpty) {
      return terms.currentId;
    }
    return '';
  }

  List<ExamItem> _exams = const <ExamItem>[];
  List<ExamItem> get exams => _exams;

  List<GradeItem> _grades = const <GradeItem>[];
  List<GradeItem> get grades => _grades;

  /// 当前学期成绩与学分绩点统计。
  GradeStats get gradeStats => GradeStats.calculate(_grades);

  bool _isNotEvaluated = false;
  bool get isNotEvaluated => _isNotEvaluated;

  bool _academicLoading = false;
  bool get academicLoading => _academicLoading;

  int _academicLoadSeq = 0;
  String? _loadingAcademicTerm;

  String? _academicError;
  String? get academicError => _academicError;

  bool _academicDataClearedForDebug = false;
  Future<void>? _academicSync;
  bool _disposed = false;

  Future<void>? get academicSyncForTest => _academicSync;

  void rebindCaches({
    ExamCache? examCache,
    GradesCache? gradesCache,
    AcademicService? academicService,
  }) {
    if (examCache != null) _examCache = examCache;
    if (gradesCache != null) _gradesCache = gradesCache;
    if (academicService != null) {
      _academicService = academicService;
    } else {
      _academicService = AcademicService(
        service: _service,
        examCache: _examCache,
        gradesCache: _gradesCache,
      );
    }
  }

  /// 切换学业查看学期。
  void setAcademicTerm(String termId) {
    if (_academicTermId == termId) return;
    _academicTermId = termId;
    loadAcademicData(termId: termId);
  }

  /// 跨天时提醒学业页重算倒计时。
  void notifyDayChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 恢复学期离线学业缓存（0 延迟展示）。
  Future<void> restoreCachedData(String termId) async {
    if (termId.isEmpty) return;
    try {
      final cachedExams = await _examCache.load(termId);
      final cachedGrades = await _gradesCache.load(termId);
      if (_disposed) return;
      if (cachedExams != null || cachedGrades != null) {
        _exams = cachedExams?.items ?? const <ExamItem>[];
        _grades = cachedGrades?.items ?? const <GradeItem>[];
        _isNotEvaluated = cachedGrades?.isNotEvaluated ?? false;
        _loadedAcademicTerm = termId;
        _academicError = null;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 加载学业数据（考试与成绩）。
  ///
  /// 若 [forceRefresh] 为 false，优先使用本地离线缓存；
  /// 若没有缓存或 [forceRefresh] 为 true，发起网络请求并落盘。
  Future<void> loadAcademicData({
    String? termId,
    bool forceRefresh = false,
    bool showHint = false,
  }) async {
    var target = termId ?? academicTermId;
    if (_academicLoading &&
        !forceRefresh &&
        target.isNotEmpty &&
        target == _loadingAcademicTerm) {
      return;
    }

    final seq = ++_academicLoadSeq;
    if (target.isEmpty) {
      final existingTerms = _termsReader();
      if (existingTerms != null && existingTerms.currentId.isNotEmpty) {
        target = existingTerms.currentId;
        _academicTermId = target;
      } else {
        try {
          final fetched = await _service.fetchTerms();
          if (_disposed || seq != _academicLoadSeq) return;
          _termsSetter(fetched);
          target = fetched.currentId;
          _academicTermId = target;
        } catch (_) {}
      }
    }
    if (_disposed || seq != _academicLoadSeq || target.isEmpty) return;

    final bool termChanged = target != _loadedAcademicTerm;

    if (!forceRefresh) {
      final cachedExams = await _examCache.load(target);
      final cachedGrades = await _gradesCache.load(target);
      if (_disposed || seq != _academicLoadSeq) return;
      if (cachedExams != null || cachedGrades != null) {
        _exams = cachedExams?.items ?? const <ExamItem>[];
        _grades = cachedGrades?.items ?? const <GradeItem>[];
        _isNotEvaluated = cachedGrades?.isNotEvaluated ?? false;
        _loadedAcademicTerm = target;
        _academicError = null;
        _academicLoading = false;
        _loadingAcademicTerm = null;
        notifyListeners();
        return;
      }
    }

    final existingExams = await _examCache.load(target);
    final existingGrades = await _gradesCache.load(target);
    if (_disposed || seq != _academicLoadSeq) return;

    if (termChanged) {
      // 切换到无缓存的新学期：清空上一学期的残留数据，避免画面串台
      _exams = const <ExamItem>[];
      _grades = const <GradeItem>[];
      _isNotEvaluated = false;
      _loadedAcademicTerm = target;
    }

    final bool isDebugCleared = _academicDataClearedForDebug;
    _academicDataClearedForDebug = false;

    _loadingAcademicTerm = target;
    _academicLoading = true;
    _academicError = null;
    notifyListeners();
    if (showHint) {
      _hints.showHint('正在更新学业数据…', scope: HintScope.academic);
    }
    String? changeMsg;

    try {
      Future<dynamic> safeRun(Future<dynamic> f) async {
        try {
          return await f;
        } catch (e) {
          return e;
        }
      }

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        safeRun(_academicService.fetchExams(target)),
        safeRun(_academicService.fetchGrades(target)),
      ]);
      if (_disposed || seq != _academicLoadSeq) return;

      final examRes = results[0];
      final gradeRes = results[1];

      if (examRes is List<ExamItem>) {
        _exams = examRes;
      } else if (examRes is AcademicError &&
          examRes.code == ErrorCode.notOpen) {
        // 考试安排未开放属于正常学期周期状态，保持静默，不提示错误
      } else if (examRes != null) {
        _academicError ??= _describeAcademicError(examRes);
      }

      if (gradeRes is List<GradeItem>) {
        _grades = gradeRes;
        _isNotEvaluated = false;
      } else if (gradeRes is AcademicError &&
          gradeRes.code == ErrorCode.notEvaluated) {
        _isNotEvaluated = true;
        final existing = await _gradesCache.load(target);
        if (_disposed || seq != _academicLoadSeq) return;
        if (existing != null && existing.items.isNotEmpty) {
          _grades = existing.items;
        }
      } else if (gradeRes != null) {
        _academicError ??= _describeAcademicError(gradeRes);
      }

      changeMsg = _diffChangeMessage(
        existingExams: existingExams?.items,
        freshExams: examRes is List<ExamItem> ? examRes : null,
        existingGrades: existingGrades?.items,
        freshGrades: gradeRes is List<GradeItem> ? gradeRes : null,
        hasOldExams: existingExams != null,
        hasOldGrades: existingGrades != null,
        isDebugCleared: isDebugCleared,
      );
    } catch (e) {
      if (!_disposed && seq == _academicLoadSeq) {
        _academicError ??= _describeAcademicError(e);
      }
    } finally {
      if (!_disposed && seq == _academicLoadSeq) {
        _academicLoading = false;
        _loadingAcademicTerm = null;
        notifyListeners();
        if (_academicError != null) {
          if (showHint) {
            _hints.showHint(
              '更新失败：$_academicError',
              error: true,
              clearAfter: const Duration(seconds: 4),
              scope: HintScope.academic,
            );
          }
        } else if (changeMsg != null) {
          _hints.clearAcademicHint();
          _hints.showAcademicUpdateHint(changeMsg);
        } else if (showHint) {
          _hints.showHint(
            '已更新',
            clearAfter: const Duration(milliseconds: 1500),
            scope: HintScope.academic,
          );
        }
      }
    }
  }

  /// 手动刷新当前学业数据。
  Future<void> refreshAcademicData({bool showHint = true}) => loadAcademicData(
    termId: academicTermId,
    forceRefresh: true,
    showHint: showHint,
  );

  /// 课程查询完成后异步非阻塞触发考试与成绩查询，不弹出阶段提示或错误气泡。
  Future<void> syncQuietly(String termId) {
    final future = _runQuietSync(termId);
    _academicSync = future;
    return future;
  }

  Future<void> _runQuietSync(String termId) async {
    _suppressStageHintsSetter(true);
    try {
      final existingExams = await _examCache.load(termId);
      final existingGrades = await _gradesCache.load(termId);
      final bool isDebugCleared = _academicDataClearedForDebug;
      _academicDataClearedForDebug = false;

      await _academicService.syncCurrentTermAsync(termId: termId);
      if (_disposed || _isNeedLoginReader()) return;
      if (academicTermId == termId) {
        await restoreCachedData(termId);
      }

      final freshExams = await _examCache.load(termId);
      final freshGrades = await _gradesCache.load(termId);
      if (_disposed || _isNeedLoginReader()) return;

      final changeMsg = _diffChangeMessage(
        existingExams: existingExams?.items,
        freshExams: freshExams?.items,
        existingGrades: existingGrades?.items,
        freshGrades: freshGrades?.items,
        hasOldExams: existingExams != null,
        hasOldGrades: existingGrades != null,
        isDebugCleared: isDebugCleared,
      );

      if (changeMsg != null) {
        _hints.showAcademicUpdateHint(changeMsg);
      }
    } catch (_) {
      // 绝不上抛或弹网络错误通知
    } finally {
      _suppressStageHintsSetter(false);
    }
  }

  /// 清除当前学期的学业数据与缓存（调试专用）。
  Future<void> clearDataForDebug() async {
    _exams = const <ExamItem>[];
    _grades = const <GradeItem>[];
    _isNotEvaluated = false;
    _loadedAcademicTerm = '';
    await _examCache.clear();
    await _gradesCache.clear();
    _academicDataClearedForDebug = true;
    _hints.clearAcademicHint();
    notifyListeners();
  }

  void resetOnSignOut() {
    _academicTermId = '';
    _loadedAcademicTerm = '';
    _exams = const <ExamItem>[];
    _grades = const <GradeItem>[];
    _isNotEvaluated = false;
    _academicError = null;
    _academicSync = null;
    notifyListeners();
    unawaited(_examCache.clear());
    unawaited(_gradesCache.clear());
  }

  void hydrateForTest({
    required String termId,
    List<ExamItem>? exams,
    List<GradeItem>? grades,
    bool isNotEvaluated = false,
  }) {
    if (exams != null) _exams = exams;
    if (grades != null) _grades = grades;
    _isNotEvaluated = isNotEvaluated;
    if (termId.isNotEmpty) {
      _academicTermId = termId;
      _loadedAcademicTerm = termId;
    }
    notifyListeners();
  }

  static String? _diffChangeMessage({
    required List<ExamItem>? existingExams,
    required List<ExamItem>? freshExams,
    required List<GradeItem>? existingGrades,
    required List<GradeItem>? freshGrades,
    required bool hasOldExams,
    required bool hasOldGrades,
    required bool isDebugCleared,
  }) {
    final bool examsChanged =
        (hasOldExams || isDebugCleared) &&
        freshExams != null &&
        !listEquals(existingExams ?? const <ExamItem>[], freshExams);
    final bool gradesChanged =
        (hasOldGrades || isDebugCleared) &&
        freshGrades != null &&
        !listEquals(existingGrades ?? const <GradeItem>[], freshGrades);

    if (examsChanged && gradesChanged) {
      return '学业数据有更新';
    } else if (examsChanged) {
      return '考试安排有更新';
    } else if (gradesChanged) {
      return '成绩有更新';
    }
    return null;
  }

  /// 归一化学业数据加载错误，为用户呈现友好且具备指导性的提示文案。
  static String _describeAcademicError(dynamic err) {
    if (err is AcademicError) {
      return err.message;
    }
    if (err is TimeoutException) {
      return '网络请求超时，请检查网络后重试';
    }
    if (err is SocketException) {
      return '无法连接教务网，请检查网络或连接校园网后重试';
    }
    final errStr = err.toString();
    if (errStr.contains('SocketException') ||
        errStr.contains('Connection refused') ||
        errStr.contains('Network is unreachable')) {
      return '无法连接教务网，请检查网络或连接校园网后重试';
    }
    if (errStr.contains('TimeoutException') || errStr.contains('timed out')) {
      return '网络请求超时，请检查网络后重试';
    }
    return '学业数据加载失败，请重试';
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
