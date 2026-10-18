/// 课表本地缓存：把最近一次成功抓到的课表落到 app 私有目录，
/// 让冷启动能"先给课表，再后台更新"，而不是每次打开都干等网络。
///
/// 为什么和 Cookie 快照（`session_repository.dart`）分开存：
///  - Cookie 是会话资产，可清可重建；课表是"已经拿到手的数据"，性质不同；
///  - 换学校时两者都要一起作废，但各自的失败面与重写频率不一样。
///
/// 缓存里额外记 `baseUrl` 与 `fetchedAt`：
///  - `baseUrl` 用于换校后丢弃旧学校的课表；
///  - `fetchedAt` 用于"最小更新间隔"——冷启动静默刷新前先判断隔了多久。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:zf_academic/zf_academic.dart';

/// 一份已缓存的课表 + 抓取时间 + 所属学校。
class CachedSchedule {
  const CachedSchedule({
    required this.baseUrl,
    required this.schedule,
    required this.fetchedAt,
  });

  final String baseUrl;
  final Schedule schedule;
  final DateTime fetchedAt;
}

/// 课表缓存的存取接口。抽象出来和 [SessionRepository] 同理：
/// 让 app 在拿到 path_provider 目录之前就能构造状态机，boot() 时换成落盘实现。
abstract class ScheduleCache {
  Future<CachedSchedule?> load();

  Future<void> save(CachedSchedule cached);

  Future<void> clear();
}

/// 文件实现：app 私有目录下单个 JSON。
class FileScheduleCache implements ScheduleCache {
  FileScheduleCache._(this._file);

  final File _file;

  static Future<FileScheduleCache> open({
    String fileName = 'zf-schedule-cache.json',
  }) async {
    final directory = await getApplicationSupportDirectory();
    return FileScheduleCache._(File('${directory.path}/$fileName'));
  }

