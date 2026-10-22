# 交接文档：课表页 / 设置页切换的性能与交互改造

> 写于 2026-10-22。上一轮任务在收尾阶段因额度中断，本文档记录**已完成什么、为什么这么做、怎么验证、还剩什么**。
> 当前状态：`flutter test` **230 项全绿**，`flutter analyze lib test` 只剩 `status_popup.dart` 一条既有 info，`dart format` 无差异，改动**未提交**（都在工作区）。

---

## 一、任务需求（用户原话要点）

1. 修复课表页 ↔ 设置页切换、以及设置页内部子页面切换的**明显卡顿**（定位页面重建 / 重复渲染 / 动画计算等原因）。
2. 课表页与设置页之间的切换动画改为**水平平移**。
3. 平移动画要**与底部 dock 栏滑动联动跟随**，dock 滑动过程中页面同步位移。
4. **禁止在页面内容区域用手势切换两页**（避免和课表页内部的翻周手势冲突），只允许 dock 触发。

第 1 项是性能，2/3/4 是交互。

---

## 二、根因（都用探针在真实渲染树里量过，debug/JIT 环境）

| 根因 | 说明 | 实测 |
|---|---|---|
| **外壳每次 `setState` 都新建页面 widget 实例** | `SchedulePage(model: model)` 在 `build` 里每次 new 一个 → widget 不同 instance → 整棵子树重建 | 切换一帧 **56.7ms**；缓存实例后 **6.9ms** |
| **用 `Opacity` 做交叉淡入淡出** | `RenderOpacity` 在 `0 < alpha < 1` 时强制 `saveLayer`（整页离屏缓冲），框架源码里明确注释 "expensive"，动画期间**每帧**都做 | 平移动画后切页帧 ≤13ms |
| **设置页/子页面整页监听整个 `AppModel`** | 任何 model 通知（后台刷新课表、换周次…）都让设置页整页重建，而设置页显示的东西根本没变 | 无关通知重建 **21~26ms** → 现在 **0.0ms** |
| **子页面首帧是冷构建** | `push` 时新页首次构建 + 首次文本排版（字体/字形缓存冷） | push 首帧 96–126ms → 现在 **42.8ms**（首次）/ **23.2ms**（第二次） |

补充：`MaterialPageRoute` 在桌面端默认走 `ZoomPageTransitionsBuilder`（缩放 + 整页快照），项目原本已用自定义 `_QuickFadeTransitionsBuilder`（淡入 + 微位移），但淡入同样触发 `saveLayer`。

---

## 三、改了什么（9 个文件）

### 1. `lib/pages/home_shell.dart`（改动最大，基本重写）

**旧的**：`Stack` + 两个 `Positioned.fill` + `Opacity` 交叉淡入，每页用 `IgnorePointer` / `TickerMode` 控制。

**新的**：`_ShellPager` —— 自己搭的横向轨道。

- `AnimationController`（260ms）表示"当前在轨道上的位置"，`0.0` = 课表页正中，`1.0` = 设置页正中。
- 每页套 `Positioned.fill` → `IgnorePointer` → `TickerMode` → `RepaintBoundary` → `AnimatedBuilder` → `Transform.translate(offset: (index - position) * width)`。
- **只重建变换**，页面内容一个字节都不动；`RepaintBoundary` 让平移只重新合成缓存图层。
- **两页常驻**，切回来时状态（展开项、滚动位置）不丢。

为什么不用 `PageView`：
1. `PageView`（含 `children:` 构造）会**回收离屏页** → 切回来设置页被重建、状态丢失；
2. 需要能被外部（dock）**逐帧精确写位置**，而不是等手势自己结算。

为什么内容区没有切换手势：**这一层完全不注册任何手势**。课表页内部有自己翻周的 `PageView`，若外壳也接横向拖动，两套手势会打架（滑一下既翻周又切页）。所以两页切换只能由 dock 触发 —— 这正好也满足需求 4。

