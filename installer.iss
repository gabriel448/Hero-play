; A versao e passada pelo build_installer.ps1 via linha de comando:
;   ISCC.exe /DAppVersion="1.2.0" installer.iss
; Se rodar manualmente sem o parametro, usa "1.0.0" como fallback.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppName=Hero Play
AppVersion={#AppVersion}
AppPublisher=Sousa
DefaultDirName={autopf}\Hero Play
DefaultGroupName=Hero Play
OutputDir=installer_output
OutputBaseFilename=Hero_Play_Setup_{#AppVersion}
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
Name: "{group}\Hero Play";             Filename: "{app}\iptv_app.exe"
Name: "{group}\Desinstalar Hero Play"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Hero Play";     Filename: "{app}\iptv_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\iptv_app.exe"; Description: "Abrir Hero Play agora"; Flags: nowait postinstall skipifsilent
