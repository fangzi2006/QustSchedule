/// 滚轮选择器：时间 / 时长 / 月日 / 节数，全部从底部弹出。
///
/// 用框架自带的 `CupertinoPicker`，不引第三方依赖。
/// 桌面端能拖拽的前提是 `MaterialApp.scrollBehavior` 放开了 mouse/trackpad
/// （见 `theme/app_theme.dart` 的 `AppScrollBehavior`）。
///
/// 两个刻意做过的细节：
///  1. **鼠标滚轮一次只走一格**。Windows 上一格滚轮的 delta 通常是 100+，
///     直接交给 `CupertinoPicker` 会跳好几项。这里在每个 item 上挂 `Listener`，
///     通过 `pointerSignalResolver` 抢在 Scrollable 之前接管事件（item 比
///     Scrollable 更深，而 resolver 只认第一个注册者），自己走一格。
///  2. **小时统一两位**（`01` 而不是 `1 时`），和分钟列对齐，扫一眼不会错位。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../src/term_calendar.dart';
import '../src/timetable.dart';

/// 弹出时间轮，返回从 00:00 起的分钟数；取消返回 null。
Future<int?> showTimeWheel(
  BuildContext context, {
  required int initialMinutes,
  String title = '选择时间',
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => _TimeWheelSheet(
      title: title,
      initialMinutes: snapToFiveMinutes(initialMinutes),
    ),
  );
}

/// 弹出「开始 + 结束」两列时间轮，一次设完一节课的起止。
///
/// 结束时间必须晚于开始时间，否则「确定」不可用——不做静默纠正，
/// 因为用户可能正在准备输入一个更晚的时间。
Future<({int start, int end})?> showTimeRangeWheel(
  BuildContext context, {
  required int startMinutes,
  required int endMinutes,
  String title = '上课时间',
}) {
  return showModalBottomSheet<({int start, int end})>(
    context: context,
    showDragHandle: true,
    builder: (context) => _TimeRangeSheet(
      title: title,
      startMinutes: snapToFiveMinutes(startMinutes),
      endMinutes: snapToFiveMinutes(endMinutes),
    ),
  );
}

/// 弹出时长轮（5 的倍数），用于"每节课时长""课间时长"。取消返回 null。
Future<int?> showDurationWheel(
  BuildContext context, {
  required int initialMinutes,
  String title = '选择时长',
  int minMinutes = 5,
  int maxMinutes = 180,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => _DurationWheelSheet(
      title: title,
      initialMinutes: initialMinutes,
      minMinutes: minMinutes,
      maxMinutes: maxMinutes,
    ),
  );
}

/// 弹出「月 + 日」两列轮（生效日期只让选月日，年份自动推算）。
///
/// 返回月日；取消返回 null。
Future<({int month, int day})?> showMonthDayWheel(
  BuildContext context, {
  required int month,
  required int day,
  String title = '选择日期',
}) {
  return showModalBottomSheet<({int month, int day})>(
    context: context,
    showDragHandle: true,
    builder: (context) => _MonthDaySheet(title: title, month: month, day: day),
  );
}

/// 弹出「第几节后 + 时长」两列轮：大课间的一次设置。
Future<({int after, int minutes})?> showBigBreakWheel(
  BuildContext context, {
  required int maxAfter,
  required int after,
  required int minutes,
  String title = '大课间',
}) {
  return showModalBottomSheet<({int after, int minutes})>(
    context: context,
    showDragHandle: true,
    builder: (context) => _BigBreakSheet(
      title: title,
      maxAfter: maxAfter,
      after: after,
      minutes: minutes,
    ),
  );
}

/// 弹出「上午 / 下午 / 晚上」三列节数轮。
///
/// 节数是全局设置，所以在这里一次调完；返回新的三段节数，取消返回 null。
/// 三列互不联动，只在确定时校验总数（≥1 且 ≤ [maxSections]）——联动限制会让
/// "上午减一节、下午加一节"这种调法变得很别扭。
Future<Map<PeriodGroup, int>?> showSectionCountWheel(
  BuildContext context, {
  required Map<PeriodGroup, int> counts,
}) {
  return showModalBottomSheet<Map<PeriodGroup, int>>(
    context: context,
    showDragHandle: true,
    builder: (context) => _SectionCountSheet(counts: counts),
  );
}

/// 弹出周次校准轮：选择「本周实际是第几周」。
///
/// 返回选中的周次（>= 1）；
/// 若点击「恢复默认估算」返回 0；取消返回 null。
Future<int?> showWeekCalibrationWheel(
  BuildContext context, {
  required int currentWeek,
  int maxWeek = 30,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => _CalibrateSheet(week: currentWeek, max: maxWeek),
  );
}