页索引的时序（重要，别改回去）：
- 页面位置**只有一个写入方**：`_ShellPagerState.followPill(progress)`，值来自 dock 的指示块；
- 页面**自己没有动画**（`AnimationController` 的 duration 是 0），指示块滑到哪，分界就在哪；
- `_index` 由 `_onTick()` 在**位置正好压在整页上**（`|offset - round| <= 0.001`）时才上报；
  不能按 `round()` 判，否则滑到一半（0.5）就把当前页切了，`IgnorePointer`/`TickerMode`
  提前跳、动画也会被打断。

> 历史包袱提醒：这里曾经是"dock 报落点 + 页面自己 `animateTo` 260ms"，与指示块的 180ms
> **两套动画**并行。结果必然是"阴影停了、页面还在滑"（或反过来）。已全部删除，
> 别再引回来 —— 任何"页面自己再补一段动画"的写法都会重新引入这个错位。

设置页的懒建：`Widget? _settingsPage`，由 `FloatingDock.onPressStart`（手指**按下** dock 的瞬间）触发 `_ensureSettingsPage()`。建好之后永久保留。

> **踩过的坑（两次尝试都回退了，别再走）**
>
> 1. `SchedulerBinding.scheduleTask(Priority.idle)` 自动预建 —— 它的实现是 `Timer.run`，会在测试里留下 pending timer 导致用例失败；而且它仍占 UI 线程。**不要再走这条路**。
> 2. 首帧之后延一帧（`addPostFrameCallback` 链）预建 —— 实测那正好把 40~100ms 的构建砸在用户刚看到课表、正要滑动的那一帧上，换来的是启动卡顿，不值。
>
> **重要（当时的误判，已纠正）**：中途我以为它"与冷启动测试冲突"，其实不是。那一次的测试失败是 pending Timer，不是断言。真相是**那条测试当时根本拦不住这种写法** —— 它只在第一帧断言 `SettingsPage` 不存在，而延帧预热发生在第 2 帧，断言照样通过。也就是说这条契约当时是空的。
>
> 现在已经补实：`冷启动首帧不建设置页…` 这条用例在首帧断言之后**再 pump 8 个空闲帧**，继续要求 `SettingsPage` 不存在。我把"延帧预热"临时加回去验证过，这条断言会立刻变红（`Found 1 widget with type "SettingsPage"`），不是空转。

### 2. `lib/widgets/floating_dock.dart`

新增两个可选回调：

- `onDragProgress(double)` —— 拖动过程中的**连续**位置（0..1）。换算依据是**指示块中心**在首末两项中心之间的比例，不是手指落在哪一段：指示块跟着手指滑，页面跟着指示块走才叫"同步位移"。
- `onPressStart()` —— 指针按下（还没决定点还是拖）就触发，用来预建另一页。

另外把落点上报改成**无条件**（原来 `if (target != widget.index)` 才报）：
- `_onDragEnd` / `_onTapUp` / `_onDragCancel` 都总是调 `onChanged`；
- 否则"轻扫没到阈值"时页面被拖到半路，没人通知它弹回整页，就卡在 0.39 这种位置。

### 3. `lib/theme/app_theme.dart`

`_QuickFadeTransitionsBuilder` → `_SlideTransitionsBuilder`：**纯位移，无透明度**。

- 新页从右侧 `0.28` 页宽推入（`easeOutCubic`，220ms）；
- 旧页随 `secondaryAnimation` 往左让 `0.12` 页宽（180ms 反向）；
- `route.isFirst` 直接返回 `child`（启动直达不做转场）。

为什么不保留淡入：`FadeTransition` 在 alpha<1 时同样强制 `saveLayer`。纯位移只做 `Transform`，不产生离屏缓冲。这也顺带让"设置页内部子页面切换"和外壳的平移语言一致。

> 这个 builder 是**全局**的（android / windows / linux / fuchsia）。已确认项目里所有 `Navigator.push` 都是"进入子页面"语义，水平位移对登录页、调试页同样正确。

### 4. `lib/src/app_model.dart`

新增 `prefsNotifier`（`ValueNotifier<int>` 或类似），以及私有 `_notifyPrefs()`。

