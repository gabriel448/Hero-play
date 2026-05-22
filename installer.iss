; A versao e passada pelo build_installer.ps1 via linha de comando:
;   ISCC.exe /DAppVersion="1.2.0" installer.iss
; Se rodar manualmente sem o parametro, usa "1.0.0" como fallback.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppName=IPTV Player
AppVersion={#AppVersion}
AppPublisher=Sousa
DefaultDirName={autopf}\IPTV Player
DefaultGroupName=IPTV Player
OutputDir=installer_output
OutputBaseFilename=IPTV_Player_Setup_{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\iptv_app.exe
; Permite instalar por cima de versoes antigas sem desinstalar antes.
AppId={{B3F2A1C0-IPTV-PLAYER-SOUSA-0001}}
MinVersion=10.0

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar ícone na Área de Trabalho"; GroupDescription: "Ícones adicionais:"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\IPTV Player";             Filename: "{app}\iptv_app.exe"
Name: "{group}\Desinstalar IPTV Player"; Filename: "{uninstallexe}"
Name: "{commondesktop}\IPTV Player";     Filename: "{app}\iptv_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\iptv_app.exe"; Description: "Abrir IPTV Player agora"; Flags: nowait postinstall skipifsilent
