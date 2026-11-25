# 青科课表通 (`qustschedule`) · AI 主入口 (`AGENTS.md`)

> `com.fangzi.qustschedule` · GPL-3.0 · Flutter (Android + Windows) · 独立自包含

## 核心开发纪律
1. **Doc-First**：先按 §1 路由表查对应 `docs/dev/*.md`，再精准读源码；禁盲目全库扫描。
2. **Doc-Sync**：增删改代码/契约/路径时，同次任务更新对应唯一真源并清理过时符号。
3. **冲突裁决**：文档与源码冲突时以源码为准，并同步修文档。
4. **文档编写与维护规范**：
   - **易定位**：优先用表格、短句与清晰小标题，保留精确路径、符号名、常量、契约与坑点，一条事实占一行/一格，不写大段散文。
   - **易增删**：同一信息只在唯一真源写一次，不跨文档重复，增删改只动一处。
   - **去噪音**：禁写背景叙事、过渡句、客套括号免责、重复提醒及看文件名/代码一眼可知的常识；不得删减真实技术契约与边界条件。
5. **变更门禁**：`git commit`、`git push`、打 Tag、发版等提交/同步操作仅在用户明确要求时执行，禁自行判断或按习惯执行。

---

## 一、任务路由与单一真源总表

> 增删改任意文件路径同步 [`docs/dev/FILE_MAP.md`](docs/dev/FILE_MAP.md)。