- **只在设置页关心的东西真变了时才发通知**：偏好开关、节数、作息表增删、账号/登录状态、教务地址簿、学期起始日（校准）。
- `dispose()` 里要 `prefsNotifier.dispose()`。
- 已有先例：`weekNotifier`（换周不整页重建）是同一套思路，上一轮加的。

### 5–7. `lib/pages/settings_page.dart`、`timetable_list_page.dart`、`school_address_page.dart`

`ListenableBuilder(listenable: model)` → `ListenableBuilder(listenable: model.prefsNotifier)`。

> **踩过的坑**：本想用 `Selector` 做值比较收窄重建，但这个 Flutter 版本（3.47 分支）**没有 `Selector`**（`grep -rn "class Selector" packages/flutter/lib/src` 无结果）。所以改用"专用通知源"的方案，和项目既有做法一致。

### 8. `lib/pages/reschedule_page.dart`

只有 `dart format` 的换行差异，无逻辑改动。

### 9. `test/widget_test.dart`

测试 helper `pageOpacity()` 已删除，换成：

```dart
double shellPagePosition(WidgetTester) // 轨道位置：0=课表正中，1=设置正中
int shellCurrentPage(WidgetTester)     // 停稳在第几页，卡半页返回 -1
```

新增/改写的用例（`两页外壳与设置` 组）：
- `dock 在课表与设置之间切换`
- `从课表往右拖到设置，再拖回来`
- **`dock 拖动过程中页面同步位移`**（需求 3 的锁）
- `均分判定：轻微右滑不误切（阈值在胶囊中线）`
- **`内容区横向拖动不切换页面`**（需求 4 的锁）
- **`切页是水平平移，不是透明度变化`**（需求 2 的锁）
- `切到设置的中途点回课表，动画被接管且终态正确`
- `冷启动首帧不建设置页，第一次切过去才建（之后就常挂）`：首帧断言 + **再 pump 8 个空闲帧仍要求不存在**（拦住「延帧预建」这类写法），外加 `Element` 身份断言「进过一次后没被重建」

---

## 四、实测数据（同一台机、同场景、debug 构建）

| 场景 | 改造前 | 现在 |
|---|---|---|
| 切课表（每帧最大） | **56.7 ms** | **12.1 ms** |
| 切设置（第 2 次起，每帧最大） | **57.2 ms** | **12.9 ms** |
| 切设置（**第 1 次**） | 57 ms + 未预建 | **95.7 ms**，但落在"手指按下 dock"那一帧（还没开始滑），滑动首帧只 **3.3 ms** |
| dock 拖动逐帧 | —（无此交互） | **2.7 ~ 5.9 ms** |
| 设置页被无关 model 通知重建 | **21–26 ms** | **0.0 ms**（不再监听） |
| push 设置页子页面首帧 | **96–126 ms** | **42.8 ms**（首次）/ **23.2 ms**（再次） |
| push 之后每帧 | 有 38 ms 尖峰 | 1–7 ms |

> 数字都是 **debug + 测试环境**（无 GPU 加速、JIT）。release 上绝对值会明显更小，但**相对改善**是有效的。

---

## 五、怎么验证

```bash
cd D:/directory/Desktop/my_work/ke_biao/qustschedule

# 注意：本机沙箱代理会打断 flutter_tester 的 websocket 握手，必须去掉代理变量
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test

# 只跑切换相关
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  flutter test test/widget_test.dart --plain-name "两页外壳与设置"

flutter analyze lib test
dart format --output=none --set-exit-if-changed lib test
```

手动验证清单（真机 / 桌面端都要看）：
1. 点 dock 切页 → 水平平移，无淡入、无闪烁；连点两个按钮，动画被接管且终态正确。
2. 按住 dock 指示块横向拖 → 页面**逐帧跟手**，松手吸附；轻扫不过半应弹回原页，不能停在半页。
3. 在课表页内容区横向拖 → **只翻周，不切页**；在设置页内容区横向拖 → 什么都不发生（列表只能上下滚）。
4. 切到设置页 → 进"作息时间表" → 返回 → 再进一次，第二次进入应明显更快。
5. 在设置页停留时触发后台刷新（下拉课表刷新）→ 设置页不应有任何重建抖动。
6. 切回课表页 → 之前停在第几周、滚动位置都还在；设置页的展开项也不丢。

