# build_installer.ps1
# Uso: .\build_installer.ps1

$ErrorActionPreference = "Stop"

# ─── 1. Lê a versão do pubspec.yaml ──────────────────────────────────────────
$versionLine = (Get-Content pubspec.yaml | Select-String "^version:").ToString()
$version = $versionLine.Split(":")[1].Trim().Split("+")[0]
Write-Host "Versão: $version" -ForegroundColor Cyan

# ─── 2. Localiza o ISCC.exe (tenta registro, depois caminhos comuns) ─────────
function Find-ISCC {
    # 1) Registro (mais confiável — independe do caminho de instalação)
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup*"
    )
    foreach ($pattern in $regPaths) {
        $key = Get-ItemProperty $pattern -ErrorAction SilentlyContinue
        if ($key.InstallLocation) {
            $candidate = Join-Path $key.InstallLocation "ISCC.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    # 2) Caminhos comuns como fallback
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 5\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 5\ISCC.exe",
        "C:\Program Files\Inno Setup 5\ISCC.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    return $null
}

$ISCC = Find-ISCC
if (-not $ISCC) {
    Write-Host ""
    Write-Host "Inno Setup nao encontrado." -ForegroundColor Red
    Write-Host "Baixe em: https://jrsoftware.org/isinfo.php" -ForegroundColor Yellow
    Write-Host "Apos instalar, rode o script novamente." -ForegroundColor Yellow
    exit 1
}
Write-Host "Inno Setup: $ISCC" -ForegroundColor DarkGray

# ─── 3. Compila o Flutter em modo release ────────────────────────────────────
Write-Host "`nCompilando Flutter..." -ForegroundColor Cyan
flutter build windows --release
if (-not $?) { Write-Error "flutter build falhou."; exit 1 }

# ─── 4. Gera o instalador ────────────────────────────────────────────────────
Write-Host "`nGerando instalador..." -ForegroundColor Cyan
& $ISCC "/DAppVersion=$version" installer.iss
if (-not $?) { Write-Error "ISCC falhou."; exit 1 }

# ─── 5. Resultado ────────────────────────────────────────────────────────────
$output = "installer_output\Hero_Play_Setup_$version.exe"
Write-Host "`nInstalador gerado:" -ForegroundColor Green
Write-Host "  $((Resolve-Path $output).Path)" -ForegroundColor Green
