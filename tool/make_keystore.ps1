# One-shot Play upload-keystore setup. Asks for a password, generates
# ~/terrax-upload-key.jks, and writes android/key.properties.
# The password never leaves this machine.
$ErrorActionPreference = 'Stop'

$keytool = 'C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot\bin\keytool.exe'
$keystore = Join-Path $env:USERPROFILE 'terrax-upload-key.jks'
$repo = Split-Path -Parent $PSScriptRoot
$props = Join-Path $repo 'android\key.properties'

if (Test-Path $keystore) {
    Write-Host ""
    Write-Host "A keystore already exists at $keystore - not touching it." -ForegroundColor Yellow
    Write-Host "Delete it first ONLY if it has never been uploaded to Google Play."
    exit 1
}

Write-Host ""
Write-Host "This creates the Google Play upload key. The password you invent now" -ForegroundColor Cyan
Write-Host "must be BACKED UP - Google verifies every future app update with it." -ForegroundColor Cyan
Write-Host ""

# Password entry happens in Windows pop-up dialogs (the embedded terminal has
# no keyboard input). The username field is ignored - only type the password.
$c1 = Get-Credential -UserName 'upload' -Message 'INVENT your keystore password (ignore the username field)'
if ($null -eq $c1) { Write-Host 'Cancelled.' -ForegroundColor Red; exit 1 }
$c2 = Get-Credential -UserName 'upload' -Message 'Type the SAME password again to confirm'
if ($null -eq $c2) { Write-Host 'Cancelled.' -ForegroundColor Red; exit 1 }
$plain1 = $c1.GetNetworkCredential().Password
$plain2 = $c2.GetNetworkCredential().Password
if ($plain1 -ne $plain2) { Write-Host 'Passwords do not match - run this again.' -ForegroundColor Red; exit 1 }
if ($plain1.Length -lt 6) { Write-Host 'Password must be at least 6 characters - run this again.' -ForegroundColor Red; exit 1 }

& $keytool -genkey -v -keystore $keystore -keyalg RSA -keysize 2048 `
    -validity 10000 -alias upload -storepass $plain1 -keypass $plain1 `
    -dname 'CN=TERRAX, OU=TERRAX, O=TERRAX, L=Manila, ST=NCR, C=PH'
if ($LASTEXITCODE -ne 0) { Write-Host 'keytool failed - see the message above.' -ForegroundColor Red; exit 1 }

$storeFileForward = $keystore -replace '\\', '/'
@(
    'storePassword=' + $plain1
    'keyPassword=' + $plain1
    'keyAlias=upload'
    'storeFile=' + $storeFileForward
) | Out-File -FilePath $props -Encoding ascii

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Keystore:        $keystore"
Write-Host "  Signing config:  $props (gitignored)"
Write-Host ""
Write-Host "NOW BACK UP the .jks file AND the password (USB drive / password" -ForegroundColor Yellow
Write-Host "manager). If both are lost, publishing updates gets painful." -ForegroundColor Yellow
