/// 学业服务业务编排层。
///
/// 负责考试查询、成绩查询、未评教状态流转、统计指标计算及离线缓存持久化。
library;

import 'dart:ui';

import 'package:zf_academic/zf_academic.dart';

import 'academic_cache.dart';
import 'schedule_service.dart';

/// 成绩与学分统计指标。
class GradeStats {
  final double averageGpa;
  final double totalCredits;
  final double passedCredits;
  final int totalCourses;
  final int passedCourses;

  const GradeStats({
    required this.averageGpa,
    required this.totalCredits,
    required this.passedCredits,
    required this.totalCourses,
    required this.passedCourses,
  });

  /// 依据教务原生数据计算加权平均绩点与通过门数。
  ///
  /// 严格遵循教务官方 `jd`（绩点），严禁客户端擅自臆测换算规则。
  static GradeStats calculate(List<GradeItem> grades) {
    if (grades.isEmpty) {
      return const GradeStats(
        averageGpa: 0.0,
        totalCredits: 0.0,
        passedCredits: 0.0,
        totalCourses: 0,
        passedCourses: 0,
      );
    }

    double totalWeightedGpa = 0.0;
    double gpaCredits = 0.0;
    double totalCredits = 0.0;
    double passedCredits = 0.0;
    int passedCount = 0;

    for (final grade in grades) {
      final cr = grade.credit;
      if (grade.gradePoint != null && cr > 0) {
        totalWeightedGpa += grade.gradePoint! * cr;
        gpaCredits += cr;
      }
      totalCredits += cr;

      final numScore = grade.numericScore ?? double.tryParse(grade.rawScore);
      final raw = grade.rawScore.trim();
      final isPassed =
          (numScore != null && numScore >= 60.0) ||
          const [
            '通过',
            '合格',
            '优秀',
            '良好',
            '中等',
            '及格',
            '免修',
            '免考',
            'P',
            'p',
          ].contains(raw) ||
          (grade.gradePoint != null && grade.gradePoint! > 0);
      if (isPassed) {
        passedCount++;
        passedCredits += cr;
      }
    }

    final avgGpa = gpaCredits > 0 ? (totalWeightedGpa / gpaCredits) : 0.0;
    return GradeStats(
      averageGpa: avgGpa,
      totalCredits: totalCredits,
      passedCredits: passedCredits,
      totalCourses: grades.length,
      passedCourses: passedCount,
    );
  }
}

class AcademicService {
  final ScheduleService service;
  final ExamCache examCache;
  final GradesCache gradesCache;

  AcademicService({
    required this.service,
    required this.examCache,
    required this.gradesCache,
  });

  /// 抓取并缓存指定学期的考试安排。
  Future<List<ExamItem>> fetchExams(String termId) async {
    final exams = await service.fetchExams(termId);
    await examCache.save(termId, exams);
    return exams;
  }

  /// 抓取并缓存指定学期的成绩清单。
  Future<List<GradeItem>> fetchGrades(String termId) async {
    try {
      final grades = await service.fetchGrades(termId);
      await gradesCache.save(termId, grades, isNotEvaluated: false);
      return grades;
    } on AcademicError catch (e) {
      if (e.code == ErrorCode.notEvaluated) {
        final existing = await gradesCache.load(termId);
        await gradesCache.save(
          termId,
          existing?.items ?? const <GradeItem>[],
          isNotEvaluated: true,
        );
      }
      rethrow;
    }
  }

  /// 随课表触发的非阻塞异步后台同步流水线。
  ///
  /// 独立捕获异常，绝不向上抛出阻碍课表主流程。
  Future<void> syncCurrentTermAsync({
    required String termId,
    VoidCallback? onDataUpdated,
  }) async {
    if (termId.isEmpty) return;
    await Future.wait(<Future<dynamic>>[
      fetchExams(termId).catchError((_) => const <ExamItem>[]),
      fetchGrades(termId).catchError((_) => const <GradeItem>[]),
    ]);
    onDataUpdated?.call();
  }
}
