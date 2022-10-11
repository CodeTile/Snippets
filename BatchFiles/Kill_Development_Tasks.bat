TASKKILL /F /IM "VBCSCompiler.exe"
TASKKILL /F /IM "MSBuild.exe"
TASKKILL /F /IM "dotnet.exe"
TASKKILL /F /IM "git.exe"

CD "C:\<<My Repositories root folder>>"

FOR /F "tokens=*" %%G IN ('DIR /B /AD /S bin') 			DO RMDIR /S /Q "%%G"
FOR /F "tokens=*" %%G IN ('DIR /B /AD /S obj') 			DO RMDIR /S /Q "%%G"
FOR /F "tokens=*" %%G IN ('DIR /B /AD /S TestResults') 	DO RMDIR /S /Q "%%G"

:: Delete SpecFlow codebehind files
Del /S *.feature.cs
:: Delete MS-SQL backup files
Del /S *.BAK

pause