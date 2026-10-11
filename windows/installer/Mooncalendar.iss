#define MyAppName "Mooncalendar"
; Version: taken from the MOONCALENDAR_VERSION environment variable when set
; (CI passes the release tag), otherwise the default below.
#define MyAppVersion GetEnv("MOONCALENDAR_VERSION")
#if MyAppVersion == ""
  #undef MyAppVersion
  #define MyAppVersion "1.1.2"
#endif

; Flutter build folder: build\windows\<arch>\runner\Release.
#define MyArch "x64"

#define MyAppPublisher "M-D-6"
#define MyAppPublisherURL "https://github.com/M-D-6/MoonCalendar"
#define MyAppExeName "mooncalendar.exe"
#define MyAppId "{{5B2E9C41-7D68-4A13-9E0F-3C84D1A6B72E}"
#define MyAppIcon "..\runner\resources\app_icon.ico"
#define MyPublishDir "..\..\build\windows\" + MyArch + "\runner\Release"
#define MyOutputDir "Output"


[Setup]

AppId={#MyAppId}

AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}

AppPublisher={#MyAppPublisher}

VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoDescription={#MyAppName} Installer
VersionInfoVersion={#MyAppVersion}
VersionInfoTextVersion={#MyAppVersion}
VersionInfoCopyright=Copyright © 2026 {#MyAppPublisher}

AppPublisherURL={#MyAppPublisherURL}
AppSupportURL={#MyAppPublisherURL}
AppUpdatesURL={#MyAppPublisherURL}/releases

DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}

OutputDir={#MyOutputDir}
OutputBaseFilename=MoonCalendar-Setup-{#MyArch}

SetupIconFile={#MyAppIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; 64-bit app, installed in 64-bit mode (also runs on Arm64 Windows 11 via emulation).
; SetupArchitecture needs Inno Setup 7+; older compilers just use a 64-bit loader (UseSetupLdr below).
#if Ver >= 0x07000000
SetupArchitecture=x64
#endif
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Per-user install: no administrator rights; {autopf} resolves to %LocalAppData%\Programs.
PrivilegesRequired=lowest
MinVersion=10.0

WizardStyle=modern windows11 dynamic includetitlebar
WizardSizePercent=120

ShowLanguageDialog=yes
UsePreviousLanguage=no
LanguageDetectionMethod=uilanguage

DisableStartupPrompt=yes
DisableProgramGroupPage=yes
AllowNoIcons=yes

CreateUninstallRegKey=yes
Uninstallable=yes

AppMutex=Local\MoonCalendar.SingleInstance

CloseApplications=yes
RestartApplications=no

SetupLogging=yes
UninstallLogging=yes
UninstallLogMode=append

RedirectionGuard=yes

Compression=lzma
SolidCompression=yes

UseSetupLdr=x64

OutputManifestFile=MoonCalendar-Setup-{#MyArch}.manifest


[Languages]

Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "fa"; MessagesFile: "Languages\Farsi.isl"
Name: "ar"; MessagesFile: "compiler:Languages\Arabic.isl"


[Tasks]

Name: "startmenuicon"; \
    Description: "{cm:CreateStartMenuShortcut}"; \
    GroupDescription: "{cm:AdditionalIcons}"

Name: "desktopicon"; \
    Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"



[Files]

Source: "{#MyPublishDir}\*"; \
    DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs



[UninstallDelete]
; Force cleanup of the exact application directory after uninstall.
; This targets ONLY {app}, not the parent Program Files directory.
Type: filesandordirs; Name: "{app}"


[Icons]

Name: "{autoprograms}\{#MyAppName}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; \
    WorkingDir: "{app}"; \
    Tasks: startmenuicon

Name: "{autodesktop}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; \
    WorkingDir: "{app}"; \
    Tasks: desktopicon


[Run]

Filename: "{app}\{#MyAppExeName}"; \
    Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent


[CustomMessages]

en.AdditionalIcons=Additional shortcuts:
en.CreateStartMenuShortcut=Create Start Menu shortcut
en.CreateDesktopIcon=Create Desktop shortcut
en.LaunchProgram=Launch %1

fa.AdditionalIcons=میانبر های جانبی:
fa.CreateStartMenuShortcut=ایجاد &میانبر در منوی استارت
fa.CreateDesktopIcon=ایجاد &میانبر روی دسکتاپ
fa.LaunchProgram=اجرای %1

ar.AdditionalIcons=اختصارات إضافية:
ar.CreateStartMenuShortcut=إنشاء اختصار في قائمة ابدأ
ar.CreateDesktopIcon=إنشاء اختصار على سطح المكتب
ar.LaunchProgram=تشغيل %1


[Code]

var
  DeleteSettings:
    Boolean;


{ The app registers per-user scheduled tasks for athan and date notifications. }
procedure RemoveScheduledTasks;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\schtasks.exe'), '/Delete /TN "MoonCalendarAthan" /F', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\schtasks.exe'), '/Delete /TN "MoonCalendarDateNotification" /F', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;


{ Start-with-Windows entry written by the app. It is removed only when it points to this installation. }
procedure RemoveStartupEntry;
var
  Command: String;
begin
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Mooncalendar', Command) then
  begin
    if Pos(Lowercase(ExpandConstant('{app}\{#MyAppExeName}')), Lowercase(Command)) > 0 then
      RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Mooncalendar');
  end;
end;


{ Registry keys created by the athan notification code (current user only). }
procedure RemoveNotificationRegistration;
begin
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\AppUserModelId\MoonCalendar.Athan');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\mooncalendar-athan');
end;


{ Per-user data. Restricted to the exact Mooncalendar folders; never %LocalAppData% itself or a wildcard. }
procedure DeleteMoonCalendarSettings;
var
  Folder: String;
begin
  Folder := ExpandConstant('{localappdata}\MoonCalendar');
  if DirExists(Folder) then
    DelTree(Folder, True, True, True);

  Folder := ExpandConstant('{userappdata}\Mooncalendar');
  if DirExists(Folder) then
    DelTree(Folder, True, True, True);
end;


procedure CleanupMoonCalendarShortcuts;
var
  Shortcut: String;
  StartMenuFolder: String;
begin
  Shortcut := ExpandConstant('{autodesktop}\{#MyAppName}.lnk');
  if FileExists(Shortcut) then
    DeleteFile(Shortcut);

  StartMenuFolder := ExpandConstant('{autoprograms}\{#MyAppName}');
  if DirExists(StartMenuFolder) then
    DelTree(StartMenuFolder, True, True, True);

  { Shortcut written by the app for toast notifications (it carries the notification identity). }
  Shortcut := ExpandConstant('{userprograms}\Mooncalendar (اعلان).lnk');
  if FileExists(Shortcut) then
    DeleteFile(Shortcut);
end;


procedure CloseRunningMoonCalendar;
var
  ResultCode: Integer;
begin
  Exec(
    ExpandConstant('{sys}\taskkill.exe'),
    '/IM {#MyAppExeName} /F',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode);
end;


function InitializeUninstall: Boolean;
var
  Form: TSetupForm;
  TitleLabel: TNewStaticText;
  DescriptionLabel: TNewStaticText;
  SettingsCheckBox: TNewCheckBox;
  RemoveButton: TNewButton;
  CancelButton: TNewButton;
  ResultCode: Integer;
  IsPersian: Boolean;
  IsArabic: Boolean;
begin
  { Safe default: settings are deleted unless the user turns the checkbox off. }
  DeleteSettings := True;

  IsPersian := ActiveLanguage = 'fa';
  IsArabic := ActiveLanguage = 'ar';

  Form := CreateCustomForm(ScaleX(470), ScaleY(270), False, False);

  try
    Form.Caption := 'Mooncalendar';
    Form.BorderStyle := bsDialog;
    Form.Position := poScreenCenter;

    TitleLabel := TNewStaticText.Create(Form);
    TitleLabel.Parent := Form;
    TitleLabel.Left := ScaleX(24);
    TitleLabel.Top := ScaleY(22);
    TitleLabel.Width := ScaleX(420);
    TitleLabel.Height := ScaleY(30);
    TitleLabel.AutoSize := False;
    TitleLabel.Font.Style := [fsBold];
    TitleLabel.Font.Size := 12;

    if IsPersian then
      TitleLabel.Caption := 'حذف Mooncalendar'
    else if IsArabic then
      TitleLabel.Caption := 'إزالة Mooncalendar'
    else
      TitleLabel.Caption := 'Remove Mooncalendar';

    DescriptionLabel := TNewStaticText.Create(Form);
    DescriptionLabel.Parent := Form;
    DescriptionLabel.Left := ScaleX(24);
    DescriptionLabel.Top := ScaleY(68);
    DescriptionLabel.Width := ScaleX(420);
    DescriptionLabel.Height := ScaleY(58);
    DescriptionLabel.AutoSize := False;
    DescriptionLabel.WordWrap := True;

    if IsPersian then
      DescriptionLabel.Caption := 'آیا مطمئن هستید که می‌خواهید Mooncalendar از این رایانه حذف شود؟'
    else if IsArabic then
      DescriptionLabel.Caption := 'هل أنت متأكد أنك تريد إزالة Mooncalendar من هذا الكمبيوتر؟'
    else
      DescriptionLabel.Caption := 'Are you sure you want to remove Mooncalendar from this computer?';

    SettingsCheckBox := TNewCheckBox.Create(Form);
    SettingsCheckBox.Parent := Form;
    SettingsCheckBox.Left := ScaleX(24);
    SettingsCheckBox.Top := ScaleY(135);
    SettingsCheckBox.Width := ScaleX(420);
    SettingsCheckBox.Height := ScaleY(28);
    SettingsCheckBox.Checked := True;

    if IsPersian then
      SettingsCheckBox.Caption := 'تنظیمات و داده‌های برنامه نیز حذف شوند'
    else if IsArabic then
      SettingsCheckBox.Caption := 'حذف الإعدادات وبيانات التطبيق أيضًا'
    else
      SettingsCheckBox.Caption := 'Delete settings and application data';

    RemoveButton := TNewButton.Create(Form);
    RemoveButton.Parent := Form;
    RemoveButton.Left := ScaleX(285);
    RemoveButton.Top := ScaleY(210);
    RemoveButton.Width := ScaleX(78);
    RemoveButton.Height := ScaleY(30);
    RemoveButton.Default := True;
    RemoveButton.ModalResult := mrOk;

    if IsPersian then
      RemoveButton.Caption := 'حذف'
    else if IsArabic then
      RemoveButton.Caption := 'إزالة'
    else
      RemoveButton.Caption := 'Remove';

    CancelButton := TNewButton.Create(Form);
    CancelButton.Parent := Form;
    CancelButton.Left := ScaleX(373);
    CancelButton.Top := ScaleY(210);
    CancelButton.Width := ScaleX(70);
    CancelButton.Height := ScaleY(30);
    CancelButton.Cancel := True;
    CancelButton.ModalResult := mrCancel;

    if IsPersian then
      CancelButton.Caption := 'لغو'
    else if IsArabic then
      CancelButton.Caption := 'إلغاء'
    else
      CancelButton.Caption := 'Cancel';

    ResultCode := Form.ShowModal;

    if ResultCode <> mrOk then
    begin
      Result := False;
      Exit;
    end;

    DeleteSettings := SettingsCheckBox.Checked;

    CloseRunningMoonCalendar();
    RemoveScheduledTasks();
    RemoveStartupEntry();
    RemoveNotificationRegistration();

    Result := True;
  finally
    Form.Free;
  end;
end;


procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    { Remove shortcuts only after the application files are gone. }
    CleanupMoonCalendarShortcuts();

    { Extra cleanup for files created after installation. }
    if DirExists(ExpandConstant('{app}')) then
      DelTree(ExpandConstant('{app}'), True, True, True);

    if DeleteSettings then
      DeleteMoonCalendarSettings();
  end;
end;
