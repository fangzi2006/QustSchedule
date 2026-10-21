/// 课表页：周视图。
///
/// 结构：
///   AppBar（周次条 + 刷新 + 菜单）
///   ├─ 周次条：← 第 N 周 / 共 M 周 → + 该周日期范围（回本周由右下角"今"按钮负责）
///   ├─ PageView：每页一周，左右滑切换
///   │    ├─ 表头（周几 + 日期，今天高亮；有课程冲突的那天黄底）
///   │    ├─ 网格：左侧时间轴（等高格子）+ 7 天 × N 节，课程块绝对定位
///   │    └─ 备注区：实践课程 / 其他课程，跟着网格一起滚
///   └─ 右下角"今"：看非本周时浮出，点一下回本周
///
/// 加载/刷新/报错都不在页面里画：进度与错误统一由外壳的状态弹窗负责。
///
/// 时间轴的"格"是等高的：一节课一行，左侧标开始时间与节次号。
/// 之所以不做"按真实分钟数拉伸"，是因为跨节课会被课间切断成碎块，
/// 且换作息表时全表高度跳变。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart';

import '../src/app_model.dart';
import '../src/reschedule.dart';
import '../src/term_calendar.dart';
import '../widgets/app_menu.dart';
import '../widgets/course_detail_sheet.dart';
import '../widgets/course_tile.dart';
import '../widgets/floating_dock.dart';
import '../widgets/week_pager.dart';
import 'appearance_sheet.dart';
import 'reschedule_page.dart';
import 'school_address_page.dart';
import 'timetable_list_page.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.model});

  final AppModel model;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  AppModel get model => widget.model;

  /// 顶栏"第 N 周"此刻该显示哪一周 —— **只负责显示**。
  ///
  /// 为什么不直接读 `model.week`：`week` 是"落定"的结果，而滑动时画面翻过
  /// 半页就已经换了一周。翻到一半就 `goToWeek()`，整个课表页（已建页面的网格
  /// 布局、AppBar、右下角按钮）都要在同一帧里重建一遍 —— 实测这正是快速连滑
  /// 时最大的一次掉帧（同一帧正常 3~5ms，带上整页重建是 100ms 量级）。
  ///
  /// 所以拆成两件事：
  ///  - 显示：跟着手势走的轻量值，只在**跨过一页**那一刻变一次，
  ///    只重建顶栏与右下角按钮这两个小部件；
  ///  - 状态：`model.week` 留到停稳后再写（见 `_WeekPagerState._settleToPage`）。
  final ValueNotifier<int> _shownWeek = ValueNotifier<int>(1);

  @override
  void initState() {
    super.initState();
    _shownWeek.value = model.week;
    // 只听周次通知：换周不该让整张课表重建（内容没变）。
    model.weekNotifier.addListener(_syncShownWeek);
  }

  @override
  void dispose() {
    model.weekNotifier.removeListener(_syncShownWeek);
    _shownWeek.dispose();
    super.dispose();
  }

  /// 外部改了周次（刷新 / 校准 / 回到前台 / 点箭头 / 选周）→ 顶栏跟上。
  /// 手势期间的跨页由 pager 直接写 `_shownWeek`，不走这里。
  void _syncShownWeek() {
    if (_shownWeek.value != model.week) _shownWeek.value = model.week;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, _) => Scaffold(
        // 这一行不写"某某的课表"：AppBar 左边留给周次选择，右边是刷新与更多。
        // 之前是"标题一行 + 周次条一行"，两行占了近百像素，格子反而更挤。
        appBar: AppBar(
          titleSpacing: 4,
          title: model.schedule == null
              ? null
              : _WeekBar(model: model, week: _shownWeek),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新课表',
              onPressed: model.status == AppStatus.ready && !model.refreshing
                  ? model.refresh
                  : null,
            ),
            _MoreMenu(model: model),
          ],
        ),
        // 备注不固定在这里：它跟着周网格一起滚（放在 _WeekView 的滚动内容底部）。
        body: Stack(
          children: <Widget>[
            Positioned.fill(child: _body(context)),
            // "今"：只在看非本周时浮出来（替代原来占位置的"回到本周"按钮）。
            _TodayFab(model: model, week: _shownWeek),
          ],
        ),
      ),
    );
  }

  /// 加载中不再整屏转圈：网格照常铺开，进度与错误由外壳的状态弹窗负责。
  Widget _body(BuildContext context) {
    switch (model.status) {
      case AppStatus.needLogin:
      case AppStatus.needCaptcha:
        return const SizedBox.shrink();
      case AppStatus.booting:
      case AppStatus.loading:
      case AppStatus.signingIn:
      case AppStatus.failed:
      case AppStatus.ready:
        return _WeekPager(
          // 换学期 / 节数变化时整体重建：PageController 的 initialPage
          // 只在创建时有效，重建比手动纠正页码可靠。
          key: ValueKey<String>('${model.termId}:${model.maxWeek}'),
          model: model,
          shownWeek: _shownWeek,
        );
    }
  }
}