| 任务域 | 核心目标文件 | 关键机制 / 通知源 | 唯一真源 |
|---|---|---|---|
| 文件与符号定位 | 全仓库源码与测试 | 路径与导出符号总目录 | [`docs/dev/FILE_MAP.md`](docs/dev/FILE_MAP.md) |
| 登录 / 重登 / 验证码 / 改密 / 切校 | `lib/src/schedule_service.dart`, `lib/src/state/auth_session_controller.dart`, `lib/src/app_model.dart`, `lib/pages/{login,captcha}_page.dart` | `routeNotifier`, `_authEpoch`, `_reloginFlight`, 10m×2 熔断 | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1–§3 |
| 正方协议 / RSA / Cookie | `packages/zf_academic/lib/src/*.dart` | 纯 Dart 零 Flutter 依赖，23 项 `ErrorCode` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §8 |
| 线路 / 学期 / 校历 / 周次 | `lib/src/{school,term_selector_helper,term_calendar}.dart`, `lib/src/state/schedule_controller.dart`, `lib/pages/school_address_page.dart` | `ScheduleController`, `weekNotifier`, `DateTime.utc` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §3.4–§4.2 |
| `Preferences` Schema 15 / 存储 | `lib/src/preferences_repository.dart`, `lib/src/state/preferences_controller.dart`, `lib/src/safe_json_file.dart` | `prefsNotifier`, `SafeJsonFile` (`.tmp`/`.bak`/`>=16KB` Isolate) | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §5 |
| 自动更新 / 代理 / Windows 壳 | `lib/src/updater/*.dart`, `lib/pages/{update_dialog,update_proxy_page}.dart`, `android/.../updater/AppUpdaterBridge.kt`, `windows/runner/*` | `UpdateFlowController`, `.update_staging`, VBS + `robocopy /mir` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §6–§7 |
| 课表网格 / 排版 / 冲突 / 调课 | `lib/pages/{schedule,reschedule}_page.dart`, `lib/widgets/{course_tile,week_pager,course_detail_sheet}.dart`, `lib/src/reschedule.dart` | `ScheduleController` (`_dataRevision`), `weekNotifier`, `letterSpacing: 0` + `1e-4` | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.4–§4.5 |
| 学业页（考试 / GPA / 未评教） | `lib/pages/academic_page.dart`, `lib/src/state/academic_controller.dart`, `lib/src/academic_{service,cache}.dart` | `academicNotifier`, `_academicLoadSeq`, `loadedAcademicTerm` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1.4 & §3.2 · [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §5 |
| 三页外壳 / Dock / 顶栏 / 菜单 | `lib/pages/home_shell.dart`, `lib/widgets/{floating_dock,tactile_button,app_menu}.dart`, `lib/theme/app_theme.dart` | 单运动源 `ValueNotifier<double>`、`TactileAppBar` 四层、`AppMenuScope` | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.1–§4.3 |
| 二级页转场 / 骨架屏 / 气泡 | `lib/src/route_settled.dart`, `lib/widgets/{page_skeleton,status_popup,app_snack_bar}.dart`, `lib/src/state/hint_notice_controller.dart` | `RouteSettledStateMixin`, `runInBackground`, `hints` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §4.4 · [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §3.5 & §4.6 |
| Android 课前提醒 / 流体云 | `lib/src/reminder_*.dart`, `lib/pages/{reminder,settings}_page.dart`, `android/.../reminder/*.kt` (13) | `ReminderService`, `ReminderWorker`, ID `2000`/`2001`/`2003` | [`docs/dev/REMINDER.md`](docs/dev/REMINDER.md) |
| Android 桌面小组件 / 预览 | `lib/src/widget_*.dart`, `lib/pages/widget_settings_page.dart`, `lib/widgets/desktop_widget_preview.dart`, `android/.../widget/*.kt` (15) | `DesktopWidgetService`, `WidgetWorker`, `RenderMode.surface` | [`docs/dev/WIDGET.md`](docs/dev/WIDGET.md) |
| 测试矩阵 / 替身 / CI | `test/*_test.dart`, `test/support/fake_*.dart`, `packages/zf_academic/test/*_test.dart`, `.github/workflows/build-release.yml` | L0–L3 分层门禁 | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §6 |

---

## 二、工程红线 vs 当前业务现状

### 工程红线
- **版本号**：唯一真源 [`pubspec.yaml`](pubspec.yaml) `version:`（运行时 [`lib/src/app_version.dart`](lib/src/app_version.dart) 异步读），禁硬编码。
- **格式与洁净**：`dart format`（≤ 80 列）；结束前确认 `git status` 洁净。
- **分层边界**：`pages/widgets → AppModel(5 Controllers) → Services → zf_academic & Repositories`；UI 禁直调 Service/Cache/Client；[`packages/zf_academic`](packages/zf_academic/) 零 Flutter 依赖。
- **Windows**：[`windows/runner/`](windows/runner/) `.cpp`/`.h` **禁中文注释/字面量**（MSVC `C4819`，用 `\uXXXX`）；`Runner.rc` 保持 `UTF-16LE + BOM`；产物名 `qustschedule.exe`（绑定 DPAPI / `Local\com.fangzi.qustschedule.SingleInstance`）。
- **Android**：Flutter 3.29+ 主线程已合并，MethodChannel 与 `BroadcastReceiver` **禁主线程 IO/闹钟/画 Bitmap**（走 `ReminderWorker`/`WidgetWorker` + `goAsync()`）；`minSdk 24`（`widget/` 禁 `java.time.*`，用 `Calendar`）；`debug`/`release` 签名分离；`useLegacyPackaging = true`；`allowBackup="false"`；`android/keystore/` 与 `android/key.properties` 禁入库。

### 当前业务现状
- 青科大默认外网线路 `https://jwglxt.qust.edu.cn/jwglxt`（支持自定义）；两学期制（秋 `3` / 春 `12`，历史 `'16'` 收敛）；GPA 文案「学期平均学分绩点 (GPA)」；10 位学号 `2000 + YY` 推导入学年（超 5 年回退学年学期标签）。
- 协议与防锁号常量（RFC 6265 属性、PNG 魔数、10 分钟 2 次重登熔断、10s 超时、默认 18 周保底）为正常设计常量，勿当冗余硬编码误删。

---

## 三、跨模块高频防坑

| 场景 | 避免 | 正确做法 | 守护测试 |
|---|---|---|---|
| 状态订阅 | `ListenableBuilder(listenable: model)` 整页包裹或高频调根 `notifyListeners()` | 细粒度订阅 `routeNotifier`/`scheduleState`/`weekNotifier`/`refreshingNotifier`/`academicNotifier`/`prefsNotifier`/`hints`/`updateFlow` | `test/rebuild_scope_test.dart` |
| 课程块预排版 | 裸 `TextStyle` 喂 `TextPainter`、漏 `letterSpacing: 0` 或 `>0.5px` 容差 | `DefaultTextStyle.of(context).style.merge(...)` + `MediaQuery.boldTextOf(context)` + `letterSpacing: 0` + `1e-4` | `test/widget_test.dart` |
| 三页与菜单 | `PageView` 做底栏、`TactileSurfaceScope` 套 `Opacity`、菜单脱离页坐标 | `FloatingDock` 单运动源驱动 `_ShellPager`；`TactileAppBar` 四层合绘；页内包 `AppMenuScope` | `test/dock_transition_test.dart` |
| 转场与选字 | 260ms 转场中途 `setState` 挂重子树；用 `SelectableText` 或多棵 `SelectionArea` | `initState` 并行 `runInBackground` + `RouteSettledStateMixin` 骨架；页级单层 `SelectionArea` + `Text` | `test/page_transition_test.dart` |
| Cookie 免登 | `sessionInfo?.username ?? accountHint`（`''` 不触发 `??`） | 按 `isNotEmpty` 顺序回退：`username` → `accountHint` → `studentId` → `prefs.accountOf` | `test/schedule_service_test.dart` |
| 跨学期考试 | 切他学期仍拼当前学期周次或混入小组件 | 仅 `loadedAcademicTerm == model.termId` 时拼周次与注入小组件 | `test/academic_page_test.dart`, `test/widget_service_test.dart` |
| 防连点与延时 | `onPressed = null` 闪灰；滑块 `onChanged` 写盘；裸 `Future.delayed` | 非 State `bool _running`；滑块 `onChanged` 改草稿、`onChangeEnd` 落盘；可取消 `Timer` + `dispose()` 清理 | `test/widget_settings_page_test.dart` |
| 测试去重 | 仅因相似删已有测试 | 删固定测试前确认：同被测对象 + 同断言集 + 同 L1/L2/L3 层级 + 无独占失败模式 | 全量 `test/*_test.dart` |

---

## 四、CI 与一键验证命令

- **CI（[`.github/workflows/build-release.yml`](.github/workflows/build-release.yml)）**：改 `**.md` 不触发；代码变更触发 `test` + `build-android` + `build-windows` 并行（`test` 失败即 `fail-fast` 取消打包）；`v*` 标签全绿校验版本号一致后发 Release。
- **代理 502 处理**：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'`。

```powershell
# L0: 格式与静态分析
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos lib test
cd packages/zf_academic; dart format --output=none --set-exit-if-changed lib test; dart analyze lib test

# L1: 协议包单测
dart test; cd ../..

# L1–L3: 主工程全量测试
flutter test -j 2 --timeout 30s

# Android 校验（改 android/ 后必跑）
.\android\gradlew.bat -p android :app:processDebugManifest :app:compileDebugKotlin

# 仓库洁净检查
git status -s
```
