#define MyAppName "Mooncalendar"
; Version: taken from the MOONCALENDAR_VERSION environment variable when set
; (CI passes the release tag), otherwise the default below.
#define MyAppVersion GetEnv("MOONCALENDAR_VERSION")
#if MyAppVersion == ""
  #undef MyAppVersion
  #define MyAppVersion "1.1.6"
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
; Force cleanup of the application directory after uninstall, but only when it is a folder of our own
; (named after the app and holding the executable). A folder shared with other programs is never wiped:
; there the uninstaller removes just the files it installed.
Type: filesandordirs; Name: "{app}"; Check: IsOwnAppFolder


[InstallDelete]

Type: filesandordirs; Name: "{autoprograms}\{#MyAppName}"
Type: files; Name: "{userprograms}\Mooncalendar (اعلان).lnk"


[Icons]

Name: "{autoprograms}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; \
    WorkingDir: "{app}"; \
    AppUserModelID: "MoonCalendar.Athan"; \
    Tasks: startmenuicon

Name: "{autodesktop}\{#MyAppName}"; \
    Filename: "{app}\{#MyAppExeName}"; \
    WorkingDir: "{app}"; \
    Tasks: desktopicon


[Run]

Filename: "{app}\{#MyAppExeName}"; \
    Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent

; Silent runs (the in-app updater) have no finish page: start the new version right away.
Filename: "{app}\{#MyAppExeName}"; \
    WorkingDir: "{app}"; \
    Flags: nowait skipifnotsilent


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

en.ModeTitle=Mooncalendar is already installed
en.ModeSubtitle=Version %1 is installed. Choose what to do.
en.ModeUpdate=Update to version %1 (keeps your settings)
en.ModeRepair=Repair this installation (reinstall the program files, keeps your settings)
en.ModeReinstall=Reinstall version %1 over the installed version %2
en.ModeUninstall=Uninstall Mooncalendar
en.BtnUpdate=&Update
en.BtnRepair=&Repair
en.ReadyUpdate=Setup is ready to update Mooncalendar to version %1.
en.ReadyRepair=Setup is ready to repair Mooncalendar. Your settings are kept.
en.DoneUpdate=Mooncalendar was updated.
en.DoneRepair=Mooncalendar was repaired.

fa.ModeTitle=Mooncalendar از قبل نصب شده است
fa.ModeSubtitle=نسخهٔ %1 نصب است. یکی از گزینه‌ها را انتخاب کنید.
fa.ModeUpdate=به‌روزرسانی به نسخهٔ %1 (تنظیمات شما حفظ می‌شود)
fa.ModeRepair=تعمیر نصب فعلی (نصب دوبارهٔ فایل‌های برنامه، تنظیمات حفظ می‌شود)
fa.ModeReinstall=نصب دوبارهٔ نسخهٔ %1 روی نسخهٔ نصب‌شدهٔ %2
fa.ModeUninstall=حذف Mooncalendar
fa.BtnUpdate=&به‌روزرسانی
fa.BtnRepair=&تعمیر
fa.ReadyUpdate=برنامه آمادهٔ به‌روزرسانی Mooncalendar به نسخهٔ %1 است.
fa.ReadyRepair=برنامه آمادهٔ تعمیر Mooncalendar است. تنظیمات شما حفظ می‌شود.
fa.DoneUpdate=Mooncalendar به‌روزرسانی شد.
fa.DoneRepair=Mooncalendar تعمیر شد.

ar.ModeTitle=Mooncalendar مثبّت بالفعل
ar.ModeSubtitle=الإصدار %1 مثبّت. اختر ما تريد فعله.
ar.ModeUpdate=التحديث إلى الإصدار %1 (مع الاحتفاظ بإعداداتك)
ar.ModeRepair=إصلاح هذا التثبيت (إعادة تثبيت ملفات البرنامج مع الاحتفاظ بالإعدادات)
ar.ModeReinstall=إعادة تثبيت الإصدار %1 فوق الإصدار المثبّت %2
ar.ModeUninstall=إزالة Mooncalendar
ar.BtnUpdate=&تحديث
ar.BtnRepair=&إصلاح
ar.ReadyUpdate=الإعداد جاهز لتحديث Mooncalendar إلى الإصدار %1.
ar.ReadyRepair=الإعداد جاهز لإصلاح Mooncalendar. سيتم الاحتفاظ بإعداداتك.
ar.DoneUpdate=تم تحديث Mooncalendar.
ar.DoneRepair=تم إصلاح Mooncalendar.


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
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\AppUserModelId\MoonCalendar.Date');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\AppUserModelId\MoonCalendar.Weather');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\mooncalendar-athan');
end;


{ True only for a dedicated application folder (its name is the app name and it contains our executable). }
function IsOwnAppFolder: Boolean;
var
  Folder: String;
