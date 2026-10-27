# Windows version of setup.sh. Run once from the mobile folder:
#   powershell -ExecutionPolicy Bypass -File setup.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

flutter create . --project-name cvsafe_mobile --org com.cvsafe --platforms=android,ios,web

$manifest = "android/app/src/main/AndroidManifest.xml"
$m = Get-Content $manifest -Raw
if ($m -notmatch "android.permission.INTERNET") {
    $m = $m -replace "<application", "<uses-permission android:name=`"android.permission.INTERNET`"/>`r`n    <application"
}
if ($m -notmatch "usesCleartextTraffic") {
    $m = $m -replace "<application", "<application android:usesCleartextTraffic=`"true`""
}
Set-Content -Path $manifest -Value $m -NoNewline -Encoding UTF8

$plist = "ios/Runner/Info.plist"
if (Test-Path $plist) {
    $p = Get-Content $plist -Raw
    if ($p -notmatch "NSCameraUsageDescription") {
        $keys = @"
	<key>NSCameraUsageDescription</key>
	<string>Take site photos and videos for AI safety analysis.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Record video of the site for AI safety analysis.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Choose site photos and videos for AI safety analysis.</string>
	<key>NSAppTransportSecurity</key>
	<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
"@
        $idx = $p.LastIndexOf("</dict>")
        $p = $p.Substring(0, $idx) + $keys + "`n" + $p.Substring($idx)
        Set-Content -Path $plist -Value $p -NoNewline -Encoding UTF8
    }
}

flutter pub get
Write-Host "Done. Start the AI server, then: flutter run"