---

## 六、遗留问题 / 下一步（按价值排序）

1. **第一次进设置页的 95.7ms** 目前落在"按下 dock"那一帧。理论上还能再降：设置页是 `ListView` + 40 多个 `ListTile`/`SwitchListTile`，可以拆成 `CustomScrollView` + 分节懒构建，或把不常改的"关于/协议"分节延后。**但不要再试"首帧后自动预建"**（见上面的坑）。
2. **新页首次进入视口仍要建一次网格**（课表翻页时每进一个新页约 63ms，release 会小很多）。上一轮的结论：`allowImplicitScrolling` + `scrollCacheExtent: viewport(1)` 在 3.47 的 `SliverFillViewport` 上**不生效**（实测无效，已回退）。要彻底消掉得自己接管视口，成本高。
3. **设置页子页面仍是 `Navigator.push`**，每次 push 都是新实例、全新构建（23ms）。如果还嫌慢，可以考虑"预建 + 复用实例"（把子页面常挂在设置页的 `Stack` 里，用 `Visibility` 控制），但要自己接管返回键与 `WillPopScope` 语义，改动面不小。
4. **没做的**：`compute`/isolate 解析缓存 JSON。这个数据量下起 isolate 的开销比解析本身还大，评估后放弃。

---

## 七、交付前复查发现并修掉的问题（2026-10-22 第二轮）

逐项复查未暂存改动时抓到三处，都已修 + 已补测试：

| # | 问题 | 影响 | 修法 |
|---|---|---|---|
| 1 | `_applyCalendar()` **无条件** `_notifyPrefs()`，而它每次加载课表都会走到（含后台刷新） | 后台刷新一次 → 设置页白重建 2 次（实测 `prefsNotifier` 触发 2 次，17~19ms/次）。**恰好是这次想消掉的开销，等于没修** | 只在 `_termStart` 真的变了时通知；`hydrateForTest` 同理按 `termId/姓名/学号` 是否变化判断 |
| 2 | `changeSchool()` 里 `_notifyPrefs()` 排在 `_restoreAccount()` **之前** | 设置页会在"账号已清空、还没读回"的中间态渲染一次，显示空账号 | 先 `_restoreAccount()` 再通知 |
| 3 | `home_shell.dart` 文件头、`app_theme.dart` 类注释仍写着旧的 `PageView` / 淡入方案 | 注释与实现不符，下一个人会照错的理解改 | 改成"自建横向轨道 + 纯位移"，并删掉重复的旧注释块 |

顺带修正：

- `RepaintBoundary` 原来套在 `Transform` **外层**，导致每次平移都把边界标脏；已挪到内层（`Transform > RepaintBoundary > 页面`）。实测帧耗在这台机器上没差异（15.15 vs 16.89 ms/帧，噪声级），保留是因为这才是"平移只改图层位置"的正确嵌套。
- `两页之间是水平平移` 用例的断言原本是空的：起手点在"设置"上，进度本来就是 1，`greaterThan(0)` 恒真。已改成从"课表"起手 + `allOf(>0, <1)`。
- 新增回归用例 `重载同一份课表不触发偏好通知`，并验证过：把通知改回无条件，它会红（Expected 0 / Actual 2）。

当前：`flutter test` **231 项全绿**，`flutter analyze` 仅 `status_popup.dart` 一条既有 info，`dart format` 零差异。

### 第三轮：dock 切换改成"页面跟随指示块"（2026-10-22 下午）

**现象（先后两版）**：
1. 按住 dock 的"设置"，指示块跟到设置上，但页面不动；按住不放直接松手，页面切过去了，指示块却弹回课表再弹回来。
2. 改完第一版后：点击时阴影停在"手指点的位置"，没有归位到按钮中心；且页面与阴影各自滑动，看起来阴影先停下、页面还在动。