/// 右下角"今"按钮：看非本周时出现，点一下回到今天所在周。
///
/// 跟着 [week]（当前显示的那一周）走而不是 `model.week`：滑动跨过一页它就该
/// 跟着浮出/收起，不必等停稳后整页重建。
class _TodayFab extends StatelessWidget {
  const _TodayFab({required this.model, required this.week});

  final AppModel model;
  final ValueListenable<int> week;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: week,
      builder: (BuildContext context, int shown, _) => _build(context, shown),
    );
  }

  Widget _build(BuildContext context, int shown) {
    final show =
        model.status == AppStatus.ready && shown != model.currentWeekOfToday;
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      right: 16,
      bottom: FloatingDock.contentInset(context),
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedScale(
          scale: show ? 1 : 0.55,
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            key: const ValueKey<String>('today-fab'),
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Tooltip(
              message: '回到本周',
              child: Material(
                color: scheme.primary,
                shape: const CircleBorder(),
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.28),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: model.goToThisWeek,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Center(
                      child: Text(
                        '今',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 右上角三点菜单：校准周次 / 作息时间表 / 教务地址 / 外观。
///
/// 「调试信息」和「退出登录」不在这里——那两个是低频且危险的操作，
/// 统一收在设置页；这里放的是"看课表时顺手想改一下"的东西。
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    // Builder 只是为了拿到按钮自己的 context：菜单要靠它定位。
    return Builder(
      builder: (buttonContext) => IconButton(
        icon: const Icon(Icons.more_horiz_rounded),
        tooltip: '更多',
        onPressed: () => showAppMenu<String>(
          context: buttonContext,
          items: const <AppMenuItem<String>>[
            AppMenuItem<String>(
              value: 'calibrate',
              label: '校准当前周次',
              icon: Icons.event_repeat_rounded,
            ),
            AppMenuItem<String>(
              value: 'timetables',
              label: '作息时间表',
              icon: Icons.schedule_rounded,
            ),
            AppMenuItem<String>(
              value: 'school',
              label: '教务地址',
              icon: Icons.link_rounded,
            ),
            AppMenuItem<String>.divider(),
            AppMenuItem<String>(
              value: 'appearance',
              label: '外观',
              icon: Icons.palette_outlined,
            ),
            AppMenuItem<String>(
              value: 'reschedule',
              label: '调课',
              icon: Icons.swap_horiz_rounded,
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'calibrate':
                showCalibrateSheet(context, model);
              case 'timetables':
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TimetableListPage(model: model),
                  ),
                );
              case 'school':
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SchoolAddressPage(model: model),
                  ),
                );
              case 'appearance':
                showAppearanceSheet(context, model);
              case 'reschedule':
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReschedulePage(model: model),
                  ),
                );
            }
          },
        ),
      ),
    );
  }
}

/// 周次选择：「← 第 N 周 / 共 M 周 →」，中间那块点了从**下方**弹周次菜单。
///
/// 现在是 AppBar 的 title，和右边的刷新/更多挤在同一行：
/// 箭头贴着文字而不是撑到两边，手机上左右扫视距离短，两个换周操作落在同一视觉区域里。
class _WeekBar extends StatelessWidget {
  const _WeekBar({required this.model, required this.week});

  final AppModel model;

