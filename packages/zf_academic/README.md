# zf_academic

新正方教务系统的 Dart 客户端基座：凭据存储接口、RFC 6265 Cookie 管理、登录密码加密、
HTTP 传输、登录、课表查询与解析。**纯 Dart，零 Flutter 依赖**，可以脱离 UI 单独测试。

青科课表通（Windows + Android）的协议层就是它。

## 环境要求

- Dart SDK ≥ 3.0（开发用 Flutter 3.47 / Dart 3.13 验证）
- 运行环境：VM / Flutter 移动与桌面（`zf_academic_io.dart` 依赖 `dart:io`；Web 不可用）

## 分层与依赖

```text
zf_academic（纯 Dart barrel，零 Flutter 依赖）
├── credential_store.dart  CredentialStore 接口 + 内存实现 + key 派生
├── cookies.dart           CookieStore（RFC 6265）+ 快照序列化
├── crypto.dart            表单登录 PKCS#1 v1.5 加密 / 统一认证裸 RSA 分块加密
├── errors.dart            AcademicError / ErrorCode（wire 名称稳定）
├── types.dart             公共数据契约 + 传输层契约
├── urls.dart              地址解析 / 白名单 / 应用根路径 / 学期编码
├── util.dart              取值 / 行 id 生成 / delay
├── html.dart              轻量 HTML 扫描（隐藏域 / 验证码 / 身份 / 下拉框）
├── respond.dart           响应分类（错误不能当成空数据）
├── schedule.dart          课表与学期解析
├── http_client.dart       AcademicHttpClient：手动重定向、白名单、重试、限速、字符集
│                          （传输层 ZfHttpTransport 可注入，测试用假传输）
└── zhengfang_client.dart  ZhengfangClient：登录 / 会话 / 学期 / 课表

zf_academic_io（依赖 dart:io）
├── FileCookieStorage      Cookie 快照文件持久化（chmod 600）
├── DartIoTransport        dart:io 传输层实现（连接池复用）
└── vmZhengfangClient      带默认传输层的客户端工厂
```

设计纪律：

- **核心包不依赖 Flutter**：`flutter_secure_storage` 只经由 `CredentialStore` 接口在 app 侧
  注入（实现见 `example/secure_storage_flutter.dart`，拷进你的项目即可）。
- **传输层可注入**：重定向 / 白名单 / 重试等逻辑全部用无套接字的假传输测试。

## 跑测试

```sh
cd packages/zf_academic
dart pub get
dart test        # 72 个用例
dart analyze     # 0 问题
```

覆盖：加密的确定性黄金向量、PKCS#1 往返与随机填充、Cookie 匹配/过期/迁移/快照往返、
凭据存储与 key 派生、HTTP 重定向与状态码映射、登录全流程（**服务端用真实 RSA 私钥把
密码解回明文核对**）、验证码（错误换图 / 刷新保序 / 正确码登录）、Cookie 免登查询、
`checkSession` 三态、课表解析（字段 / 节次 / 周次 / 备注）、权限拒绝后的路由发现、
会话失效时不返回空课表。

## 用法

```dart
import 'package:zf_academic/zf_academic_io.dart';

// 1) 登录（表单直登；RSA 加密自动处理）
final client = vmZhengfangClient(
  const ZfClientConfig(baseUrl: 'https://jwglxt1.qust.edu.cn/jwglxt'),
);
final state = await client.login(const Credentials('2407720102', '…'));
if (state is AuthenticatedState) {
  // 2) 保存 Cookie（落盘由 app 决定；凭据放 flutter_secure_storage，见 example/）
  final storage = FileCookieStorage('./zf-session.json');
  await storage.save(client.exportCookies());
}

// 3) 下次启动：免登查询
final snapshot = await storage.load();
final restored = vmZhengfangClient(
  ZfClientConfig(
    baseUrl: 'https://jwglxt1.qust.edu.cn/jwglxt',
    cookies: snapshot,
  ),
);
final schedule = await restored.fetchSchedule('2026-2027-1');
await restored.close();
```

## 支持范围

- 表单直登（RSA 加密 + 图片验证码 + 登录前清理会话）、会话校验、学期目录、
  课表查询（含 `sjkList` 备注）、课表入口的路由发现。
- **统一认证（CAS）不在支持范围**：`probe()` 如实报告 `requiresCas`，
  `login()` 遇到 CAS 学校抛 `WEB_LOGIN_REQUIRED`。
- 只针对新正方的页面结构；旧正方 / 强智 / 金智等系统会在登录阶段报 `PAGE_CHANGED`。
