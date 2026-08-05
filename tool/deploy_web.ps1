# Builds the Flutter web app and deploys it to Vercel (terrax/terrax-tech).
# Live at https://terrax-tech.vercel.app — the "add to home screen" version.
#
# Usage (from the repo root):  powershell -File tool\deploy_web.ps1
$ErrorActionPreference = 'Stop'

$env:PATH = "C:\dev\flutter\bin;$env:PATH"
$env:TMP = "C:\dev\tmp"; $env:TEMP = "C:\dev\tmp"

Set-Location "$PSScriptRoot\.."
flutter build web
if (-not $?) { throw 'flutter build web failed' }

Set-Location "build\web"
# Re-link every time: flutter build can clear build/web, taking .vercel with it.
npx --yes vercel@latest link --yes --project terrax-tech --scope terrax
npx --yes vercel@latest deploy --prod --yes