  /// 正在显示的那一周：跟着手势走，滑动跨页时只重建这一条。
  final ValueListenable<int> week;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: week,
      builder: (BuildContext context, int shown, _) =>
          _buildBar(context, shown),
    );
  }

  Widget _buildBar(BuildContext context, int shownWeek) {
    final theme = Theme.of(context);
    // 日期范围按"显示的那一周"算，而不是 model.week：滑动跨页时它要跟着变。
    final start = model.termStart;
    final range = start == null ? '' : weekRangeLabel(start, shownWeek);
    // 三个东西整体当成一块：[←][第 N 周][→]，靠左排。
    // 外面套 FittedBox：小屏 + 大字号（或等宽字体）下这块可能比标题栏还宽，
    // 整体缩一点总比溢出成黄黑条纹好；放得下时它就是 1:1，完全不动。
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SmallIconButton(
              icon: Icons.chevron_left_rounded,
              tooltip: '上一周',
              onPressed: shownWeek > 1
                  ? () => model.goToWeek(shownWeek - 1)
                  : null,
            ),
            Builder(
              builder: (buttonContext) => InkWell(
                onTap: () =>
                    showWeekPicker(buttonContext, model, current: shownWeek),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '第 $shownWeek 周',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            ' / 共 ${model.maxWeek} 周',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 18,
                            color: theme.hintColor,
                          ),
                        ],
                      ),
                      if (range.isNotEmpty)
                        Text(
                          model.weekRange,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _SmallIconButton(
              icon: Icons.chevron_right_rounded,
              tooltip: '下一周',
              onPressed: shownWeek < model.maxWeek
                  ? () => model.goToWeek(shownWeek + 1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 统一边长的小按钮：36×36，图标 20。
///
/// 固定尺寸而不用 `visualDensity.compact`：后者的实际边长取决于图标与内边距，
/// 同一行里会看着忽大忽小。
class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  static const double size = 36;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 每周一页。PageController 的生命周期交给这个 State：
/// 外层用 key 触发重建，重建时旧 State 先 dispose，controller 不会带着
/// 错误的 initialPage 继续用。
///
/// 翻页规则（实现在 [WeekPagerController]）：
///  - **一次滑动 = 一页**：松手时以"起手页"为锚，快速滑动固定翻到相邻一页。
///    框架默认按"当前位置 + 半页"取整，手把页面拖过一页就会跳过一页。
///  - **慢慢松开就近吸附**：拖过半页才翻，没到半页回原页。
///  - **按住不打断**：按下 / 抬起不改位置，只有真的拖起来才接管。
///  - **手势期间不写 model**：跨过一页只更新 [shownWeek]（只重建顶栏），
///    周次停稳后才写回 `model.week` —— 否则每翻一页都要整页重建一次。
class _WeekPager extends StatefulWidget {
  const _WeekPager({super.key, required this.model, required this.shownWeek});

  final AppModel model;

  /// 顶栏正在显示的那一周：跟着翻页走，不等到停稳。
  final ValueNotifier<int> shownWeek;

  @override
  State<_WeekPager> createState() => _WeekPagerState();
}

/// 翻页动画时长。比原来（220ms）更利落；落页弹簧在 [WeekPagerController]
/// 里另有一处调快（见 `_kSnapSpring`），两边节奏要对得上。
const Duration _flipDuration = Duration(milliseconds: 150);

class _WeekPagerState extends State<_WeekPager> {
  late final WeekPagerController _controller = WeekPagerController(
    initialPage: (widget.model.week - 1).clamp(0, widget.model.maxWeek - 1),
  );

  /// 正在程序化滚向的页；null = 没有程序动画在跑。
  ///
  /// 用途有二：
  ///  ① 连点箭头时，新目标会打断旧动画，但**同一目标**不再重复启动
  ///     （重复 `animateToPage` 会让动画从头再演一次，看着一卡一卡）；
  ///  ② 动画途中 `onPageChanged` 报的中间页不是用户意图，不能写进顶栏。
  int? _animatingTo;

  /// 正在把页码回写成周次：此时 model 的通知来自我们自己，不是"外部要换周"。
  bool _syncingFromPage = false;

  /// 手指正按着拖（含松手后的惯性直到完全停下）。
  bool _dragging = false;

  AppModel get model => widget.model;

  @override
  void initState() {
    super.initState();
    // 外部改了周次（点箭头 / 选周 / 回到本周）→ 动画翻过去。
    // 订阅的是**周次通知源**而不是整个 model：内容变化与翻页无关，
    // 而周次变化也不该拖着整张课表重建。
    model.weekNotifier.addListener(_onWeekChanged);
  }

  @override
  void dispose() {
    model.weekNotifier.removeListener(_onWeekChanged);
    _controller.dispose();
    super.dispose();
  }

  /// 外部改了周次（点箭头 / 选周 / 回到本周 / 校准）→ 动画滚到对应页。
  ///
  /// 刻意不用"动画进行中"的布尔锁（连点两下会被吞掉），靠 [_animatingTo]
  /// 判断"是不是已经在去同一页的路上"：可打断、可续接，但不会重复启动。
  void _onWeekChanged() {
    // 这条通知是我们自己从页码回写的：没有新的翻页意图，别再反向驱动动画。
    if (_syncingFromPage) return;
    if (!mounted || !_controller.hasClients) return;

    final target = (model.week - 1).clamp(0, model.maxWeek - 1);
    if (_animatingTo == target) return;

    final page = _controller.page;
    // 已经停在那页上（位置比 round() 可信），不为半个像素再动一次。
    if (_animatingTo == null && page != null && (page - target).abs() < 0.02) {
      return;
    }

    _animatingTo = target;
    _controller
        .animateToPage(target, duration: _flipDuration, curve: Curves.easeOut)
        .whenComplete(() {
          if (!mounted || _animatingTo != target) return;
          _animatingTo = null;
          // 动画被打断（拖拽接管）时，落点由手决定：以实际停下的页为准。
          _settleToPage();
        });
  }

  /// 只处理翻页这一层的通知；`depth != 0` 是每页里那个竖向滚动（网格），
  /// 跟翻页无关，交给它自己。
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        _dragging = true;
        // 真拖拽接管：程序动画的目标作废，否则拖到一半会被"拉回"原目标。
        _animatingTo = null;
      }
    } else if (notification is ScrollEndNotification) {
      // 拖拽 + 惯性彻底停下（按住不会走到这里，因为 hold 已被忽略）。
      _dragging = false;
      _settleToPage();
    }
    return false;
  }

  /// 页面翻过一半时触发（`PageView.onPageChanged` 的口径是 round(page)）。
  ///
  /// 这里**只更新顶栏**，不碰 model：跨页是滑动过程中最密集的时刻，
  /// 此时整页重建最容易掉帧。真正写回 `model.week` 的时机在 [_settleToPage]。
  void _onPageChanged(int index) {
    // 程序动画途中的中间页不代表用户意图：目标周早已写进顶栏了。
    if (_animatingTo != null) return;
    final week = index + 1;
    if (widget.shownWeek.value != week) widget.shownWeek.value = week;
  }

  /// 一切停下之后，以**实际页码**为准回写周次。
  ///
  /// 覆盖两种"手动手势压过程序意图"的结果：拖拽打断翻页动画、
  /// 惯性落在相邻页。不回写的话周次会停在旧值，画面却在另一页。
  void _settleToPage() {
    if (!mounted || _dragging || _animatingTo != null) return;
    final page = _controller.page;
    if (page == null) return;
    final week = page.round() + 1;
    if (week != model.week) _writeWeek(week);
  }

  /// 把页码写成周次；期间 model 的通知要认成"自己发的"，
  /// 否则 [_onModelChanged] 会为了跟上这次回写再启动一次动画，正好和手打架。
  void _writeWeek(int week) {
    _syncingFromPage = true;
    try {
      model.goToWeek(week);
    } finally {
      _syncingFromPage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: PageView.builder(
        controller: _controller,
        // 起拖位移从"手指按下那一点"算起。框架默认（start）会丢掉起拖阈值
        // 那 ~18dp：慢慢拖时手已经走了一截页面才动，而且这段永远补不回来。
        dragStartBehavior: DragStartBehavior.down,
        itemCount: model.maxWeek,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) =>
            _WeekView(model: model, week: index + 1),
      ),
    );
  }
}

