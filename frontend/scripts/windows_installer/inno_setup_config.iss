[Setup]
AppName=AppFlowy
AppVersion={#AppVersion}
AppPublisher=AppFlowy-IO
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
DefaultDirName={autopf}\AppFlowy\
DefaultGroupName=AppFlowy
SetupIconFile=flowy_logo.ico
UninstallDisplayIcon={app}\AppFlowy.exe
UninstallDisplayName=AppFlowy
VersionInfoVersion={#AppVersion}
UsePreviousAppDir=no
ChangesAssociations=yes

[Tasks]
Name: "markdowndefault"; Description: "Make AppFlowy the default app for Markdown files"; GroupDescription: "File associations:"

[Files]
Source: "AppFlowy\AppFlowy.exe"; DestDir: "{app}"; DestName: "AppFlowy.exe"; Flags: ignoreversion
Source: "AppFlowy\*";DestDir: "{app}"
Source: "AppFlowy\data\*";DestDir: "{app}\data\"; Flags: recursesubdirs

[Icons]
Name: "{userdesktop}\AppFlowy"; Filename: "{app}\AppFlowy.exe"
Name: "{group}\AppFlowy"; Filename: "{app}\AppFlowy.exe"

[Registry]
Root: HKCR; Subkey: "AppFlowy"; ValueType: "string"; ValueData: "URL:Custom Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "AppFlowy"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "AppFlowy\DefaultIcon"; ValueType: "string"; ValueData: "{app}\AppFlowy.exe,0"
Root: HKCR; Subkey: "AppFlowy\shell\open\command"; ValueType: "string"; ValueData: """{app}\AppFlowy.exe"" ""%1"""

; Markdown, text and HTML files open in AppFlowy, each in a new tab.
Root: HKA; Subkey: "Software\Classes\AppFlowy.Markdown"; ValueType: string; ValueName: ""; ValueData: "Markdown document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\AppFlowy.Markdown\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\AppFlowy.exe,0"
Root: HKA; Subkey: "Software\Classes\AppFlowy.Markdown\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\AppFlowy.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\AppFlowy.Text"; ValueType: string; ValueName: ""; ValueData: "Text document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\AppFlowy.Text\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\AppFlowy.exe,0"
Root: HKA; Subkey: "Software\Classes\AppFlowy.Text\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\AppFlowy.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\AppFlowy.Html"; ValueType: string; ValueName: ""; ValueData: "HTML document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\AppFlowy.Html\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\AppFlowy.exe,0"
Root: HKA; Subkey: "Software\Classes\AppFlowy.Html\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\AppFlowy.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "AppFlowy"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\AppFlowy.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Markdown"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".md"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.markdown\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Markdown"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".markdown"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.mdown\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Markdown"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".mdown"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.mkd\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Markdown"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".mkd"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.mkdn\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Markdown"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".mkdn"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.txt\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Text"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".txt"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.text\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Text"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".text"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.log\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Text"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".log"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.html\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Html"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".html"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.htm\OpenWithProgids"; ValueType: string; ValueName: "AppFlowy.Html"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\AppFlowy.exe\SupportedTypes"; ValueType: string; ValueName: ".htm"; ValueData: ""
; Lists AppFlowy in Settings > Apps > Default apps.
Root: HKA; Subkey: "Software\AppFlowy"; Flags: uninsdeletekeyifempty
Root: HKA; Subkey: "Software\AppFlowy\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "AppFlowy"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\AppFlowy\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Open Markdown, text and HTML files in AppFlowy."
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".md"; ValueData: "AppFlowy.Markdown"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".markdown"; ValueData: "AppFlowy.Markdown"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mdown"; ValueData: "AppFlowy.Markdown"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mkd"; ValueData: "AppFlowy.Markdown"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mkdn"; ValueData: "AppFlowy.Markdown"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".txt"; ValueData: "AppFlowy.Text"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".text"; ValueData: "AppFlowy.Text"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".log"; ValueData: "AppFlowy.Text"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".html"; ValueData: "AppFlowy.Html"
Root: HKA; Subkey: "Software\AppFlowy\Capabilities\FileAssociations"; ValueType: string; ValueName: ".htm"; ValueData: "AppFlowy.Html"
Root: HKA; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "AppFlowy"; ValueData: "Software\AppFlowy\Capabilities"; Flags: uninsdeletevalue
; Windows keeps the default for text and HTML files to the person, in
; Settings; Markdown usually has no default, so AppFlowy can claim it.
Root: HKA; Subkey: "Software\Classes\.md"; ValueType: string; ValueName: ""; ValueData: "AppFlowy.Markdown"; Flags: uninsdeletevalue; Tasks: markdowndefault
Root: HKA; Subkey: "Software\Classes\.markdown"; ValueType: string; ValueName: ""; ValueData: "AppFlowy.Markdown"; Flags: uninsdeletevalue; Tasks: markdowndefault
Root: HKA; Subkey: "Software\Classes\.mdown"; ValueType: string; ValueName: ""; ValueData: "AppFlowy.Markdown"; Flags: uninsdeletevalue; Tasks: markdowndefault
Root: HKA; Subkey: "Software\Classes\.mkd"; ValueType: string; ValueName: ""; ValueData: "AppFlowy.Markdown"; Flags: uninsdeletevalue; Tasks: markdowndefault
Root: HKA; Subkey: "Software\Classes\.mkdn"; ValueType: string; ValueName: ""; ValueData: "AppFlowy.Markdown"; Flags: uninsdeletevalue; Tasks: markdowndefault

[Run]
Filename: "ms-settings:defaultapps?registeredAppMachine=AppFlowy"; Description: "Choose AppFlowy as the default app for text and HTML files"; Flags: postinstall shellexec skipifsilent nowait
