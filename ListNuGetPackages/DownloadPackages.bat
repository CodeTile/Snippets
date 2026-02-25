@echo off
setlocal

cls

set ROOT=%cd%
set CSV=%ROOT%\PackagesInSolution.csv
set NUPKGDIR=%ROOT%\nupkg
set ERRORS=%ROOT%\errors.log

if not exist "%CSV%" (
    echo PackagesInSolution.csv not found.
    exit /b
)

if not exist "%NUPKGDIR%" mkdir "%NUPKGDIR%"
del "%ERRORS%" >nul 2>&1

echo.
echo Downloading .nupkg files using PowerShell CSV parser...
echo.

powershell -NoLogo -NoProfile -Command ^
    "$csv = Import-Csv '%CSV%';" ^
    "foreach ($row in $csv) {" ^
    "    $pkg = $row.Package;" ^
    "    $ver = $row.Version;" ^
    "    if ([string]::IsNullOrWhiteSpace($pkg) -or [string]::IsNullOrWhiteSpace($ver)) { continue }" ^
    "    $pkgLower = $pkg.ToLower();" ^
    "    $verLower = $ver.ToLower();" ^
    "    $url = 'https://api.nuget.org/v3-flatcontainer/' + $pkgLower + '/' + $verLower + '/' + $pkgLower + '.' + $verLower + '.nupkg';" ^
    "    Write-Host 'PACKAGE:' $pkg 'VERSION:' $ver;" ^
    "    Write-Host 'URL:' $url;" ^
    "    $out = Join-Path '%NUPKGDIR%' ($pkg + '.' + $ver + '.nupkg');" ^
    "    try { Invoke-WebRequest -Uri $url -OutFile $out -ErrorAction Stop }" ^
    "    catch { Add-Content '%ERRORS%' ('Failed: ' + $pkg + ' ' + $ver + ' - ' + $_.Exception.Message) }" ^
    "}"

echo.
echo Done.
echo Files saved to: %NUPKGDIR%
echo Errors logged to: %ERRORS%
echo.

endlocal
