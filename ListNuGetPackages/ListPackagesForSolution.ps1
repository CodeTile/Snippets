Clear-Host

$root = (Get-Location).Path
$output = Join-Path $root "PackagesInSolution.csv"
$rows = @()

dotnet restore $root | Out-Null

Get-ChildItem -Path $root -Recurse -Filter *.csproj | ForEach-Object {
    $projPath = $_.FullName
    $projName = $_.BaseName

    $assetsPath = Join-Path $_.Directory.FullName "obj\project.assets.json"
    if (-not (Test-Path $assetsPath)) { return }

    $json = Get-Content $assetsPath -Raw | ConvertFrom-Json

    foreach ($tfm in $json.targets.PSObject.Properties.Name) {
        foreach ($pkg in $json.targets.$tfm.PSObject.Properties.Name) {

            # Skip project references (they contain no version)
            if ($json.targets.$tfm.$pkg.type -eq "project") { continue }

            # pkg looks like: "AngleSharp/1.4.0"
            $parts = $pkg.Split("/")
            if ($parts.Length -eq 2) {
                $rows += [PSCustomObject]@{
                    Project = $projName
                    Package = $parts[0]
                    Version = $parts[1]
                }
            }
        }
    }
}

$rows |
    Sort-Object Package, Version -Unique |
    Export-Csv -Path $output -NoTypeInformation

Write-Host "Generated: $output"
