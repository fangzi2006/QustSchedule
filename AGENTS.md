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
| 登录 / 重登 / 验证码 / 改密 / 切校 | `lib/src/schedule_service.dart`, `lib/src/state/auth_session_controller.dart`, `lib/src/app_model.dart`, `lib/pages/login_page.dart`, `lib/pages/captcha_page.dart` | `routeNotifier`, `_authEpoch`, `_reloginFlight`, `_sessionVersion`, `buildAccountKey`, 10m×3 白名单熔断 | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1–§3 |
| 正方协议 / RSA / Cookie | `packages/zf_academic/lib/zf_academic.dart`, `packages/zf_academic/lib/zf_academic_io.dart`, `packages/zf_academic/lib/src/*.dart` | 纯 Dart 零 Flutter 依赖，43 公开符号桶，23 项 `ErrorCode` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §8 |
| 线路 / 学期 / 校历 / 周次 | `lib/src/school.dart`, `lib/src/term_selector_helper.dart`, `lib/src/term_calendar.dart`, `lib/src/state/schedule_controller.dart`, `lib/pages/school_address_page.dart`, `lib/widgets/calibrate_sheet.dart` | `ScheduleController`, `weekNotifier`, `DateTime.utc`, `defaultAcademicPaceHosts` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §3.4–§4.2 |
| `Preferences` Schema 15 / 存储 | `lib/src/preferences_repository.dart`, `lib/src/state/preferences_controller.dart`, `lib/src/safe_json_file.dart` | `prefsNotifier`, `SafeJsonFile` (`.tmp`/`.bak`/`>=16KB` Isolate) | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §5 |
| 自动更新 / 代理 / Windows 壳 | `lib/src/updater/*.dart` (`updater_gateway.dart`), `lib/pages/update_dialog.dart`, `lib/pages/update_proxy_page.dart`, `android/.../updater/AppUpdaterBridge.kt`, `windows/runner/*` | `UpdateFlowController`, `UpdaterGateway`, `.update_staging`, VBS + `robocopy /mir` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §6–§7 |
| 课表网格 / 排版 / 冲突 / 调课 | `lib/pages/schedule_page.dart`, `lib/pages/reschedule_page.dart`, `lib/widgets/course_tile.dart`, `lib/widgets/week_pager.dart`, `lib/widgets/course_detail_sheet.dart`, `lib/src/reschedule.dart` | `ScheduleController` (`_dataRevision`), `weekNotifier`, `letterSpacing: 0` + `1e-4` | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §4.4–§4.5 |
| 学业页（考试 / GPA / 未评教） | `lib/pages/academic_page.dart`, `lib/src/state/academic_controller.dart`, `lib/src/academic_service.dart`, `lib/src/academic_cache.dart` | `academicNotifier`, `_academicLoadSeq`, `loadedAcademicTerm` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §1.4 & §3.2 · [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §5 |
| 三页外壳 / Dock / 顶栏 / 菜单 / 转场 | `lib/pages/home_shell.dart`, `lib/widgets/floating_dock.dart`, `lib/widgets/tactile_button.dart`, `lib/widgets/app_menu.dart`, `lib/theme/app_theme.dart` | 单运动源 `ValueNotifier<double>`、`TactileAppBar` 四层、`routeWrapper` 注入 `AppMenuScope` | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §3.4 & §4.1–§4.3 |
| 二级页转场 / 骨架屏 / 气泡 | `lib/src/route_settled.dart`, `lib/widgets/page_skeleton.dart`, `lib/widgets/status_popup.dart`, `lib/widgets/app_snack_bar.dart`, `lib/src/state/hint_notice_controller.dart` | `RouteSettledStateMixin`, `runInBackground`, `hints` | [`docs/dev/CORE_AND_STATE.md`](docs/dev/CORE_AND_STATE.md) §4.4 · [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §3.5 & §4.6 |
| Android 课前提醒 / 流体云 | `lib/src/reminder_*.dart`, `lib/pages/reminder_page.dart`, `lib/pages/settings_page.dart`, `android/.../reminder/*.kt` (13) | `ReminderService`, `ReminderWorker`, ID `2000`/`2001`/`2003` | [`docs/dev/REMINDER.md`](docs/dev/REMINDER.md) |
| Android 桌面小组件 / 预览 | `lib/src/widget_*.dart`, `lib/pages/widget_settings_page.dart`, `lib/widgets/desktop_widget_preview.dart`, `android/.../widget/*.kt` (15) | `DesktopWidgetService`, `WidgetWorker`, `RenderMode.surface` | [`docs/dev/WIDGET.md`](docs/dev/WIDGET.md) |
| 测试矩阵 / 替身 / 架构守卫 / CI | `test/*_test.dart`, `test/architecture_guard_test.dart`, `test/support/*.dart`, `tool/verify.dart`, `packages/zf_academic/test/*_test.dart`, `.github/workflows/build-release.yml` | L0–L3 分层门禁、统一验证入口与静态架构守卫 | [`docs/dev/UI_AND_TESTING.md`](docs/dev/UI_AND_TESTING.md) §6 |

---

## 二、工程红线 vs 当前业务现状

### 工程红线
- **版本号**：唯一真源 [`pubspec.yaml`](pubspec.yaml) `version:`（运行时 [`lib/src/app_version.dart`](lib/src/app_version.dart) 异步读），禁硬编码。
- **格式与静态分析**：`dart format`（≤ 80 列）；遵循 [`analysis_options.yaml`](analysis_options.yaml) 严格模式（`strict-casts`/`strict-inference`/`strict-raw-types` 与 7 条 lint：`always_declare_return_types`、`cancel_subscriptions`、`close_sinks`、`depend_on_referenced_packages`、`directives_ordering`、`prefer_final_locals`、`unawaited_futures`，其中 4 项为 `warning`），禁新增 `// ignore:`；结束前确认 `git status` 洁净。
- **分层与封装（Import DAG）**：
  - [`packages/zf_academic/lib/zf_academic.dart`](packages/zf_academic/lib/zf_academic.dart) 零 Flutter/`dart:io` 依赖，仅导出 8 个 `src/` 模块的 43 项公开符号（禁暴露 `Page`、内部 HTML/RSA/HTTP 辅助函数）；`dart:io`/`dart:isolate` 限 `cookie_storage.dart`/`dart_io_transport.dart`/`zf_academic_io.dart`；站点降频表 `defaultAcademicPaceHosts` 归 [`lib/src/school.dart`](lib/src/school.dart) 注入。
  - `lib/src/**` 禁引 `theme/`、`widgets/`、`pages/`、`dart:ui`、`material.dart`、`cupertino.dart`；13 个纯 Dart 领域/规划模块 + `academic_service.dart` 零 `package:flutter/*` 与 `dart:ui`。
  - `lib/theme/**` 禁引 `widgets/`、`pages/`、`dart:io`、service/repository/cache。
  - `lib/widgets/**` 禁引 `pages/`、`*_repository.dart`、`*_cache.dart`、`*_gateway.dart`、service/installer/`zf_academic_io.dart`/`dart:io`/`MethodChannel`。
  - `lib/pages/**` 禁引 `dart:io`、`zf_academic_io.dart`、`*_cache.dart`、`credentials_repository.dart`、`session_repository.dart`、`schedule_service.dart`、`update_service.dart`、`app_installer.dart`、`updater_gateway.dart`、`MethodChannel`；同级 `pages/` 路由依赖严格有向无环（三 Tab 页互不引用亦不引 `home_shell.dart`，非外壳页不引 `home_shell.dart`，叶页零同级引用）；`pages/` 与 `widgets/` 禁直接实例化 `*Service(` / `MethodChannel*(`。
  - `MethodChannel` 仅限 [`reminder_gateway.dart`](lib/src/reminder_gateway.dart)、[`widget_gateway.dart`](lib/src/widget_gateway.dart)、[`app_installer.dart`](lib/src/updater/app_installer.dart)、[`updater_gateway.dart`](lib/src/updater/updater_gateway.dart)；测试替身网关实现集中于 `test/support/fake_*.dart`（业务测试禁直接 `implements *Gateway`）。
  - **`AppModel` 薄透传冻结**：[`lib/src/app_model.dart`](lib/src/app_model.dart) 仅保留跨控制器协调逻辑与既有兼容转发（上限冻结 `<= 134`）；新增状态或动作**禁再向 `AppModel` 新增 1:1 透传**，新页面直接读取/订阅 `model.prefs` / `session` / `scheduleState` / `academic` / `hints` / `updateFlow`。
- **换行与编码（`.gitattributes` + Windows）**：[`.gitattributes`](.gitattributes) 统一跨平台换行（Dart/Kotlin/YAML/MD/JSON `lf`；`.cpp`/`.h`/`.rc`/`.iss`/`.bat`/`.ps1` `crlf`）；[`windows/runner/`](windows/runner/) `.cpp`/`.h` **纯 ASCII（禁中文注释/字面量，防 MSVC `C4819`，用 `\uXXXX`）**；`Runner.rc` 保持 **无 BOM UTF-8 + `#pragma code_page(65001)`**；`setup.iss` 保持 **UTF-8 + BOM**；产物名 `qustschedule.exe`（绑定 DPAPI / `Local\com.fangzi.qustschedule.SingleInstance`）。
- **Android & 原生通道**：三条 MethodChannel（`qustschedule/reminder`、`qustschedule/widget`、`com.fangzi.qustschedule/updater`）两端契约 1:1 对齐；Flutter 3.29+ 主线程已合并，MethodChannel 与 `BroadcastReceiver` 重 I/O/闹钟/Bitmap/APK 校验统一派发单线程 Worker（`ReminderWorker`/`WidgetWorker`/`UpdaterWorker`）+ `postReply`（`@Volatile disposed`）或 `goAsync()`；`ReminderScheduler.MIN_EVENT_REQUEST_CODE = 10_000`；`minSdk 24`（`widget/` 禁 `java.time.*`，用 `Calendar`）；`android/gradle.properties` 保持 `android.newDsl=false` 与 `android.builtInKotlin=false`（随 Flutter `3.47.7` 锁 `org.jetbrains.kotlin.android`）；`debug`/`release` 签名分离；`useLegacyPackaging = true`；`allowBackup="false"`；`android/keystore/` 与 `android/key.properties` 禁入库。

### 当前业务现状
- 青科大默认外网线路 `https://jwglxt.qust.edu.cn/jwglxt`（支持自定义）；两学期制（秋 `3` / 春 `12`，历史 `'16'` 收敛）；GPA 文案「学期平均学分绩点 (GPA)」；10 位学号 `2000 + YY` 推导入学年（超 5 年回退学年学期标签）。
- 协议与防锁号常量（RFC 6265 属性、PNG 魔数、10 分钟 3 次白名单重登熔断、10s 超时、默认 18 周保底）为正常设计常量，勿当冗余硬编码误删。

---

## 三、跨模块高频防坑

| 场景 / 触发改动 | 避免 | 正确做法 | 守护测试 / CI |
|---|---|---|---|
| 改分层引用 / 新增导出或文件 / 删改路径 | 跨层 import、`pages/` 互引、自造 `implements *Gateway`、漏更 `FILE_MAP.md` | 遵守 §2 Import DAG；共享弹窗放 `widgets/`；测试继承 `test/support/fake_*.dart`；同步 `docs/dev/FILE_MAP.md` | `test/architecture_guard_test.dart` |
| 改 Windows C++ 壳 / `Runner.rc` / `setup.iss` | `.cpp`/`.h` 写非 ASCII；`Runner.rc` 存成 UTF-16LE 或加 BOM；`setup.iss` 去 BOM | `.cpp`/`.h` 纯 ASCII（中文用 `\uXXXX`）；`Runner.rc` 无 BOM UTF-8 + `#pragma code_page(65001)`；`setup.iss` UTF-8 + BOM | `test/architecture_guard_test.dart`, CI `Lint: Windows encoding & C4819 guard` |
| 改凭据键 / 学校 URL 规范化 / 自动重登 | 遗漏 `baseUrl.toLowerCase()`、末尾 `/` 或 `http↔https` 回退 | 统一经 `buildAccountKey()`（`school.dart`）与 `ScheduleService._fallbackAccountKeys()` 读写删凭据 | `test/credentials_repository_test.dart`, `test/schedule_service_test.dart` |
| 改更新下载 / 安装状态机 (`UpdateFlowController`) | 弹窗/页面直调 `UpdateService()` 或 `MethodChannel`；忽略跨取消/重下 epoch | 经 `UpdaterGateway` 注入；`startDownload()` 拦截 `_isTriggeringInstall`；`executeInstall()` 校验 `epoch == _downloadEpoch && !_disposed` | `test/updater_test.dart`, `test/architecture_guard_test.dart` |
| 改小组件色板 / 样式边界 / 本周预览或布局 | Dart 与 Kotlin 色板/范围/行高/行数上限不一致 | 同步 `stable_hash.dart`/`course_palette.dart`/`widget_style.dart`/`desktop_widget_preview.dart` ↔ `WidgetThemeResolver.kt`/`WidgetStore.kt`/`WeekGridRemoteViewsBuilder.kt` | `test/architecture_guard_test.dart`, `test/widget_settings_page_test.dart` |
| 改 Android MethodChannel / Bridge / 提醒排程 | 主线程校验 APK 或漏 `!disposed` 回调；`requestCode` 占 `0..9999`；`ReminderService` 漏监听 `prefsNotifier` | 重操作走 `*Worker` + `postReply`；`MIN_EVENT_REQUEST_CODE = 10_000`；`cancelAll()` 先等 `_syncInFlight`；同步网关与 Kotlin | `test/architecture_guard_test.dart`, `test/reminder_service_test.dart`, CI `verify-android` |
| 状态订阅 | `ListenableBuilder(listenable: model)` 整页包裹或高频调根 `notifyListeners()` | 细粒度订阅 `routeNotifier`/`hints`/`scheduleState`/`weekNotifier`/`refreshingNotifier`/`academicNotifier`/`prefsNotifier`/`updateFlow` | `test/rebuild_scope_test.dart` |
| 课程块预排版 | 裸 `TextStyle` 喂 `TextPainter`、漏 `letterSpacing: 0` 或 `>0.5px` 容差 | `DefaultTextStyle.of(context).style.merge(...)` + `MediaQuery.boldTextOf(context)` + `letterSpacing: 0` + `1e-4` | `test/schedule_grid_widget_test.dart` |
| 升级 Flutter SDK / AGP / 安全存储插件 | 只改 CI 版本号或 `pubspec.yaml`，遗留过时 Gradle 标志或让 `example` 漂移 | 同步 `build-release.yml` `FLUTTER_VERSION` 与 `AGENTS.md`；复查 `android/gradle.properties`（`android.newDsl=false`/`android.builtInKotlin=false`）；核对 `packages/zf_academic/example/secure_storage_flutter.dart` 与 `credentials_repository.dart` 并跑 `dart run tool/verify.dart --full --android` | `test/architecture_guard_test.dart`, CI `verify-android` |
| 三页与菜单 | `PageView` 做底栏、`TactileSurfaceScope` 套 `Opacity`、菜单脱离页坐标 | `FloatingDock` 单运动源驱动 `_ShellPager`；`TactileAppBar` 四层合绘；`routeWrapper` + 页级 `AppMenuScope` | `test/dock_transition_test.dart` |
| 转场与选字 | 260ms 转场中途 `setState` 挂重子树；用 `SelectableText` 或多棵 `SelectionArea` | `initState` 并行 `runInBackground` + `RouteSettledStateMixin` 骨架；页级单层 `SelectionArea` + `Text` | `test/page_transition_test.dart` |
| Cookie 免登 | `sessionInfo?.username ?? accountHint`（`''` 不触发 `??`） | 按 `isNotEmpty` 顺序回退：`username` → `accountHint` → `studentId` → `prefs.accountOf` | `test/schedule_service_test.dart` |
| 跨学期考试 | 切他学期仍拼当前学期周次或混入小组件 | 仅 `loadedAcademicTerm == model.termId` 时拼周次与注入小组件 | `test/academic_page_test.dart`, `test/widget_service_test.dart` |
| 防连点与延时 | `onPressed = null` 闪灰；滑块 `onChanged` 写盘；裸 `Future.delayed` | 非 State `bool _running`；滑块 `onChanged` 改草稿、`onChangeEnd` 落盘；可取消 `Timer` + `dispose()` 清理 | `test/widget_settings_page_test.dart` |
| 测试去重 | 仅因相似删已有测试 | 删固定测试前确认：同被测对象 + 同断言集 + 同 L1/L2/L3 层级 + 无独占失败模式 | 全量 `test/*_test.dart` |

---

## 四、CI 与一键验证命令

- **统一验证入口（[`tool/verify.dart`](tool/verify.dart)）**：本地开发与 CI `test` job 共用同一套门禁逻辑，避免命令漂移。
- **CI（[`.github/workflows/build-release.yml`](.github/workflows/build-release.yml)）**：改 `**.md` 不触发；非 PR 触发 `test` + `build-android` + `build-windows` 并行（`test` 失败即 `fail-fast` 中止打包），`test` 调用 `dart run tool/verify.dart --lint-only` 与 `--tests-only`；PR 额外跑 `verify-android`（`flutter build apk --debug --config-only` + `./android/gradlew -p android :app:processDebugManifest :app:compileDebugKotlin`）；`v*` 标签全绿校验版本号一致后发 Release。
- **代理 502 处理**：`$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:NO_PROXY='127.0.0.1,localhost'`。

```powershell
# 日常快速门禁（L0 格式/分析 + Windows 编码检查 + 架构守卫，<15s）
dart run tool/verify.dart --quick

# 完整验证（L0 + zf_academic + 主工程全量测试）
dart run tool/verify.dart --full

# 改 android/ 或升 SDK 时追加原生校验（可选再加 --probe 检查 ../tools/probe）
dart run tool/verify.dart --full --android

# 仓库洁净检查
git status -s
```
