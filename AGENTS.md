# 青科课表通 (`qustschedule`) · AI 主入口与架构导航 (`AGENTS.md`)

> **定位**：本仓库（`com.fangzi.qustschedule`，GPL-3.0，Flutter Android + Windows 客户端）独立自包含的 AI 协作主入口与极速路由枢纽。单独 `git clone` 本仓库即可直接查阅全部架构契约与文档，零外部路径依赖。
>
> **阅读策略**：本文件仅保留**核心铁律、任务路由、文档维护触发器、高频防坑与一键验证命令**；具体类签名、状态机与全量文件地图按下方路由直达 `docs/dev/*.md`，避免盲目全库扫描。代码与文档冲突时以现行源码为准，并在同次任务中同步更新对应专题文档。

---

## 一、工程硬性铁律（不可逾越）

1. **版本号唯一真源**：严禁在文档、Dart、Kotlin、C++ 或测试断言中硬编码版本号；唯一真源为 [`pubspec.yaml`](pubspec.yaml) 的 `version:`（运行时由 [`lib/src/app_version.dart`](lib/src/app_version.dart) 异步读取）。
2. **仓库洁净与格式门禁**：Dart 代码严格 `dart format`（单行 ≤ 80 列）；任务结束前确认 `git status` 无遗留临时文件。
3. **青岛科技大学专属边界**：仅内置 1 条青科大外网教务线路 `https://jwglxt.qust.edu.cn/jwglxt`（仍支持自定义地址）；严格**两学期制**（秋 `3` / 春 `12`，历史 `'16'` 自动收敛不外显）；GPA 文案固定为**「学期平均学分绩点 (GPA)」**；10 位学号按 `2000 + YY` 推导入学年（超 5 年回退学年学期标签）。
4. **单向分层依赖**：`lib/pages/ & lib/widgets/ → AppModel (及 5 大 State Controller) → ScheduleService / AcademicService / ReminderService / DesktopWidgetService → packages/zf_academic & Repositories`。UI 层严禁直调 Service/Cache/Repository/`ZhengfangClient`；[`packages/zf_academic`](packages/zf_academic/) 为**零 Flutter 依赖**纯 Dart 包。
5. **平台红线**：
   - **Windows**：[`windows/runner/`](windows/runner/) 下 `.cpp`/`.h` **严禁出现中文注释或中文字符字面量**（MSVC CP936 报 `C4819`，UI 文案用 `\uXXXX` 转义）；`Runner.rc` 保持 `UTF-16LE + BOM`；产物名恒为 `qustschedule.exe`（绑定 DPAPI、AppData 与互斥锁 `Local\com.fangzi.qustschedule.SingleInstance`）。
   - **Android**：Flutter 3.29+ 已合并 UI 与 Platform 主线程，MethodChannel 与 `BroadcastReceiver` **严禁在主线程读盘、设闹钟或画 Bitmap**（一律走 `ReminderWorker` / `WidgetWorker` 单线程 + `goAsync()`）；`minSdk = 24`（`widget/` 禁 `java.time.*`，用 `Calendar`）；`debug`/`release` 签名分离；`useLegacyPackaging = true`；`android:allowBackup="false"`；`android/keystore/` 与 `android/key.properties` 严禁入库。

---

## 二、专题文档索引与维护触发器 (`docs/dev/`)

| 专题文档 | 覆盖范围 | 何时必读 / 改哪类文件时必须同步更新 |
|---|---|---|
| [`docs/dev/FILE_MAP.md`](docs/dev/FILE_MAP.md) | 全量文件地图与核心导出符号索引（Dart / `zf_academic` / Android / Windows / 测试） | 新增、删除或重命名源码/测试文件时同步更新 |
| [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) | `AppModel` + 5 大控制器、认证代数与互斥重登、缓存、Schema 15、`SafeJsonFile`、自动更新、`zf_academic`、Windows 壳 | 修改 `lib/src/`（非提醒/小组件）、`packages/zf_academic/`、`windows/` 或 `updater/` 时查阅并同步 |
| [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) | `AppColors`/`AppRadius`/`CoursePalette`、18 页订阅隔离、15 个自定义动效组件契约、L0–L3 测试矩阵 | 修改 `lib/theme/`、`lib/pages/`、`lib/widgets/` 或测试架构时查阅并同步 |
| [`docs/dev/REMINDER.md`](docs/dev/REMINDER.md) | 课前提醒规划/网关/服务、Android `reminder/*.kt`（13 文件）、流体云卡片、14 天/10 天闹钟窗与权限诊断 | 修改 `lib/src/reminder_*.dart`、`lib/pages/reminder_page.dart` 或 `android/.../reminder/` 时查阅并同步 |
| [`docs/dev/WIDGET.md`](docs/dev/WIDGET.md) | 桌面小组件样式/规划/网关/服务、同构预览页、Android `widget/*.kt`（15 文件）与 XML 资源 | 修改 `lib/src/widget_*.dart`、`widget_settings_page.dart`、`desktop_widget_preview.dart` 或 `android/.../widget/` 时查阅并同步 |