/// 一列滚轮。
///
/// 自己持有 `FixedExtentScrollController` 与当前索引：鼠标滚轮要"一次一格"，
/// 就必须知道当前停在哪一项，而 `controller.selectedItem` 在动画期间还是旧值。
class _Wheel extends StatefulWidget {
  const _Wheel({
    super.key,
    required this.labels,
    required this.initialIndex,
    required this.onChanged,
    this.textStyle,
  });

  final List<String> labels;
  final int initialIndex;
  final ValueChanged<int> onChanged;
  final TextStyle? textStyle;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late int _index = widget.initialIndex.clamp(0, widget.labels.length - 1);
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: _index);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    widget.onChanged(index);
  }

  /// 接管鼠标滚轮：一次一格。
  ///
  /// `Listener` 挂在每个 item 上（比 `Scrollable` 更深），所以能先于它注册到
  /// `pointerSignalResolver`；resolver 只认第一个注册者，等于把原生滚动"吃掉"。
  ///
  /// **`behavior` 必须是 `opaque`**：默认的 `deferToChild` 只有文字本身算命中，
  /// 把鼠标放在数字以外的位置（选中高亮块、行间空白）事件会落到 `Scrollable` 上，
  /// 于是同一个轮子里"指哪儿"决定了滚一格还是滚好几格——这正是不一致的原因。
  /// 改成 opaque 后整个轮子（可见区域）行为统一。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerEvent _,
    ) {
      final next = (_index + (delta > 0 ? 1 : -1));
      if (next < 0 || next >= widget.labels.length) return;
      _controller.animateToItem(
        next,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      _select(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPicker(
      scrollController: _controller,
      itemExtent: 40,
      diameterRatio: 1.5,
      useMagnifier: true,
      magnification: 1.1,
      onSelectedItemChanged: _select,
      children: <Widget>[
        for (final label in widget.labels)
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: _onPointerSignal,
            child: Center(child: Text(label, style: widget.textStyle)),
          ),
      ],
    );
  }
}

class _WheelShell extends StatelessWidget {
  const _WheelShell({
    required this.title,
    required this.wheels,
    required this.suffix,
    required this.onConfirm,
    this.confirmEnabled = true,
    this.wheelHeight = 168,
    this.extraAction,
  });

  final String title;
  final Widget wheels;

