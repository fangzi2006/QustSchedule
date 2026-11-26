/// 应用内更新状态机控制器（脱离具体弹窗生命周期，支持后台下载与全局恢复）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'update_models.dart';
import 'update_service.dart';
import 'updater_gateway.dart';

/// 更新流程所处阶段。
enum UpdateFlowStage {
  /// 尚未发现新版本。
  idle,

  /// 已检测到新版本，等待用户决定。
  available,

  /// 正在后台下载更新包。
  downloading,

  /// 更新包已就绪，等待用户确认安装或授权。
  readyToInstall,

  /// 下载或唤起安装出错。
  error,
}

/// 统一管理版本检查结果、后台下载进度与安装状态的状态机。
///
/// 由 [AppModel] 长期持有，弹窗关闭或按返回键退出后下载不会中断，
/// 用户可通过课表顶栏更新图标随时重新打开当前阶段的弹窗。
class UpdateFlowController extends ChangeNotifier {
  UpdateFlowController({
    this.updateService,
    UpdaterGateway? gateway,
    bool Function()? isAndroid,
  }) : _gateway = gateway ?? const MethodChannelUpdaterGateway(),
       _isAndroid = isAndroid ?? _defaultIsAndroid;

  static bool _defaultIsAndroid() => Platform.isAndroid;

  final UpdateService? updateService;
  final UpdaterGateway _gateway;
  final bool Function() _isAndroid;

  UpdateService? _ownedService;
  UpdateService get _service =>
      updateService ?? (_ownedService ??= UpdateService());

  UpdateCheckResult? _updateResult;
  String _selectedProxy = '';
  List<String> _backupProxies = const <String>[];

  UpdateFlowStage _stage = UpdateFlowStage.idle;
  DownloadProgress? _progress;
  String _currentProxy = '';
  File? _downloadedFile;
  String? _errorMessage;
  bool _needsPermission = false;
  bool _isTriggeringInstall = false;
  bool _allowAvailableFallback = true;
  CancelToken? _cancelToken;

  int _openDialogCount = 0;
  int _backgroundReadyEvent = 0;
  int _backgroundErrorEvent = 0;
  int _requestCloseEvent = 0;
  int _downloadEpoch = 0;
  bool _disposed = false;

  UpdateCheckResult? get updateResult => _updateResult;
  ReleaseInfo? get release => _updateResult?.release;
  ReleaseAsset? get targetAsset => _updateResult?.targetAsset;
  String get selectedProxy => _selectedProxy;
  List<String> get backupProxies => _backupProxies;

  UpdateFlowStage get stage => _stage;
  DownloadProgress? get progress => _progress;
  String get currentProxy => _currentProxy;
  File? get downloadedFile => _downloadedFile;
  String? get errorMessage => _errorMessage;
  bool get needsPermission => _needsPermission;
  bool get isTriggeringInstall => _isTriggeringInstall;
  bool get hasAvailableFallback => _allowAvailableFallback && release != null;
  bool get isDialogOpen => _openDialogCount > 0;
  bool get hasUpdate => _stage != UpdateFlowStage.idle;

  /// 后台收起状态下下载完成事件序号（每次后台完成递增）。
  int get backgroundReadyEvent => _backgroundReadyEvent;

  /// 后台收起状态下下载失败事件序号（每次后台失败递增）。
  int get backgroundErrorEvent => _backgroundErrorEvent;

  /// 控制器请求已打开弹窗自动关闭的事件序号（例如安装器成功拉起后）。
  int get requestCloseEvent => _requestCloseEvent;

  /// 使用最新构造的代理前缀的直连/加速下载地址。
  String get proxiedDownloadUrl {
    final asset = targetAsset;
    if (asset == null) return '';
    return UpdateService.buildProxiedUrl(asset.downloadUrl, _selectedProxy);
  }

  /// 当前错误阶段用于浏览器兜底的下载地址（优先使用回退后的节点）。
  String get fallbackDownloadUrl {
    final asset = targetAsset;
    if (asset == null) return '';
    final proxy = _currentProxy.isNotEmpty ? _currentProxy : _selectedProxy;
    return UpdateService.buildProxiedUrl(asset.downloadUrl, proxy);
  }

  /// 写入检测到的新版本结果。
  ///
  /// 若当前正在下载或已就绪的是同一版本与同款产物，保持既有进度不重置。
  void setAvailableUpdate({
    required UpdateCheckResult result,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
  }) {
    if (_disposed) return;
    final incomingRelease = result.release;
    if (incomingRelease == null) return;

    _selectedProxy = selectedProxy;
    _backupProxies = List<String>.unmodifiable(backupProxies);
    _allowAvailableFallback = true;

    final sameVersion =
        _updateResult?.release?.version == incomingRelease.version &&
        _updateResult?.targetAsset?.name == result.targetAsset?.name;

    if (sameVersion &&
        (_stage == UpdateFlowStage.downloading ||
            _stage == UpdateFlowStage.readyToInstall)) {
      _updateResult = result;
      notifyListeners();
      return;
    }

    _downloadEpoch++;
    _cancelToken?.cancel();
    _cancelToken = null;
    _updateResult = result;
    _stage = UpdateFlowStage.available;
    _progress = null;
    _currentProxy = selectedProxy;
    _downloadedFile = null;
    _errorMessage = null;
    _needsPermission = false;
    _isTriggeringInstall = false;
    notifyListeners();
  }

