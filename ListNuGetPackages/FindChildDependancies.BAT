@echo off
cls
setlocal enabledelayedexpansion

rem =====================================================================
rem  extend-packages.bat
rem
rem  Description:
rem    Expands the package list defined in PackagesInSolution.csv by
rem    resolving NuGet dependencies using "nuget.exe install -WhatIf".
rem
rem    - No packages are downloaded (simulation only).
rem    - Input source is PackagesInSolution.csv (Package,Version).
rem    - Excludes any package whose name contains "pingpong".
rem    - Avoids duplicates and avoids re-processing packages.
rem    - Writes updated list to packages_temp.csv, then replaces original.
rem    - Reports:
rem         * Initial package count
rem         * Number of new packages added
rem         * Final total package count
rem
rem    If nuget.exe is missing, it is automatically downloaded.
rem =====================================================================

set "csv=PackagesInSolution.csv"
set "temp=packages_temp.csv"
set "nuget=nuget.exe"

rem ---------------------------------------------------------
rem Download nuget.exe if missing
rem ---------------------------------------------------------
if not exist "%nuget%" (
    echo nuget.exe not found. Downloading...
    powershell -NoLogo -NoProfile -Command ^
        "Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile '%nuget%'"
    echo Download complete.
    echo.
)

rem ---------------------------------------------------------
rem Start dependency expansion
rem ---------------------------------------------------------
> "%temp%" echo "Package","Version"

powershell -NoLogo -NoProfile -Command ^
  "$seen=@{}; $processed=@{}; $initialCount=0;" ^
  "Import-Csv '%csv%' | ForEach-Object { if ($_.Package -match 'pingpong') { return }; $key=$_.Package+','+$_.Version; $seen[$key]=$_; };" ^
  "$initialCount=$seen.Count;" ^
  "foreach ($entry in $seen.Values) { Add-Content '%temp%' ('\"'+$entry.Package+'\",\"'+$entry.Version+'\"'); };" ^
  "foreach ($entry in $seen.Values) { $pkg=$entry.Package; $ver=$entry.Version; $procKey=$pkg+','+$ver; if ($processed.ContainsKey($procKey)) { continue }; $processed[$procKey]=$true; $output = & '%nuget%' install $pkg -Version $ver -DependencyVersion Highest -WhatIf 2>$null; foreach ($line in $output) { if ($line -match 'Installing ([^ ]+) ([0-9][^ ]*)') { $depPkg=$matches[1]; $depVer=$matches[2]; if ($depPkg -match 'pingpong') { continue }; $key=$depPkg+','+$depVer; if (-not $seen.ContainsKey($key)) { $seen[$key]=@{Package=$depPkg;Version=$depVer}; Add-Content '%temp%' ('\"'+$depPkg+'\",\"'+$depVer+'\"'); } } } };" ^
  "$finalCount=$seen.Count; $added=$finalCount-$initialCount;" ^
  "Write-Host ('Initial packages: '+$initialCount);" ^
  "Write-Host ('New packages added: '+$added);" ^
  "Write-Host ('Final total: '+$finalCount);"

move /y "%temp%" "%csv%" >nul

echo.
echo Dependency expansion complete.
echo Updated file: %csv%