  /// 副标题：把当前选择拼成一句人话。
  final String suffix;
  final VoidCallback onConfirm;
  final bool confirmEnabled;
  final double wheelHeight;
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: confirmEnabled ? onConfirm : null,
                  child: const Text('确定'),
                ),
              ],
            ),
            SizedBox(height: wheelHeight, child: wheels),
            const SizedBox(height: 4),
            Text(
              suffix,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            if (extraAction != null) ...<Widget>[
              const SizedBox(height: 6),
              extraAction!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 小时列（00..23）。
List<String> _hourLabels() => <String>[
  for (var hour = 0; hour < 24; hour++) hour.toString().padLeft(2, '0'),
];

/// 分钟列（00, 05, ... 55）。
List<String> _minuteLabels() => <String>[
  for (var minute = 0; minute < 60; minute += 5)
    minute.toString().padLeft(2, '0'),
];

class _TimeWheelSheet extends StatefulWidget {
  const _TimeWheelSheet({required this.title, required this.initialMinutes});

  final String title;
  final int initialMinutes;

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  late int _hour = widget.initialMinutes ~/ 60;
  late int _minute = widget.initialMinutes % 60;

  static final List<String> _hours = _hourLabels();
  static final List<String> _minutes = _minuteLabels();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    return _WheelShell(
      title: widget.title,
      suffix: formatClock(_hour * 60 + _minute),
      onConfirm: () => Navigator.of(context).pop(_hour * 60 + _minute),
      wheels: Row(
        children: <Widget>[
          Expanded(
            child: _Wheel(
              labels: _hours,
              initialIndex: _hour,
              textStyle: style,
              onChanged: (index) => setState(() => _hour = index),
            ),
          ),
          Text(':', style: style),
          Expanded(
            child: _Wheel(
              labels: _minutes,
              initialIndex:
                  _minutes.contains(_minute.toString().padLeft(2, '0'))
                  ? _minutes.indexOf(_minute.toString().padLeft(2, '0'))
                  : 0,
              textStyle: style,
              onChanged: (index) =>
                  setState(() => _minute = int.parse(_minutes[index])),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「开始 + 结束」四列轮。
class _TimeRangeSheet extends StatefulWidget {
  const _TimeRangeSheet({
    required this.title,
    required this.startMinutes,
    required this.endMinutes,
  });

  final String title;
  final int startMinutes;
  final int endMinutes;

  @override
  State<_TimeRangeSheet> createState() => _TimeRangeSheetState();
}

class _TimeRangeSheetState extends State<_TimeRangeSheet> {
  late int _start = widget.startMinutes;
  late int _end = widget.endMinutes;

  static final List<String> _hours = _hourLabels();
  static final List<String> _minutes = _minuteLabels();

  int _indexOfMinute(int value) {
    final label = value.toString().padLeft(2, '0');
    final index = _minutes.indexOf(label);
    return index < 0 ? 0 : index;
  }

  // 开始时间变化时**不**自动改结束时间：滚轮各自的索引是独立状态，
  // 偷偷改值会让"显示的轮"和"实际的值"脱节。非法组合由「确定」按钮拦住。
  void _setStart(int minutes) => setState(() => _start = minutes);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    final valid = _end > _start;
    return _WheelShell(
      title: widget.title,
      wheelHeight: 196,
      confirmEnabled: valid,
      suffix: valid
          ? '${formatClock(_start)} – ${formatClock(_end)}（${_end - _start} 分钟）'
          : '结束时间要晚于开始时间',
      onConfirm: () => Navigator.of(context).pop((start: _start, end: _end)),
      wheels: Row(
        children: <Widget>[
          Expanded(
            child: _timeGroup(
              context,
              caption: '开始',
              hour: _start ~/ 60,
              minute: _start % 60,
              onHour: (index) => _setStart(index * 60 + _start % 60),
              onMinute: (index) =>
                  _setStart(_start ~/ 60 * 60 + int.parse(_minutes[index])),
              style: style,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('→', style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: _timeGroup(
              context,
              caption: '结束',
              hour: _end ~/ 60,
              minute: _end % 60,
              onHour: (index) => setState(() => _end = index * 60 + _end % 60),
              onMinute: (index) => setState(
                () => _end = _end ~/ 60 * 60 + int.parse(_minutes[index]),
              ),
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeGroup(
    BuildContext context, {
    required String caption,
    required int hour,
    required int minute,
    required ValueChanged<int> onHour,
    required ValueChanged<int> onMinute,
    required TextStyle? style,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Text(
          caption,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Wheel(
                  labels: _hours,
                  initialIndex: hour.clamp(0, 23),
                  textStyle: style,
                  onChanged: onHour,
                ),
              ),
              Text(':', style: style),
              Expanded(
                child: _Wheel(
                  labels: _minutes,
                  initialIndex: _indexOfMinute(minute),
                  textStyle: style,
                  onChanged: onMinute,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DurationWheelSheet extends StatefulWidget {
  const _DurationWheelSheet({
    required this.title,
    required this.initialMinutes,
    required this.minMinutes,
    required this.maxMinutes,
  });

  final String title;
  final int initialMinutes;
  final int minMinutes;
  final int maxMinutes;

  @override
  State<_DurationWheelSheet> createState() => _DurationWheelSheetState();
}

class _DurationWheelSheetState extends State<_DurationWheelSheet> {
  late final List<int> _values = <int>[
    for (var value = widget.minMinutes; value <= widget.maxMinutes; value += 5)
      value,
  ];

  late int _value = _snap(widget.initialMinutes);

  int _snap(int minutes) {
    final index = _values.indexWhere((value) => value >= minutes);
    return _values[index < 0 ? _values.length - 1 : index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _WheelShell(
      title: widget.title,
      suffix: '$_value 分钟',
      onConfirm: () => Navigator.of(context).pop(_value),
      wheels: _Wheel(
        labels: <String>[for (final value in _values) '$value 分钟'],
        initialIndex: _values.indexOf(_value),
        textStyle: theme.textTheme.titleMedium,
        onChanged: (index) => setState(() => _value = _values[index]),
      ),
    );
  }
}

class _MonthDaySheet extends StatefulWidget {
  const _MonthDaySheet({
    required this.title,
    required this.month,
    required this.day,
  });

  final String title;
  final int month;
  final int day;

  @override
  State<_MonthDaySheet> createState() => _MonthDaySheetState();
}

class _MonthDaySheetState extends State<_MonthDaySheet> {
  late int _month = widget.month.clamp(1, 12);
  late int _day = widget.day;

  int get _days => daysInMonth(DateTime.now().year, _month);

  @override
  void initState() {
    super.initState();
    if (_day > _days) _day = _days;
    if (_day < 1) _day = 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    return _WheelShell(
      title: widget.title,
      // 作息按月日每年循环，生效与否只看月日，不带年份。
      suffix: '${formatMonthDay(_month, _day)} 起 · 每年循环',
      onConfirm: () => Navigator.of(context).pop((month: _month, day: _day)),
      wheels: Row(
        children: <Widget>[
          Expanded(
            child: _Wheel(
              labels: <String>[
                for (var month = 1; month <= 12; month++) '$month 月',
              ],
              initialIndex: _month - 1,
              textStyle: style,
              onChanged: (index) => setState(() {
                _month = index + 1;
                final maxDay = daysInMonth(DateTime.now().year, _month);
                if (_day > maxDay) _day = maxDay;
              }),
            ),
          ),
          Expanded(
            // 换月后日数可能变少，用 key 强制重建日列。
            child: _Wheel(
              key: ValueKey<int>(_month),
              labels: <String>[for (var day = 1; day <= _days; day++) '$day 日'],
              initialIndex: _day - 1,
              textStyle: style,
              onChanged: (index) => setState(() => _day = index + 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigBreakSheet extends StatefulWidget {
  const _BigBreakSheet({
    required this.title,
    required this.maxAfter,
    required this.after,
    required this.minutes,
  });

  final String title;
  final int maxAfter;
  final int after;
  final int minutes;

  @override
  State<_BigBreakSheet> createState() => _BigBreakSheetState();
}

class _BigBreakSheetState extends State<_BigBreakSheet> {
  late int _after = widget.after.clamp(
    1,
    widget.maxAfter < 1 ? 1 : widget.maxAfter,
  );
  late int _minutes = widget.minutes;

  static List<int> get _durations => <int>[
    for (var value = 5; value <= maxBigBreakMinutes; value += 5) value,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    final durations = _durations;
    final minuteIndex = durations.contains(_minutes)
        ? durations.indexOf(_minutes)
        : 3;
    final maxAfter = widget.maxAfter < 1 ? 1 : widget.maxAfter;
    return _WheelShell(
      title: widget.title,
      suffix: '第 $_after 节后 · 休息 $_minutes 分钟',
      onConfirm: () =>
          Navigator.of(context).pop((after: _after, minutes: _minutes)),
      wheels: Row(
        children: <Widget>[
          Expanded(
            child: _Wheel(
              labels: <String>[
                for (var after = 1; after <= maxAfter; after++) '第 $after 节后',
              ],
              initialIndex: _after - 1,
              textStyle: style,
              onChanged: (index) => setState(() => _after = index + 1),
            ),
          ),
          Expanded(
            child: _Wheel(
              labels: <String>[for (final value in durations) '$value 分钟'],
              initialIndex: minuteIndex,
              textStyle: style,
              onChanged: (index) => setState(() => _minutes = durations[index]),
            ),
          ),
        ],
      ),
    );
  }
}

/// 上午 / 下午 / 晚上 三段节数。
class _SectionCountSheet extends StatefulWidget {
  const _SectionCountSheet({required this.counts});

  final Map<PeriodGroup, int> counts;

  @override
  State<_SectionCountSheet> createState() => _SectionCountSheetState();
}

class _SectionCountSheetState extends State<_SectionCountSheet> {
  late final Map<PeriodGroup, int> _counts = <PeriodGroup, int>{
    for (final group in PeriodGroup.values)
      group: (widget.counts[group] ?? 0).clamp(0, maxSections),
  };

  int get _total => countsSum(_counts);
  bool get _valid => _total >= 1 && _total <= maxSections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    return _WheelShell(
      title: '课表节数',
      confirmEnabled: _valid,
      suffix: _valid
          ? '共 $_total 节（上午 ${_counts[PeriodGroup.morning]} · '
                '下午 ${_counts[PeriodGroup.afternoon]} · '
                '晚上 ${_counts[PeriodGroup.evening]}）'
          : '总节数需在 1–$maxSections 之间',
      onConfirm: () =>
          Navigator.of(context).pop(Map<PeriodGroup, int>.from(_counts)),
      wheels: Row(
        children: <Widget>[
          for (final group in PeriodGroup.values)
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(
                    group.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: _Wheel(
                      labels: <String>[
                        for (var n = 0; n <= maxSections; n++) '$n 节',
                      ],
                      initialIndex: _counts[group] ?? 0,
                      textStyle: style,
                      onChanged: (index) =>
                          setState(() => _counts[group] = index),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CalibrateSheet extends StatefulWidget {
  const _CalibrateSheet({required this.week, required this.max});

  final int week;
  final int max;

  @override
  State<_CalibrateSheet> createState() => _CalibrateSheetState();
}

class _CalibrateSheetState extends State<_CalibrateSheet> {
  late int _week = widget.week.clamp(1, widget.max);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = termStartFromWeek(DateTime.now(), _week);
    final suffix = '推算第 1 周周一为 ${start.month}月${start.day}日 · 自动对齐日程';
    return _WheelShell(
      title: '校准当前周次',
      suffix: suffix,
      onConfirm: () => Navigator.of(context).pop(_week),
      extraAction: TextButton(
        onPressed: () => Navigator.of(context).pop(0),
        child: const Text('恢复默认估算'),
      ),
      wheels: _Wheel(
        labels: <String>[for (var w = 1; w <= widget.max; w++) '第 $w 周'],
        initialIndex: _week - 1,
        textStyle: theme.textTheme.titleMedium,
        onChanged: (index) => setState(() => _week = index + 1),
      ),
    );
  }
}