---

## 三、任务 → 目标文件 × 专题文档极速路由表

| 开发 / 排障任务 | 核心目标文件 | 关联通知源 / 关键机制 | 直达专题章节 |
|---|---|---|---|
| **登录 / 自动重登 / 验证码 / 改密 / 切校** | `lib/src/schedule_service.dart`, `lib/src/state/auth_session_controller.dart`, `lib/src/app_model.dart`, `lib/pages/{login,captcha}_page.dart` | `routeNotifier`, `_authEpoch`, `_reloginFlight`, 10 分钟 2 次熔断 | [`CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1–§3 |
| **正方教务协议 / RSA / Cookie 隔离** | `packages/zf_academic/lib/src/{zhengfang_client,schedule,academic_query,html,respond,cookies,crypto,urls,errors}.dart` | 纯 Dart 零 Flutter 依赖，23 项 `ErrorCode` | [`CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §8 |
| **教务线路 / 学期推导 / 校历 / 周次校准** | `lib/src/{school,term_selector_helper,term_calendar}.dart`, `lib/src/state/schedule_controller.dart`, `lib/pages/school_address_page.dart` | `ScheduleController`, `weekNotifier`, `DateTime.utc` 整日差 | [`CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §3.4–§4.2 |
| **`Preferences` Schema 15 / 持久化读写** | `lib/src/preferences_repository.dart`, `lib/src/state/preferences_controller.dart`, `lib/src/safe_json_file.dart` | `prefsNotifier`, `SafeJsonFile` (`.tmp`/`.bak`/`>=16KB` Isolate) | [`CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §5 |
| **课表网格 / 课程卡片排版 / 冲突 / 调课** | `lib/pages/{schedule,reschedule}_page.dart`, `lib/widgets/{course_tile,week_pager,course_detail_sheet}.dart`, `lib/src/reschedule.dart` | `ScheduleController` (`_dataRevision`), `weekNotifier`, `letterSpacing: 0` + `1e-4` | [`UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.4–§4.5 |
| **学业页（考试倒计时 / GPA / 未评教）** | `lib/pages/academic_page.dart`, `lib/src/state/academic_controller.dart`, `lib/src/academic_{service,cache}.dart` | `academicNotifier`, `_academicLoadSeq`, `loadedAcademicTerm` | [`CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1.4 & §3.2 · [`UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §5 |
| **三页外壳切页 / 底部悬浮 Dock 动效** | `lib/pages/home_shell.dart`, `lib/widgets/floating_dock.dart` | 单运动源 `ValueNotifier<double>`、同向续速上限 `31.5`、按下懒建 | [`UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.1 |
| **顶栏 / 触感按钮 / 弹出菜单作用域** | `lib/widgets/{tactile_button,app_menu}.dart`, `lib/theme/app_theme.dart` | `TactileAppBar` 四层合绘、`AppMenuScope` 空间锚定与失活即收 | [`UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.2–§4.3 |
| **二级页 260ms 转场与后台加载解耦** | `lib/src/route_settled.dart`, `lib/widgets/page_skeleton.dart`, `lib/pages/{changelog,about,debug,widget_settings,reminder}_page.dart` | `RouteSettledStateMixin`, `RouteSettledGate`, `runInBackground` | [`CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §4.4 · [`UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §3.5 |
| **状态气泡 / SnackBar / 错误文案** | `lib/src/state/hint_notice_controller.dart`, `lib/widgets/{status_popup,app_snack_bar}.dart` | `hints` (`HintScope.global`/`schedule`/`academic`) | [`CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1.4 · [`UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.6 |
| **自动更新 / 代理测速 / Windows 热替换** | `lib/src/updater/*.dart`, `lib/pages/{update_dialog,update_proxy_page}.dart`, `android/.../updater/AppUpdaterBridge.kt` | `UpdateFlowController`, `.update_staging`, VBS + `robocopy /mir` | [`CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §6–§7 |
| **Android 课前提醒 / 流体云 / 权限诊断** | `lib/src/reminder_{planner,gateway,service}.dart`, `lib/pages/{reminder,settings}_page.dart`, `android/.../reminder/*.kt` | `ReminderService` (300ms 防抖+单飞), `ReminderWorker`, ID `2000`/`2001`/`2003` | [`REMINDER.md`](docs/dev/REMINDER.md) §2–§12 |
| **Android 桌面小组件 / 样式预设 / 预览** | `lib/src/widget_{style,planner,gateway,service}.dart`, `lib/pages/widget_settings_page.dart`, `lib/widgets/desktop_widget_preview.dart`, `android/.../widget/*.kt` | `DesktopWidgetService`, `WidgetWorker`, `MainActivity` `RenderMode.texture` | [`WIDGET.md`](docs/dev/WIDGET.md) §2–§15 |
| **测试套件 / 测试替身 / CI 流水线** | `test/*_test.dart`, `test/support/fake_*.dart`, `packages/zf_academic/test/*_test.dart`, `.github/workflows/build-release.yml` | L0–L3 分层门禁、4 项测试去重铁律 | [`UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §6 |

---

## 四、跨模块高频防坑清单（Do / Don't）

| 场景 | 严禁写法 (Don't) | 正确契约 (Do) | 守护测试 |
|---|---|---|---|
| **局部状态监听** | `ListenableBuilder(listenable: model)` 包裹整页，或在翻周/刷新/气泡时调根 `notifyListeners()` | 精确订阅 `routeNotifier`、`scheduleState`、`weekNotifier`、`refreshingNotifier`、`academicNotifier`、`prefsNotifier`、`hints`、`updateFlow` | `test/rebuild_scope_test.dart` |
| **课程卡片预排版** | 裸 `TextStyle` 喂给 `TextPainter`，漏 `letterSpacing: 0` 或留 `> 0.5px` 容差 | `DefaultTextStyle.of(context).style.merge(...)` + `MediaQuery.boldTextOf(context)` + `letterSpacing: 0` + `1e-4` 容差 | `test/widget_test.dart` |
| **三页外壳与顶栏菜单** | 用 `PageView` 做底栏三页、`TactileSurfaceScope` 内套 `Opacity`、菜单脱离页面坐标系 | `FloatingDock` 单运动源驱动 `_ShellPager`；`TactileAppBar` 四层合绘；页面与转场内包裹 `AppMenuScope` | `test/dock_transition_test.dart` |
| **二级页转场与选字** | 转场中途 `setState` 挂载重子树；使用重型 `SelectableText` 或多棵 `SelectionArea` | `initState` 并行 `runInBackground` + `RouteSettledStateMixin` 骨架占位；页面级**单层 `SelectionArea` + `Text`** | `test/page_transition_test.dart` |
| **Cookie 免登空串陷阱** | `sessionInfo?.username ?? accountHint`（`''` 不会被 `??` 跳过） | 按 `isNotEmpty` 顺序回退：`username` → `accountHint` → `studentId` → `prefs.accountOf` | `test/schedule_service_test.dart` |
| **跨学期考试隔离** | 切看其他学期考试时仍拼接当前学期周次，或混入桌面小组件 | 仅 `loadedAcademicTerm == model.termId` 时追加周次标签与注入小组件快照 | `test/academic_page_test.dart`, `test/widget_service_test.dart` |
| **异步按钮与定时器** | 按钮 `onPressed` 置 `null` 引起闪烁；滑块 `onChanged` 每帧写盘；裸写不可取消 `Future.delayed` | 用非 State `bool _running` 防重入；滑块 `onChanged` 改草稿、`onChangeEnd` 落盘；所有延时用可取消 `Timer` 并在 `dispose()` 清理 | `test/widget_settings_page_test.dart` |
| **测试用例去重** | 仅因场景相似就删减已有固定测试 | 删除固定测试必须同时满足：同被测对象 + 同断言集 + 同 L1/L2/L3 层级 + 不独占任何失败模式 | 全量 `test/*_test.dart` |

> **已登记确认不改动项（防过度审计）**：① 约 25+ 处协议与防锁号常数（RFC 6265 属性、PNG 魔数、10 分钟 2 次重登熔断、10s 超时、青科大默认线路、18 周保底等）属合规架构常数，严禁清理；② 正方教务无学制字段，10 位学号超 5 年已平稳回退学年学期标签。

---

## 五、CI 门禁与本机一键验证命令

- **CI 触发策略（[`.github/workflows/build-release.yml`](.github/workflows/build-release.yml)）**：修改任何 `**.md` 均不触发 CI；源码/测试/平台工程变更触发 `test` + `build-android` + `build-windows` 三路并行（`test` 失败即 `fail-fast` 取消打包）；推送 `v*` 标签且全绿时自动校验 Tag 与 `pubspec.yaml` 版本一致并发布 Release。
- **本机运行提示**：若代理导致 `flutter_tester` WebSocket 报 `502`，先清空 `$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'`；Windows 全量测试建议 `-j 2 --timeout 30s`。

```powershell
# 1. L0: 格式与静态分析（主工程 + zf_academic 协议子包）
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos lib test
cd packages/zf_academic
dart format --output=none --set-exit-if-changed lib test
dart analyze lib test

# 2. L1: zf_academic 纯 Dart 协议单测
dart test
cd ../..

# 3. L1 + L2 + L3: 主工程全量单测、组件与性能契约测试
flutter test -j 2 --timeout 30s

# 4. Android 原生清单与 Kotlin 编译校验（修改 android/ 后必跑）
.\android\gradlew.bat -p android :app:processDebugManifest :app:compileDebugKotlin

# 5. 检查仓库洁净度
git status -s
```
