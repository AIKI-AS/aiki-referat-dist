# AIKI Meetings — installasjon for Windows.
#
#   irm https://referat.aiki.as/install.ps1 | iex
#
# Motstykket til install.sh, og med vilje like ordknapp. Den henter siste
# utgivelse, kontrollerer nedlastingen mot sjekksummen som ligger ved siden av
# den, kjører installasjonsprogrammet, og legger igjen provisjoneringsfila og
# talegjenkjenningsmodellen der appen leter etter dem.
#
# Nøkkelen kan gis på to måter, som på macOS:
#   $env:AIKI_KEY = "aiki_..."; irm .../install.ps1 | iex
# eller ved at skriptet spør.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # ellers krabber Invoke-WebRequest

$Repo     = 'AIKI-AS/aiki-referat-dist'
$AppName  = 'AIKI Meetings'
$SetupAsset = 'AIKI-Meetings-setup.exe'

function Fail($msg) { Write-Host "[FEIL] $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "-> $msg" }

# --- Krav ---------------------------------------------------------------
if ([Environment]::OSVersion.Version.Major -lt 10) {
    Fail "$AppName krever Windows 10 eller nyere."
}
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    Fail "$AppName finnes foreløpig bare for 64-bits Intel/AMD på Windows (fant $env:PROCESSOR_ARCHITECTURE)."
}

# --- Nøkkel -------------------------------------------------------------
$CalendarKey = $env:AIKI_KEY
if (-not $CalendarKey) {
    $CalendarKey = Read-Host 'Lim inn nokkelen du fikk av AIKI (Enter for aa hoppe over)'
}
$CalendarKey = ($CalendarKey -replace '\s', '')

# --- Adressene ----------------------------------------------------------
# Faste adresser, ikke API-et. api.github.com tillater 60 uautentiserte kall i
# timen per IP, og en bedrift der alle deler én utgaaende adresse sliter det
# opp paa en formiddag. Disse er rene omdirigeringer til siste utgivelse og
# har ingen slik grense.
$base     = "https://github.com/$Repo/releases/latest/download"
$setupUrl = "$base/$SetupAsset"
$shaUrl   = "$base/$SetupAsset.sha256"

$tmp = Join-Path $env:TEMP ("aiki-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $setup = Join-Path $tmp $SetupAsset
    Step "Laster ned $SetupAsset ..."
    try {
        Invoke-WebRequest -Uri $setupUrl -OutFile $setup
    } catch {
        Fail "Fikk ikke lastet ned $AppName. Finnes det en Windows-utgivelse ennaa? Kontakt AIKI (jonathan@aiki.as)."
    }

    # Integriteten til nedlastingen, uavhengig av kodesignering. Samme
    # kontroll som macOS-skriptet gjoer, og den blir staaende ogsaa etter at
    # signeringen er paa plass.
    Step 'Kontrollerer nedlastingen ...'
    try {
        $expected = (Invoke-RestMethod -Uri $shaUrl).ToString().Trim().Split()[0]
    } catch {
        Fail 'Utgivelsen mangler sjekksum. Kontakt AIKI (jonathan@aiki.as).'
    }
    $actual = (Get-FileHash -Path $setup -Algorithm SHA256).Hash.ToLower()
    if ($expected.ToLower() -ne $actual) {
        Fail 'Nedlastingen stemmer ikke med utgivelsen. Avbryter.'
    }

    Step 'Installerer ...'
    # /S er NSIS sin stille modus. Installasjonsprogrammet er ikke signert av
    # en kjent utgiver ennaa, saa SmartScreen kan spoerre foerst.
    $proc = Start-Process -FilePath $setup -ArgumentList '/S' -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Fail "Installasjonen feilet (kode $($proc.ExitCode))." }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# --- Provisjonering -----------------------------------------------------
if ($CalendarKey) {
    $dir = Join-Path $env:USERPROFILE 'aiki-referat'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $config = @{
        url     = 'https://referat.aiki.as'
        key     = $CalendarKey
        summary = @{ provider = 'server' }
    } | ConvertTo-Json
    $path = Join-Path $dir 'calendar-server.json'
    Set-Content -Path $path -Value $config -Encoding UTF8

    # Bare eieren skal kunne lese en credential, ogsaa naar hjemmemappa er
    # delt. Motstykket til chmod 600.
    $acl = Get-Acl $path
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $env:USERNAME, 'FullControl', 'Allow')))
    Set-Acl -Path $path -AclObject $acl

    Step 'Kalenderoppsett provisjonert (appen konfigurerer seg selv)'
}

# --- Modellen -----------------------------------------------------------
# Samme fil og samme plassering som appen bruker: Tauri sin app_data_dir er
# pakke-IDen, ikke produktnavnet.
$modelsDir = Join-Path $env:APPDATA 'as.aiki.referat\models'
$modelFile = Join-Path $modelsDir 'ggml-nb-whisper-large.bin'
$modelUrl  = 'https://huggingface.co/NbAiLab/nb-whisper-large/resolve/main/ggml-model-q5_0.bin'
$minBytes  = 900MB

if ((Test-Path $modelFile) -and ((Get-Item $modelFile).Length -ge $minBytes)) {
    Step 'NB-Whisper-modellen finnes allerede - hopper over nedlasting'
} else {
    Step 'Laster ned den norske talegjenkjenningsmodellen (~1 GB) ...'
    New-Item -ItemType Directory -Path $modelsDir -Force | Out-Null
    $part = "$modelFile.part"
    try {
        Invoke-WebRequest -Uri $modelUrl -OutFile $part
        if ((Get-Item $part).Length -lt $minBytes) {
            Remove-Item -Force $part -ErrorAction SilentlyContinue
            Write-Host '   Nedlastingen ble ufullstendig. Appen henter modellen selv ved foerste oppstart.'
        } else {
            Move-Item -Force $part $modelFile
        }
    } catch {
        Remove-Item -Force $part -ErrorAction SilentlyContinue
        Write-Host '   Kunne ikke hente modellen naa. Appen henter den selv ved foerste oppstart.'
    }
}

Write-Host ''
Write-Host "$AppName er installert." -ForegroundColor Green
Write-Host 'Du finner den paa Start-menyen. Oppdater senere med samme kommando.'
