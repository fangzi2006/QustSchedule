# 青科课表通 (`qustschedule`) · AI 开发主入口 (`AGENTS.md`)

> **定位**：本仓库（`com.fangzi.qustschedule`，GPL-3.0，Flutter Android + Windows 客户端）独立自包含的 AI 协作主入口与路由枢纽。单独 `git clone` 即可开箱使用，零外部路径依赖。

## 核心开发纪律（必须严格遵守）

1. **先查文档再翻代码（Doc-First）**：接到任何开发、重构或排障任务，**必须先按下方 §一 路由表定位并查阅对应 `docs/dev/*.md` 专题**，再精准打开目标源码，严禁盲目全库遍历浪费上下文。
2. **改码必同步更新文档（Doc-Sync）**：新增、删除或修改源码、架构契约、状态流转或测试时，**必须在同次任务中同步更新下表指定的唯一真源文档**，并清理已删除/重命名的过时符号。
3. **冲突以代码为准并修文档**：当文档描述与现行源码不一致时，一律以现行源码为准，并顺手修正对应专题文档，保持 1:1 同步。

---

## 一、任务路由与文档单一真源总表（查完即路由，改完即同步）

> **单一真源原则**：每类信息只在 `docs/dev/` 中的**唯一一份文档**维护；新增/删改任意源码或测试文件路径时，统一同步 [`docs/dev/FILE_MAP.md`](docs/dev/FILE_MAP.md)。