  @override
  Future<CachedSchedule?> load() async {
    try {
      if (!await _file.exists()) return null;
      final text = await _file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      final baseUrl = decoded['baseUrl'];
      if (baseUrl is! String || baseUrl.isEmpty) return null;
      final schedule = _scheduleFromJson(decoded['schedule']);
      if (schedule == null) return null;
      final fetchedAt = DateTime.tryParse(
        decoded['fetchedAt'] as String? ?? '',
      );
      return CachedSchedule(
        baseUrl: baseUrl,
        schedule: schedule,
        fetchedAt: fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      // 缓存损坏不值得让 app 起不来：按"没有缓存"处理。
      return null;
    }
  }

  @override
  Future<void> save(CachedSchedule cached) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(<String, Object?>{
          'baseUrl': cached.baseUrl,
          'fetchedAt': cached.fetchedAt.toIso8601String(),
          'schedule': _scheduleToJson(cached.schedule),
        }),
      );
    } catch (_) {
      // 写缓存失败不影响主流程（下次打开无非再抓一次）。
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Schedule ↔ JSON（zf_academic 的模型没有自带 toJson，序列化收敛在这里）
  // -------------------------------------------------------------------------

  static Map<String, Object?> _scheduleToJson(Schedule schedule) =>
      <String, Object?>{
        'termId': schedule.termId,
        'maxWeeks': schedule.maxWeeks,
        'entries': <Object?>[
          for (final entry in schedule.entries)
            <String, Object?>{
              'id': entry.id,
              'name': entry.name,
              'teacher': entry.teacher,
              'location': entry.location,
              'day': entry.day,
              'startPeriod': entry.startPeriod,
              'endPeriod': entry.endPeriod,
              'weeks': entry.weeks,
              if (entry.details != null)
                'details': <Object?>[
                  for (final detail in entry.details!)
                    <String, Object?>{
                      'id': detail.id,
                      'label': detail.label,
                      'value': detail.value,
                    },
                ],
            },
        ],
        'remarks': <Object?>[
          for (final remark in schedule.remarks)
            <String, Object?>{
              'practical': remark.practical,
              'content': remark.content,
              'courseName': remark.courseName,
              'teacher': remark.teacher,
              'weeks': remark.weeks,
              'location': remark.location,
            },
        ],
      };

  static Schedule? _scheduleFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final termId = (raw['termId'] as String?) ?? '';
    if (termId.isEmpty) return null;
    final maxWeeks = (raw['maxWeeks'] as num?)?.toInt() ?? 0;
    final rawEntries = raw['entries'];
    if (rawEntries is! List<dynamic>) return null;

    final entries = <ScheduleEntry>[];
    for (final item in rawEntries) {
      if (item is! Map<String, dynamic>) continue;
      final id = (item['id'] as String?) ?? '';
      final name = (item['name'] as String?) ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final day = (item['day'] as num?)?.toInt();
      final startPeriod = (item['startPeriod'] as num?)?.toInt();
      final endPeriod = (item['endPeriod'] as num?)?.toInt();
      if (day == null || startPeriod == null || endPeriod == null) continue;

      final rawWeeks = item['weeks'];
      final weeks = rawWeeks is List<dynamic>
          ? rawWeeks
                .whereType<num>()
                .map((value) => value.toInt())
                .where((value) => value >= 1)
                .toList()
          : const <int>[];

      List<ScheduleDetail>? details;
      final rawDetails = item['details'];
      if (rawDetails is List<dynamic>) {
        final parsed = <ScheduleDetail>[
          for (final detail in rawDetails)
            if (detail is Map<String, dynamic>)
              ScheduleDetail(
                id: (detail['id'] as String?) ?? '',
                label: (detail['label'] as String?) ?? '',
                value: (detail['value'] as String?) ?? '',
              ),
        ];
        details = parsed.where((detail) => detail.id.isNotEmpty).toList();
        if (details.isEmpty) details = null;
      }

      entries.add(
        ScheduleEntry(
          id: id,
          name: name,
          teacher: _nullIfEmpty(item['teacher']),
          location: _nullIfEmpty(item['location']),
          day: day,
          startPeriod: startPeriod,
          endPeriod: endPeriod,
          weeks: weeks,
          details: details,
        ),
      );
    }

    final remarks = <ScheduleRemark>[];
    final rawRemarks = raw['remarks'];
    if (rawRemarks is List<dynamic>) {
      for (final item in rawRemarks) {
        if (item is! Map<String, dynamic>) continue;
        final content = (item['content'] as String?) ?? '';
        final courseName = _nullIfEmpty(item['courseName']);
        // 内容和课名都空 → 脏数据，跳过。
        if (content.isEmpty && courseName == null) continue;
        remarks.add(
          ScheduleRemark(
            practical: item['practical'] == true,
            content: content,
            courseName: courseName,
            teacher: _nullIfEmpty(item['teacher']),
            weeks: _nullIfEmpty(item['weeks']),
            location: _nullIfEmpty(item['location']),
          ),
        );
      }
    }

    return Schedule(
      termId: termId,
      entries: entries,
      remarks: remarks,
      maxWeeks: maxWeeks,
    );
  }

  static String? _nullIfEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 仅测试用：把课表序列化成缓存 JSON 的形状（验证往返时不必落盘）。
  static Map<String, Object?> encodeForTest(Schedule schedule) =>
      _scheduleToJson(schedule);

  /// 仅测试用：把缓存 JSON 反序列化成课表。
  static Schedule? decodeForTest(Object? raw) => _scheduleFromJson(raw);
}

/// 占位实现：目录还没就绪前的空转（load=无缓存，save/clear=丢弃）。
class LateScheduleCache implements ScheduleCache {
  @override
  Future<CachedSchedule?> load() async => null;

  @override
  Future<void> save(CachedSchedule cached) async {}

  @override
  Future<void> clear() async {}
}
