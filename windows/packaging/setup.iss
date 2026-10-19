﻿; 青科课表通 · Windows 安装程序（Inno Setup 6）
;
; 用法（在仓库根目录执行，先构建 Windows 版）：
;   flutter build windows --release
;   iscc /DAppVersion=1.1.2 windows\packaging\setup.iss
;
; 产物：build\windows\installer\青科课表通_v1.1.2_安装程序.exe
;
; 注意：
; - 本文件必须保存为 UTF-8（带 BOM），否则里面的中文会乱码。
; - AppVersion 需显式传入（CI 从 pubspec 注入）；本地出包请手动传 /DAppVersion=。
; - 简体中文语言包缺失时脚本会自动退回英文界面（无需手动改），CI 环境无需担心。
; - 不要把 qustschedule.exe 改名：Windows 的数据目录按可执行文件名派生，
;   改名后已保存的账号密码会读不到（表现为要重新登录）。exe 名不变、只改显示名。

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define MyAppName "青科课表通"
#define MyAppExeName "qustschedule.exe"
#define MyAppPublisher "com.fangzi.qustschedule"
#define MyBuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
; AppId 必须固定不变，否则升级时会装成两份而不是覆盖
AppId={{A7F3E2D1-6B4C-4E8A-9D52-1C3B5E7F9A24}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#AppVersion}
; 装到当前用户目录，不需要管理员权限（免 UAC 弹窗）
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableReadyPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\build\windows\installer
OutputBaseFilename=青科课表通_v{#AppVersion}_安装程序
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

; 优先用简体中文；若编译器目录里没有 ChineseSimplified.isl（极少数精简环境），自动退回英文，保证编译不失败。
#if FileExists(CompilerPath + '\Languages\ChineseSimplified.isl')
[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#else
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"; Flags: unchecked

[Files]
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
// VC++ 2015-2022 x64 运行库检测：缺了它程序双击没反应，所以装完要提示
function IsVCRedistInstalled(): Boolean;
var
  Installed: Cardinal;
begin
  Result := False;
  // 先查 64 位注册表视图（VC++ 2015-2022 x64 通常注册在这里）
  if RegQueryDWordValue(HKEY_LOCAL_MACHINE_64,
       'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
    Result := (Installed = 1);
  // 部分系统只注册在 32 位视图（WOW6432Node），补查一次
  if not Result then
    if RegQueryDWordValue(HKEY_LOCAL_MACHINE_32,
         'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
      Result := (Installed = 1);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrorCode: Integer;
begin
  // 装完再提示：不阻断安装，只提醒去装运行库
  if (CurStep = ssPostInstall) and (not IsVCRedistInstalled()) then
  begin
    if MsgBox('未检测到 VC++ 2015-2022 运行库（x64），青科课表通可能无法启动。' + #13#10 + #13#10 +
              '是否现在打开微软官方下载页获取 vc_redist.x64.exe？',
              mbConfirmation, MB_YESNO) = IDYES then
    begin
      ShellExec('open', 'https://aka.ms/vs/17/release/vc_redist.x64.exe', '', '',
                SW_SHOWNORMAL, ewNoWait, ErrorCode);
    end;
  end;
end;