  /// 直接以指定安装包进入下载流程（兼容只传入 ReleaseAsset 的调用方式）。
  void prepareDirectDownload({
    required ReleaseAsset asset,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
  }) {
    if (_disposed) return;
    _downloadEpoch++;
    _cancelToken?.cancel();
    _cancelToken = null;
    _allowAvailableFallback = false;
    _selectedProxy = selectedProxy;
    _backupProxies = List<String>.unmodifiable(backupProxies);
    _updateResult = UpdateCheckResult(
      status: UpdateStatus.hasUpdate,
      release: ReleaseInfo(
        tagName: '',
        version: '',
        name: asset.name,
        body: '',
        publishedAt: null,
        assets: <ReleaseAsset>[asset],
        htmlUrl: '',
      ),
      targetAsset: asset,
    );
    _stage = UpdateFlowStage.downloading;
    _progress = null;
    _currentProxy = selectedProxy;
    _downloadedFile = null;
    _errorMessage = null;
    _needsPermission = false;
    _isTriggeringInstall = false;
    notifyListeners();
  }

  /// 同步用户最新选择的更新代理。
  void updateProxySelection({
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
  }) {
    if (_disposed) return;
    _selectedProxy = selectedProxy;
    _backupProxies = List<String>.unmodifiable(backupProxies);
    if (_stage == UpdateFlowStage.available) {
      _currentProxy = selectedProxy;
    }
    notifyListeners();
  }

  /// 记录弹窗挂载。
  void attachDialog() {
    _openDialogCount++;
  }

  /// 记录弹窗关闭（只解绑 UI 监听，不中止后台下载）。
  void detachDialog() {
    if (_openDialogCount > 0) {
      _openDialogCount--;
    }
  }

  /// 查询当前平台是否具备应用内安装权限。
  Future<bool> canInstallPackages() => _gateway.canRequestPackageInstalls();

  /// 打开系统安装权限设置页。
  Future<void> openInstallSettings() => _gateway.openInstallSettings();

  /// 检查是否有新版本可用（并执行多代理自动回退）。
  Future<UpdateCheckResult> checkForUpdates({
    required String currentVersion,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
  }) {
    return _service.checkForUpdatesWithFallback(
      currentVersion: currentVersion,
      selectedProxy: selectedProxy,
      backupProxies: backupProxies,
    );
  }

  /// 探测单个更新代理节点的连通性与 API 支持情况。
  Future<ProxyTestResult> testProxy(String proxyUrl) async {
    if (_disposed) {
      return ProxyTestResult(
        proxyUrl: proxyUrl,
        isUsable: false,
        latencyMs: 0,
        supportsApi: false,
      );
    }
    return _service.testProxy(proxyUrl);
  }

  /// 静默清理旧版本更新包与残留临时切片。
  Future<int> cleanOldUpdateFiles({
    String? currentVersion,
    Directory? targetDirectory,
  }) => UpdateService.cleanOldUpdateFiles(
    currentVersion: currentVersion,
    targetDirectory: targetDirectory,
  );

  /// 使用外部浏览器打开合法的 http/https 链接。
  Future<bool> openExternalUrl(String rawUrl) async {
    if (_disposed) return false;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return _gateway.launchExternalUrl(uri);
  }