begin
  Folder := RemoveBackslash(ExpandConstant('{app}'));
  Result := (CompareText(ExtractFileName(Folder), '{#MyAppName}') = 0) and
    FileExists(Folder + '\{#MyAppExeName}');
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
  Shortcut := ExpandConstant('{autoprograms}\{#MyAppName}.lnk');
  if FileExists(Shortcut) then
    DeleteFile(Shortcut);
  Shortcut := ExpandConstant('{userprograms}\{#MyAppName}.lnk');
  if FileExists(Shortcut) then
    DeleteFile(Shortcut);

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
    if IsOwnAppFolder() or (CompareText(ExtractFileName(RemoveBackslash(ExpandConstant('{app}'))), '{#MyAppName}') = 0) then
      if DirExists(ExpandConstant('{app}')) then
        DelTree(ExpandConstant('{app}'), True, True, True);

    if DeleteSettings then
      DeleteMoonCalendarSettings();
  end;
end;


{ ---------------------------------------------------------------------------------------------
  Setup side: recognise an existing installation and offer Update / Repair / Uninstall instead of
  a plain first-time install. Silent runs (the in-app updater) skip all of this and just update. }

var
  ModePage: TInputOptionWizardPage;
  InstalledVersion: String;
  InstalledUninstaller: String;
  { 0 = fresh install, 1 = update (older version installed), 2 = repair / reinstall (same or newer) }
  InstallMode: Integer;
  LeaveWithoutAsking: Boolean;


function UninstallKey: String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + '{5B2E9C41-7D68-4A13-9E0F-3C84D1A6B72E}' + '_is1';
end;


function DetectInstalled: Boolean;
var
  Raw: String;
begin
  Result := False;
  InstalledVersion := '';
  InstalledUninstaller := '';
  if RegQueryStringValue(HKCU, UninstallKey, 'DisplayVersion', InstalledVersion) then
  begin
    RegQueryStringValue(HKCU, UninstallKey, 'UninstallString', Raw);
    InstalledUninstaller := RemoveQuotes(Raw);
    Result := True;
  end
  else if RegQueryStringValue(HKLM, UninstallKey, 'DisplayVersion', InstalledVersion) then
  begin
    { An older all-users installation. }
    RegQueryStringValue(HKLM, UninstallKey, 'UninstallString', Raw);
    InstalledUninstaller := RemoveQuotes(Raw);
    Result := True;
  end;
end;


function ComparedToInstalled: Integer;
var
  A, B: Int64;
begin
  if StrToVersion(InstalledVersion, A) and StrToVersion('{#MyAppVersion}', B) then
    Result := ComparePackedVersion(B, A)
  else
    Result := 0;
end;


procedure InitializeWizard;
begin
  InstallMode := 0;
  if not DetectInstalled then
    Exit;

  if ComparedToInstalled > 0 then
    InstallMode := 1
  else
    InstallMode := 2;

  ModePage := CreateInputOptionPage(wpWelcome, CustomMessage('ModeTitle'),
    FmtMessage(CustomMessage('ModeSubtitle'), [InstalledVersion]), '', True, False);

  if InstallMode = 1 then
    ModePage.Add(FmtMessage(CustomMessage('ModeUpdate'), ['{#MyAppVersion}']))
  else if ComparedToInstalled = 0 then
    ModePage.Add(CustomMessage('ModeRepair'))
  else
    ModePage.Add(FmtMessage(CustomMessage('ModeReinstall'), ['{#MyAppVersion}', InstalledVersion]));
  ModePage.Add(CustomMessage('ModeUninstall'));
  ModePage.SelectedValueIndex := 0;
end;


{ The install location is kept from the existing installation. }
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if InstallMode <> 0 then
    Result := (PageID = wpSelectDir);
end;


function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if InstallMode = 0 then
    Exit;
  if CurPageID <> ModePage.ID then
    Exit;
  if ModePage.SelectedValueIndex = 1 then
  begin
    { Hand over to the regular uninstaller (it asks about settings itself) and leave. }
    if FileExists(InstalledUninstaller) then
      Exec(InstalledUninstaller, '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
    Result := False;
    LeaveWithoutAsking := True;
    WizardForm.Close;
  end;
end;


procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if LeaveWithoutAsking then
    Confirm := False;
end;


procedure CurPageChanged(CurPageID: Integer);
begin
  if InstallMode = 0 then
    Exit;

  if CurPageID = wpReady then
  begin
    if InstallMode = 1 then
    begin
      WizardForm.NextButton.Caption := CustomMessage('BtnUpdate');
      WizardForm.ReadyLabel.Caption := FmtMessage(CustomMessage('ReadyUpdate'), ['{#MyAppVersion}']);
    end
    else
    begin
      WizardForm.NextButton.Caption := CustomMessage('BtnRepair');
      WizardForm.ReadyLabel.Caption := CustomMessage('ReadyRepair');
    end;
  end
  else if CurPageID = wpFinished then
  begin
    if InstallMode = 1 then
      WizardForm.FinishedLabel.Caption := CustomMessage('DoneUpdate')
    else
      WizardForm.FinishedLabel.Caption := CustomMessage('DoneRepair');
  end;
end;