**根因（四条）**：

1. `_reportDragProgress()` 里 `if (!_dragging) return` —— "按下未拖"时页面收不到位置。
2. 松手时 Tap 赢仲裁 → 横向拖动识别器被**拒绝** → `_onDragCancel()` 把指示块弹回 `widget.index` 并上报旧页，与 `onTapUp` 打架（实测回调 `[1, 0, 1]`）。
3. **`_DockButton` 内部有自己的 `InkWell(onTap:)`**：点击落在按钮上时内层赢仲裁，外层 `onTapUp` 根本不触发 → "点哪算哪"和"指示块归位"走了两条不同的路，落点不一致。
4. 页面走 `animateTo` 260ms、指示块走 180ms —— **两套动画**，必然错位。

**最终设计**：只保留**一处运动源**。

- dock 用 `onPillProgress(double)` 逐帧上报**指示块真实矩形**换算出的位置（按下 / 拖动 / 松手三种时机都报，由 `_slide` 监听 + 手势回调驱动）；
- 外壳 `followPill(progress)` 直接写页面位置，**页面自己不跑动画**；
- 落点（`_index`）由 `_onTick` 在位置正好压在整页上时结算；
- 删掉 `onChanged` / `settleTo` / `scrubTo` / `_settlingTo` / `_scrubbing`；
- `_DockButton` 去掉自己的 `InkWell`，点击统一由外层 `GestureDetector` 处理（它本来就覆盖整条胶囊，而且没有水波纹/高亮，`InkWell` 只是多余的仲裁参与者）；
- 高亮用 `_visualIndex`：按着跟手指，松手后保持落点直到 `widget.index` 追上来。

**顺带修的两个坑（都在 dock 内部）**：

- `_pillRect` 原来用 `_slide.isAnimating` 判断是否取插值，而 `forward(from: 0)` 内部先 `stop()`
  再通知 → 通知瞬间 `isAnimating == false`，会报出"已在终点"的错值（页面先跳到底再退回重滑）。
  改成按**进度值**判断（`t >= 1 ? _to : lerp(...)`）。
- `_onDragEnd` / `_onDragCancel` 里先把 `_dragging = false` 再 `_snapTo`，导致起点取到按下时的
  旧位置（指示块松手瞬间跳回去）。改为**先取 `_livePillRect`**，作为 `from` 传进 `_snapTo`。

**测试**：2 条（`dock：点击后指示块落到按钮上，全程不回弹`、`按住 dock 不滑动，页面也跟着切过去`）。
前者断言位置序列单调、末尾为 1.0（旧实现会先出现一次 0），后者断言按住 300ms 内页面已到目标页。
全量 231 项通过。

---

## 八、这个项目里通用的注意事项

1. **跑测试必须去代理**：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test`，否则 `flutter_tester` websocket 握手失败（`Invalid WebSocket upgrade request`）。
2. **`Opacity` 在 0<alpha<1 时必开 `saveLayer`**，别用它做整页动画；要淡入淡出请用 `FadeTransition` 之外的方案，或接受它的代价。
3. **widget 实例身份就是重建开关**：`build` 里 `Page(model: model)` 每次 new 一个，即使 model 没变也会整棵重建。缓存在 `late final` 字段里。
4. **`weekNotifier` / `prefsNotifier` 是项目既定模式**：高频且局部的状态（当前周次、偏好设置）走自己的通知源，不要靠 `notifyListeners()` 一把梭。
5. **课表页的翻页器**在 `lib/widgets/week_pager.dart`（一次滑动只翻一页、落点以起手页为锚、落页弹簧 170ms）。外壳的平移和它**互不干扰**，改任一侧时注意别把 `dragStartBehavior: DragStartBehavior.down` 之类的设置碰掉。
6. **测量用一次性探针**：`test/perf_probe_test.dart` 里写 `Stopwatch` 包 `tester.pump()`，跑完立刻删（本次已删净，`git status` 里不应有 `test/perf_probe_test.dart`）。