| 开发 / 排障场景 | 核心目标文件 | 关键机制 / 通知源 | 必读 & 改后必同步的唯一真源 |
|---|---|---|---|
| **定位文件 / 导出符号 / 增删文件** | 全仓库 `lib/`、`packages/`、`android/`、`windows/`、`test/` | 文件路径与导出符号总目录 | [`docs/dev/FILE_MAP.md`](docs/dev/FILE_MAP.md) |
| **登录 / 自动重登 / 验证码 / 改密 / 切校** | `lib/src/schedule_service.dart`, `lib/src/state/auth_session_controller.dart`, `lib/src/app_model.dart`, `lib/pages/{login,captcha}_page.dart` | `routeNotifier`, `_authEpoch`, `_reloginFlight`, 10 分钟 2 次熔断 | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1–§3 |
| **正方教务协议 / RSA / Cookie 隔离** | `packages/zf_academic/lib/src/*.dart` | 纯 Dart 零 Flutter 依赖，23 项 `ErrorCode` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §8 |
| **教务线路 / 学期推导 / 校历 / 周次校准** | `lib/src/{school,term_selector_helper,term_calendar}.dart`, `lib/src/state/schedule_controller.dart`, `lib/pages/school_address_page.dart` | `ScheduleController`, `weekNotifier`, `DateTime.utc` 整日差 | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §3.4–§4.2 |
| **`Preferences` Schema 15 / 持久化读写** | `lib/src/preferences_repository.dart`, `lib/src/state/preferences_controller.dart`, `lib/src/safe_json_file.dart` | `prefsNotifier`, `SafeJsonFile` (`.tmp`/`.bak`/`>=16KB` Isolate) | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §5 |
| **自动更新 / 代理测速 / Windows 壳与热替换** | `lib/src/updater/*.dart`, `lib/pages/{update_dialog,update_proxy_page}.dart`, `android/.../updater/AppUpdaterBridge.kt`, `windows/runner/*` | `UpdateFlowController`, `.update_staging`, VBS + `robocopy /mir` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §6–§7 |
| **课表网格 / 课程卡片排版 / 冲突 / 调课** | `lib/pages/{schedule,reschedule}_page.dart`, `lib/widgets/{course_tile,week_pager,course_detail_sheet}.dart`, `lib/src/reschedule.dart` | `ScheduleController` (`_dataRevision`), `weekNotifier`, `letterSpacing: 0` + `1e-4` | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.4–§4.5 |
| **学业页（考试倒计时 / GPA / 未评教）** | `lib/pages/academic_page.dart`, `lib/src/state/academic_controller.dart`, `lib/src/academic_{service,cache}.dart` | `academicNotifier`, `_academicLoadSeq`, `loadedAcademicTerm` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1.4 & §3.2 · [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §5 |
| **三页外壳切页 / Dock 动效 / 顶栏与菜单** | `lib/pages/home_shell.dart`, `lib/widgets/{floating_dock,tactile_button,app_menu}.dart`, `lib/theme/app_theme.dart` | 单运动源 `ValueNotifier<double>`、`TactileAppBar` 四层合绘、`AppMenuScope` | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.1–§4.3 |
| **二级页 260ms 转场 / 骨架屏 / 气泡提示** | `lib/src/route_settled.dart`, `lib/widgets/{page_skeleton,status_popup,app_snack_bar}.dart`, `lib/src/state/hint_notice_controller.dart` | `RouteSettledStateMixin`, `runInBackground`, `hints` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §4.4 · [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §3.5 & §4.6 |
| **Android 课前提醒 / 流体云 / 权限诊断** | `lib/src/reminder_*.dart`, `lib/pages/{reminder,settings}_page.dart`, `android/.../reminder/*.kt`（13 文件） | `ReminderService` (300ms 防抖+单飞), `ReminderWorker`, ID `2000`/`2001`/`2003` | [`docs/dev/REMINDER.md`](docs/dev/REMINDER.md) |
| **Android 桌面小组件 / 样式预设 / 预览** | `lib/src/widget_*.dart`, `lib/pages/widget_settings_page.dart`, `lib/widgets/desktop_widget_preview.dart`, `android/.../widget/*.kt`（15 文件） | `DesktopWidgetService`, `WidgetWorker`, `MainActivity` `RenderMode.texture` | [`docs/dev/WIDGET.md`](docs/dev/WIDGET.md) |
| **测试套件 / 测试替身 / CI 流水线** | `test/*_test.dart`, `test/support/fake_*.dart`, `packages/zf_academic/test/*_test.dart`, `.github/workflows/build-release.yml` | L0–L3 分层门禁、4 项测试去重铁律 | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §6 |

---

## 二、工程硬性约束（违背会导致编译失败、崩溃、安全漏洞或数据损坏）

1. **版本号唯一真源**：不在源码、文档或测试断言中硬编码版本号；唯一真源为 [`pubspec.yaml`](pubspec.yaml) 的 `version:`（运行时由 [`lib/src/app_version.dart`](lib/src/app_version.dart) 异步读取）。
2. **代码格式与仓库洁净**：Dart 代码遵循 `dart format`（单行 ≤ 80 列）；任务结束前确认 `git status` 无遗留临时文件。
3. **单向分层依赖**：`lib/pages/ & lib/widgets/ → AppModel (及 5 大 State Controller) → ScheduleService / AcademicService / ReminderService / DesktopWidgetService → packages/zf_academic & Repositories`。UI 层不直调 Service/Cache/Repository/`ZhengfangClient`；[`packages/zf_academic`](packages/zf_academic/) 为**零 Flutter 依赖**纯 Dart 包。
4. **平台与安全红线**：
   - **Windows**：[`windows/runner/`](windows/runner/) 下 `.cpp`/`.h` **严禁出现中文注释或中文字符字面量**（MSVC CP936 会报 `C4819` 编译错误，UI 文案用 `\uXXXX` 转义）；`Runner.rc` 保持 `UTF-16LE + BOM`；产物名保持 `qustschedule.exe`（绑定 DPAPI、AppData 与单实例互斥锁 `Local\com.fangzi.qustschedule.SingleInstance`）。
   - **Android**：Flutter 3.29+ 已合并 UI 与 Platform 主线程，MethodChannel 与 `BroadcastReceiver` **严禁在主线程读盘、设闹钟或画 Bitmap**（一律走 `ReminderWorker` / `WidgetWorker` 单线程 + `goAsync()`）；`minSdk = 24`（`widget/` 禁用 `java.time.*`，用 `Calendar`）；`debug`/`release` 签名分离；`useLegacyPackaging = true`；`android:allowBackup="false"`（防换机恢复无法解密的 Keystore 密文）；`android/keystore/` 与 `android/key.properties` 严禁入库。

> **当前产品与业务现状说明（非硬性限制，后续需求变更时可按需修改并同步文档与测试）**：
> - 当前主要面向青岛科技大学：默认内置 1 条青科大外网教务线路 `https://jwglxt.qust.edu.cn/jwglxt`（仍支持自定义地址）；当前采用两学期制（秋 `3` / 春 `12`，历史 `'16'` 收敛不外显）；GPA 卡片当前文案为「学期平均学分绩点 (GPA)」；10 位学号当前按 `2000 + YY` 推导入学年（超 5 年回退学年学期标签）。
> - 当前有意保留的协议与防锁号常量（RFC 6265 属性、PNG 魔数、10 分钟 2 次重登熔断、10s 超时、默认 18 周保底等）属于正常设计常量，日常清理代码时勿误删，确有需求时可按需调整。

---

## 三、跨模块高频防坑清单（Do / Don't）

| 场景 | 严禁写法 (Don't) | 正确契约 (Do) | 守护测试 |
|---|---|---|---|
| **局部状态监听** | `ListenableBuilder(listenable: model)` 包裹整页，或在翻周/刷新/气泡时调根 `notifyListeners()` | 精确订阅 `routeNotifier`、`scheduleState`、`weekNotifier`、`refreshingNotifier`、`academicNotifier`、`prefsNotifier`、`hints`、`updateFlow` | `test/rebuild_scope_test.dart` |
| **课程卡片预排版** | 裸 `TextStyle` 喂给 `TextPainter`，漏 `letterSpacing: 0` 或留 `> 0.5px` 容差 | `DefaultTextStyle.of(context).style.merge(...)` + `MediaQuery.boldTextOf(context)` + `letterSpacing: 0` + `1e-4` 容差 | `test/widget_test.dart` |
| **三页外壳与顶栏菜单** | 用 `PageView` 做底栏三页、`TactileSurfaceScope` 内套 `Opacity`、菜单脱离页面坐标系 | `FloatingDock` 单运动源驱动 `_ShellPager`；`TactileAppBar` 四层合绘；页面与转场内包裹 `AppMenuScope` | `test/dock_transition_test.dart` |
| **二级页转场与选字** | 转场中途 `setState` 挂载重子树；使用重型 `SelectableText` 或多棵 `SelectionArea` | `initState` 并行 `runInBackground` + `RouteSettledStateMixin` 骨架占位；页面级**单层 `SelectionArea` + `Text`** | `test/page_transition_test.dart` |
| **Cookie 免登空串陷阱** | `sessionInfo?.username ?? accountHint`（`''` 不会被 `??` 跳过） | 按 `isNotEmpty` 顺序回退：`username` → `accountHint` → `studentId` → `prefs.accountOf` | `test/schedule_service_test.dart` |
| **跨学期考试隔离** | 切看其他学期考试时仍拼接当前学期周次，或混入桌面小组件 | 仅 `loadedAcademicTerm == model.termId` 时追加周次标签与注入小组件快照 | `test/academic_page_test.dart`, `test/widget_service_test.dart` |
| **异步按钮与定时器** | 按钮 `onPressed` 置 `null` 引起闪烁；滑块 `onChanged` 每帧写盘；裸写不可取消 `Future.delayed` | 用非 State `bool _running` 防重入；滑块 `onChanged` 改草稿、`onChangeEnd` 落盘；所有延时用可取消 `Timer` 并在 `dispose()` 清理 | `test/widget_settings_page_test.dart` |
| **测试用例去重** | 仅因场景相似就删减已有固定测试 | 删除固定测试前建议确认：同被测对象 + 同断言集 + 同 L1/L2/L3 层级 + 不独占任何失败模式 | 全量 `test/*_test.dart` |

---

## 四、CI 门禁与本机一键验证命令

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
