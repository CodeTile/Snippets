@echo off
setlocal enabledelayedexpansion

set "pkgroot=C:\Users\%USERNAME%\.nuget\packages"
set "outfile=PackagesInSolution..csv"

rem Clear or create the output file
> "%outfile%" echo "Package","Version"

for /d %%P in ("%pkgroot%\*") do (
    for /d %%V in ("%%P\*") do (
        >> "%outfile%" echo "%%~nxP","%%~nxV"
    )
)

echo CSV written to %outfile%