/// 一周的内容：表头 + 网格。
class _WeekView extends StatelessWidget {
  const _WeekView({required this.model, required this.week});

  final AppModel model;
  final int week;

  /// 时间列宽度：只放 `08:00` 这种 5 个字符，34 刚好。
  /// 整列套 `FittedBox(scaleDown)` 兜底：窄了或系统字号放大时整体缩小，不会折行。
  static const double timeColumnWidth = 34;

  /// 一格（一节课）的高度：外观设置里可调，默认 72。
  double get rowHeight => model.cellHeight;

  @override
  Widget build(BuildContext context) {
    final view = model.rescheduleViewFor(week);
    final entries = view.entries;
    // 备注区显示时它自己会留 dock 内边距，网格底部只留一点点，
    // 免得"网格的 dock 间距 + 备注的 dock 间距"变成两大块空白。
    final bottomInset = FloatingDock.contentInset(context);

    // 同一天节次重叠的课（重修 / 分班）→ conflictLayout 并排；据此算出
    // ① 哪些天有"课表时间冲突"（表头画黄底）② 哪些卡片要打冲突点。
    final layout = conflictLayout(entries);
    final timetableConflictDays = <int>{};
    final conflictEntryKeys = <String>{};
    for (final entry in entries) {
      if ((layout[entry.id]?.total ?? 1) > 1) {
        timetableConflictDays.add(entry.day);
        conflictEntryKeys.add(_entryKey(entry));
      }
    }
    // 调课冲突：调过来的课顶掉了原课（原课已被抑制、不显示），这张"调过来"的卡片
    // 也要打冲突点——否则只看到表头黄底、冲突卡上却没有标记。
    for (final conflicts in view.conflicts.values) {
      for (final conflict in conflicts) {
        conflictEntryKeys.add(_entryKey(conflict.winner));
      }
    }

    return Column(
      children: <Widget>[
        _DayHeader(
          model: model,
          week: week,
          timeColumnWidth: timeColumnWidth,
          conflicts: view.conflicts,
          timetableConflictDays: timetableConflictDays,
        ),
        Expanded(
          // 课表已就绪、这一周确实没课 → 给解释；还在加载 / 出错 → 只铺空网格
          // （进度和错误都由状态弹窗说，这里不该再显示"第 N 周没有课"）。
          child: entries.isEmpty && model.status == AppStatus.ready
              ? _EmptyWeek(model: model, week: week, bottomInset: bottomInset)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final rows = model.gridSectionCount;
                    final dayWidth =
                        (constraints.maxWidth - timeColumnWidth) / 7;
                    return SingleChildScrollView(
                      // 同上：竖向滚动也从按下那一点开始算，慢拖才跟手。
                      dragStartBehavior: DragStartBehavior.down,
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: Column(
                        children: <Widget>[
                          SizedBox(
                            // 高度固定：行数 × 行高，不随内容变。
                            height: rows * rowHeight,
                            child: Stack(
                              children: <Widget>[
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _GridPainter(
                                      rows: rows,
                                      rowHeight: rowHeight,
                                    ),
                                  ),
                                ),
                                ..._buildTimeLabels(context, rows),
                                ..._buildCourseBlocks(
                                  context,
                                  entries,
                                  layout,
                                  conflictEntryKeys,
                                  rows,
                                  dayWidth,
                                  constraints.maxWidth,
                                ),
                              ],
                            ),
                          ),
                          // 备注放在网格下面、跟着一起滚，不固定在屏幕上。
                          _ScheduleRemarks(model: model),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 卡片唯一键：同一门课可能有多个实例（跨周 / 调课后的目标实例），
  /// 用「id + 星期 + 起止节次」区分一张具体的卡片。
  static String _entryKey(ScheduleEntry entry) =>
      '${entry.id}|${entry.day}|${entry.startPeriod}|${entry.endPeriod}';

  /// 左侧时间轴：一节一行，三行居中——节数（大字）、开始时间、结束时间。
  ///
  /// 表头不写"节"字：第一列的意思从这三行字里一眼就能看出来，
  /// 多一个标签只是占掉一行高度。
  List<Widget> _buildTimeLabels(BuildContext context, int rows) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (var period = 1; period <= rows; period++) {
      final start = model.startLabelOf(period);
      final end = model.endLabelOf(period);
      widgets.add(
        Positioned(
          left: 0,
          top: (period - 1) * rowHeight,
          width: timeColumnWidth,
          height: rowHeight,
          // 整列套 scaleDown 兜底：格子高度调到最小（56）又赶上系统字号放大时，
          // 节数会在这个 34px 宽的列里折成两行（实测 40px 高），三行加起来
          // 就比行高高出零点几像素——调试模式下就是一条黄黑溢出条纹。
          // 缩放而不是折行：时间轴的每一节必须正好占一行。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  '$period',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (start.isNotEmpty) _clock(start),
                if (end.isNotEmpty) _clock(end),
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// 时刻一行放得下就原样，放不下（超大系统字号 / 等宽字体）就整体缩一点。
  ///
  /// 整列已经套了 `FittedBox`，这里的子项拿到的宽度无界、不会折行，
  /// 所以只需保持单行，具体缩放交给外层统一处理。
  static Widget _clock(String text) =>
      Text(text, maxLines: 1, softWrap: false, style: _timeAxisStyle);

  /// 时间轴上的时刻：小一号、灰色，不跟节数抢注意力。
  static const TextStyle _timeAxisStyle = TextStyle(
    fontSize: 10,
    height: 1.25,
    color: Color(0xFF8C929B),
  );

  List<Widget> _buildCourseBlocks(
    BuildContext context,
    List<ScheduleEntry> entries,
    Map<String, ({int index, int total})> layout,
    Set<String> conflictEntryKeys,
    int rows,
    double dayWidth,
    double totalWidth,
  ) {
    final blocks = <Widget>[];
    for (final entry in entries) {
      if (entry.day < 1 || entry.day > 7) continue;
      final start = entry.startPeriod < 1 ? 1 : entry.startPeriod;
      if (start > rows) continue;
      final end = entry.endPeriod > rows ? rows : entry.endPeriod;
      if (end < start) continue;

      final slot = layout[entry.id] ?? (index: 0, total: 1);
      final top = (start - 1) * rowHeight + 2;
      // 高度固定：按节数算，不随内容长高。
      final height = (end - start + 1) * rowHeight - 4;
      final gap = 2.5;
      final cellWidth = dayWidth - 4;
      final width = cellWidth / slot.total - (slot.total > 1 ? gap : 0);
      final left =
          timeColumnWidth +
          2 +
          (entry.day - 1) * dayWidth +
          slot.index * (width + gap);

      blocks.add(
        Positioned(
          left: left,
          top: top,
          width: width < 24 ? 24 : width,
          height: height < 26 ? 26 : height,
          child: CourseBlock(
            entry: entry,
            showTeacher: model.showTeacher,
            showLocation: model.showLocation,
            textScale: model.courseTextScale,
            // 冲突（时间重叠 或 调课顶掉原课）→ 卡片右上角打冲突点。
            conflict: conflictEntryKeys.contains(_entryKey(entry)),
            onTap: () => showEntryDetails(context, entry, week),
          ),
        ),
      );
    }
    return blocks;
  }
}

/// 表头：周几 + 日期，今天所在列高亮；有调课冲突的列显示提示点并可点击查看。
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.model,
    required this.week,
    required this.timeColumnWidth,
    required this.conflicts,
    required this.timetableConflictDays,
  });

  final AppModel model;
  final int week;
  final double timeColumnWidth;

  /// 本周每天的调课冲突（星期 → 被顶掉的原课）。表头据此显示提示点。
  final Map<int, List<RescheduleConflict>> conflicts;

  /// 本周哪些天有"课表时间冲突"（同一天多节课节次重叠、已并排显示）。表头也显示提示点。
  final Set<int> timetableConflictDays;

  /// 调课冲突的提示点：琥珀色，浅色主题下也醒目。
  /// （conflictHeaderColor 仍供冲突详情卡片 _ConflictCard 作背景使用。）
  static const Color conflictHeaderColor = Color(0xFFFFE9A8);
  static const Color conflictDotColor = Color(0xFFE6A700);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final termStart = model.termStart;
    final today = DateTime.now();
    final showToday = week == model.currentWeekOfToday;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          // 时间列不写表头（"节"字去掉）：只占位，让七列与网格对齐。
          SizedBox(width: timeColumnWidth),
          for (var day = 1; day <= 7; day++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final date = termStart == null
                      ? null
                      : dateOf(termStart, week, day);
                  final isToday =
                      showToday && date != null && _isSameDay(date, today);
                  final dayConflicts = conflicts[day];
                  final hasRescheduleConflict =
                      dayConflicts != null && dayConflicts.isNotEmpty;
                  final hasTimetableConflict = timetableConflictDays.contains(
                    day,
                  );
                  // 调课冲突、课表时间冲突，都在表头显示提示点。
                  final hasConflict =
                      hasRescheduleConflict || hasTimetableConflict;
                  final Color? background = isToday
                      ? theme.colorScheme.primary.withValues(alpha: 0.10)
                      : null;
                  final Color textColor = isToday
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface;
                  final Color dateColor = isToday
                      ? theme.colorScheme.primary
                      : theme.hintColor;

                  final cell = Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: <Widget>[
                        Text(
                          '周${kDayLabels[day - 1]}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        Text(
                          date == null ? '' : '${date.month}/${date.day}',
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.3,
                            color: dateColor,
                          ),
                        ),
                        // 冲突提示点：让"可点击"这件事被眼睛先发现。
                        if (hasConflict)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: conflictDotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  );

                  if (!hasConflict) return cell;
                  // 只有调课冲突才弹详情（被顶掉的原课看不见，需要点开才知道）；
                  // 纯课表时间冲突的课已经并排显示在格子里了，黄底 + 提示即可。
                  if (!hasRescheduleConflict) {
                    return Tooltip(
                      message: '周${kDayLabels[day - 1]}有课程时间冲突',
                      child: cell,
                    );
                  }
                  return Tooltip(
                    message: '周${kDayLabels[day - 1]}有调课冲突，点击查看',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => showDayConflicts(context, day, dayConflicts),
                      child: cell,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 表头冲突详情：列出因调课被顶掉、本周不显示的课，以及是谁占了位置。
void showDayConflicts(
  BuildContext context,
  int day,
  List<RescheduleConflict> conflicts,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DayConflictSheet(day: day, conflicts: conflicts),
  );
}

class _DayConflictSheet extends StatelessWidget {
  const _DayConflictSheet({required this.day, required this.conflicts});

  final int day;
  final List<RescheduleConflict> conflicts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: _DayHeader.conflictDotColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '周${kDayLabels[day - 1]} · 调课冲突',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '调课与原课时间冲突，已优先显示调课；'
                '下面这些课本周不显示。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 12),
              for (final conflict in conflicts)
                _ConflictCard(conflict: conflict),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.conflict});

  final RescheduleConflict conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displaced = conflict.displaced;
    final winner = conflict.winner;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    displaced.name,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _DayHeader.conflictHeaderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '未显示',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '周${kDayLabels[displaced.day - 1]} '
              '第 ${displaced.startPeriod}-${displaced.endPeriod} 节'
              '${displaced.teacher != null ? ' · ${displaced.teacher}' : ''}'
              '${displaced.location != null ? ' · ${displaced.location}' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '该时段显示了调课「${winner.name}」'
              '（第 ${winner.startPeriod}-${winner.endPeriod} 节）。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.rows, required this.rowHeight});

  final int rows;
  final double rowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE4E6EB)
      ..strokeWidth = 0.5;
    for (var row = 0; row <= rows; row++) {
      final y = row * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // 时间列右侧 + 7 天分界
    final dayWidth = (size.width - _WeekView.timeColumnWidth) / 7;
    for (var column = 0; column <= 7; column++) {
      final x = _WeekView.timeColumnWidth + column * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    canvas.drawLine(
      Offset(_WeekView.timeColumnWidth, 0),
      Offset(_WeekView.timeColumnWidth, size.height),
      paint..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.rows != rows || oldDelegate.rowHeight != rowHeight;
}

class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek({
    required this.model,
    required this.week,
    required this.bottomInset,
  });

  final AppModel model;

  /// 这一页自己的周次。**不能读 `model.week`**：滑动中 model 的周次会落后
  /// 半页（状态等停稳才落定），照着它写会显示出"第 1 周没有课"却停在第 2 周。
  final int week;

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.beach_access_outlined,
                size: 44,
                color: theme.hintColor,
              ),
              const SizedBox(height: 12),
              Text('第 $week 周没有课', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '可能是假期、考试周，或者周次校准不准。\n'
                '如果这周实际有课，用「校准当前周次」对准一次。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => showCalibrateSheet(context, model),
                child: const Text('校准周次'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选周：从周次文字**下方**弹出菜单，点哪周跳哪周。
///
/// 用锚定菜单而不是底部弹窗：周次条就在屏幕上方，菜单从那里展开时
/// 眼睛不用来回跳；菜单自带滚动与"点外面关闭"。
Future<void> showWeekPicker(
  BuildContext context,
  AppModel model, {
  int? current,
}) async {
  final selected = current ?? model.week;
  await showAppMenu<int>(
    context: context,
    maxHeight: 340,
    items: <AppMenuItem<int>>[
      for (var week = 1; week <= model.maxWeek; week++)
        AppMenuItem<int>(
          value: week,
          label: '第 $week 周',
          trailing: week == selected
              ? Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
    ],
    onSelected: model.goToWeek,
  );
}

/// 校准："本周实际是第几周" → 反推开学日并持久化。
void showCalibrateSheet(BuildContext context, AppModel model) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CalibrateSheet(model: model),
  );
}

/// 校准弹窗的内容。
///
/// 单独一个 StatefulWidget：输入框的 [TextEditingController] 由它持有，
/// 弹窗关掉时跟着 dispose —— 控制器放在函数里 new 出来就没人管了（泄漏），
/// 而在弹窗退场动画还没走完时就 dispose 又会报"disposed 后又被使用"。
class _CalibrateSheet extends StatefulWidget {
  const _CalibrateSheet({required this.model});

  final AppModel model;

  @override
  State<_CalibrateSheet> createState() => _CalibrateSheetState();
}

class _CalibrateSheetState extends State<_CalibrateSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.model.currentWeekOfToday}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppModel model = widget.model;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('校准当前周次', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '教务系统不提供开学日期，所以"第几周"需要对齐一次。\n'
            '填「本周实际是第几周」，之后按日历自动推算，并记住这个学期。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: '本周是第几周'),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              FilledButton(
                onPressed: () {
                  final week = int.tryParse(_controller.text.trim());
                  if (week != null && week > 0) {
                    model.calibrateCurrentWeek(week);
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('保存'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  model.resetCalendar();
                  Navigator.of(context).pop();
                },
                child: const Text('恢复默认估算'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 课表页下方的"备注"区：实践课程 / 其他课程（来自课表响应的 `sjkList`）。
///
/// 它放在周网格的滚动内容里（网格下面），跟着课表一起滚；没有备注时不占地方。
class _ScheduleRemarks extends StatelessWidget {
  const _ScheduleRemarks({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    if (!model.showScheduleRemarksSection) return const SizedBox.shrink();
    final remarks = model.scheduleRemarks;
    final practical = remarks.where((r) => r.practical).toList();
    final others = remarks.where((r) => !r.practical).toList();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.sticky_note_2_outlined,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '备注',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          if (practical.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _RemarkGroup(
              title: '实践课程',
              remarks: practical,
              accent: scheme.primary,
            ),
          ],
          if (others.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            _RemarkGroup(
              title: '其他课程',
              remarks: others,
              accent: scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

class _RemarkGroup extends StatelessWidget {
  const _RemarkGroup({
    required this.title,
    required this.remarks,
    required this.accent,
  });

  final String title;
  final List<ScheduleRemark> remarks;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 分组小标签：淡色底 + 同色字，比一行灰字清楚。
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final remark in remarks) _RemarkCard(remark: remark),
      ],
    );
  }
}

class _RemarkCard extends StatelessWidget {
  const _RemarkCard({required this.remark});

  final ScheduleRemark remark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 主行：sjkcgs（教务网页显示的字段）；为空则退回课程名。
    final main = remark.content.isNotEmpty
        ? remark.content
        : (remark.courseName ?? '');
    // 次行：课程名（与主行不重复时）/ 教师 / 周次 / 地点。
    final sub = <String>[
      if (remark.courseName != null && remark.courseName != main)
        remark.courseName!,
      if (remark.teacher != null) remark.teacher!,
      if (remark.weeks != null) remark.weeks!,
      if (remark.location != null) remark.location!,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (main.isNotEmpty)
            Text(
              main,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          if (sub.isNotEmpty) ...<Widget>[
            if (main.isNotEmpty) const SizedBox(height: 5),
            Text(
              sub.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