  /// 开始（或重试）后台下载。
  Future<void> startDownload() async {
    if (_disposed || _isTriggeringInstall) return;
    final asset = targetAsset;
    if (asset == null) return;
    if (_stage == UpdateFlowStage.downloading && _cancelToken != null) {
      return;
    }

    final epoch = ++_downloadEpoch;

    // 若已下载完成且本地包仍存在，直接进入安装环节避免重复下载。
    final existingFile = _downloadedFile;
    if (existingFile != null && existingFile.existsSync()) {
      _stage = UpdateFlowStage.readyToInstall;
      _errorMessage = null;
      notifyListeners();
      if (isDialogOpen && _isAndroid()) {
        await executeInstall();
      }
      return;
    }

    final token = CancelToken();
    _cancelToken = token;
    _stage = UpdateFlowStage.downloading;
    _progress = null;
    _currentProxy = _selectedProxy;
    _errorMessage = null;
    _needsPermission = false;
    notifyListeners();

    try {
      String? expectedSha256;
      final currentRelease = release;
      if (currentRelease != null && _allowAvailableFallback) {
        expectedSha256 = await _service.fetchExpectedSha256(
          release: currentRelease,
          targetAsset: asset,
          selectedProxy: _selectedProxy,
          backupProxies: _backupProxies,
          cancelToken: token,
        );
        if (_disposed ||
            epoch != _downloadEpoch ||
            token.isCancelled ||
            _cancelToken != token) {
          return;
        }
      }

      final file = await _service.downloadAssetWithFallback(
        asset: asset,
        selectedProxy: _selectedProxy,
        backupProxies: _backupProxies,
        cancelToken: token,
        expectedSha256: expectedSha256,
        onProxySwitched: (proxy) {
          if (_disposed ||
              epoch != _downloadEpoch ||
              token.isCancelled ||
              _cancelToken != token) {
            return;
          }
          _currentProxy = proxy;
          notifyListeners();
        },
        onProgress: (progress) {
          if (_disposed ||
              epoch != _downloadEpoch ||
              token.isCancelled ||
              _cancelToken != token) {
            return;
          }
          _progress = progress;
          notifyListeners();
        },
      );

      if (_disposed ||
          epoch != _downloadEpoch ||
          token.isCancelled ||
          _cancelToken != token) {
        return;
      }

      _cancelToken = null;
      _downloadedFile = file;
      _stage = UpdateFlowStage.readyToInstall;
      _errorMessage = null;

      if (_isAndroid()) {
        bool canInstall = true;
        try {
          canInstall = await _gateway.canRequestPackageInstalls();
        } catch (_) {
          canInstall = true;
        }
        if (_disposed ||
            epoch != _downloadEpoch ||
            _stage != UpdateFlowStage.readyToInstall) {
          return;
        }
        _needsPermission = !canInstall;
      }

      if (isDialogOpen) {
        notifyListeners();
        // Android 端弹窗正打开且已授权时直接唤起安装器；
        // Windows 端必须等待用户明确点击「立即重启更新」。
        if (_isAndroid() && !_needsPermission) {
          await executeInstall();
        }
      } else {
        _backgroundReadyEvent++;
        notifyListeners();
      }
    } catch (err) {
      if (_disposed ||
          epoch != _downloadEpoch ||
          token.isCancelled ||
          _cancelToken != token) {
        return;
      }
      _cancelToken = null;
      _stage = UpdateFlowStage.error;
      _errorMessage = '下载失败: $err';
      if (!isDialogOpen) {
        _backgroundErrorEvent++;
      }
      notifyListeners();
    }
  }

  /// 明确中止当前下载并回到待更新状态（仅点击「取消下载」时调用）。
  void cancelDownload() {
    if (_disposed) return;
    _downloadEpoch++;
    _cancelToken?.cancel();
    _cancelToken = null;
    _progress = null;
    _errorMessage = null;
    _isTriggeringInstall = false;
    if (_allowAvailableFallback && release != null) {
      _stage = UpdateFlowStage.available;
    } else {
      _stage = UpdateFlowStage.idle;
    }
    notifyListeners();
  }

  /// 触发安装；返回是否已成功唤起安装器。
  Future<bool> executeInstall() async {
    if (_disposed || _isTriggeringInstall) return false;
    final file = _downloadedFile;
    if (file == null) return false;

    final epoch = _downloadEpoch;
    _isTriggeringInstall = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_isAndroid()) {
        final canInstall = await _gateway.canRequestPackageInstalls();
        if (_disposed ||
            epoch != _downloadEpoch ||
            _stage != UpdateFlowStage.readyToInstall) {
          return false;
        }
        if (!canInstall) {
          _needsPermission = true;
          notifyListeners();
          return false;
        }
        _needsPermission = false;
      }

      await _gateway.install(file);
      if (_disposed ||
          epoch != _downloadEpoch ||
          _stage != UpdateFlowStage.readyToInstall) {
        return false;
      }

      if (isDialogOpen) {
        _requestCloseEvent++;
      }
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed || epoch != _downloadEpoch) return false;
      _errorMessage = '唤起系统安装器失败: $e';
      notifyListeners();
      return false;
    } finally {
      if (!_disposed && epoch == _downloadEpoch) {
        _isTriggeringInstall = false;
        notifyListeners();
      }
    }
  }

  /// 从系统设置页切回前台后重新检查安装权限，若已授予则自动继续安装。
  Future<void> refreshInstallPermissionAndAutoInstall() async {
    if (_disposed || !_isAndroid()) return;
    if (_stage != UpdateFlowStage.readyToInstall || _downloadedFile == null) {
      return;
    }
    final epoch = _downloadEpoch;
    final bool canInstall;
    try {
      canInstall = await _gateway.canRequestPackageInstalls();
    } catch (_) {
      return;
    }
    if (_disposed ||
        epoch != _downloadEpoch ||
        _stage != UpdateFlowStage.readyToInstall) {
      return;
    }

    final previous = _needsPermission;
    _needsPermission = !canInstall;
    if (previous != _needsPermission) {
      notifyListeners();
    }

    if (canInstall && previous) {
      await executeInstall();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _downloadEpoch++;
    _cancelToken?.cancel();
    _cancelToken = null;
    _ownedService?.dispose();
    _ownedService = null;
    super.dispose();
  }
}
