# =====================================================================
#  extend-packages.ps1
#
#  Description:
#    Expands the package list defined in PackagesInSolution.csv by
#    resolving NuGet dependencies using the .NET SDK restore engine.
#
#    - No nuget.exe required (deprecated for dependency resolution)
#    - Creates a temporary SDK project
#    - Adds all packages from PackagesInSolution.csv
#    - Runs "dotnet restore" to build a full dependency graph
#    - Reads project.assets.json to extract all transitive dependencies
#    - Excludes packages containing "pingpong"
#    - Removes any packages already present in C:\Repos\nupkg (if folder exists)
#    - Sorts output alphabetically
#    - Avoids duplicates
#    - Writes updated CSV deterministically
#
# =====================================================================

$csv = "PackagesInSolution.csv"
$temp = "packages_temp.csv"
$proj = "tempdeps.csproj"
$assets = "obj\project.assets.json"
$nupkgFolder = "C:\Repos\nupkg"

# ---------------------------------------------------------------------
# Create temporary project
# ---------------------------------------------------------------------
if (Test-Path $proj) { Remove-Item $proj -Force }
if (Test-Path "obj") { Remove-Item "obj" -Recurse -Force }

dotnet new classlib -n tempdeps -o . --force | Out-Null

# ---------------------------------------------------------------------
# Add packages from CSV
# ---------------------------------------------------------------------
$packages = Import-Csv $csv

foreach ($p in $packages) {
    if ($p.Package -match "pingpong") { continue }
    dotnet add package $p.Package -v $p.Version | Out-Null
}

# ---------------------------------------------------------------------
# Restore to generate dependency graph
# ---------------------------------------------------------------------
dotnet restore | Out-Null

# ---------------------------------------------------------------------
# Parse project.assets.json
# ---------------------------------------------------------------------
$json = Get-Content $assets -Raw | ConvertFrom-Json

$all = @{}

foreach ($tfm in $json.targets.PSObject.Properties.Name) {
    foreach ($pkg in $json.targets.$tfm.PSObject.Properties.Name) {

        # pkg name looks like: "Microsoft.Extensions.Logging/8.0.0"
        $parts = $pkg -split "/"
        if ($parts.Count -ne 2) { continue }

        $name = $parts[0]
        $ver  = $parts[1]

        if ($name -match "pingpong") { continue }

        $key = "$name,$ver"
        if (-not $all.ContainsKey($key)) {
            $all[$key] = [PSCustomObject]@{
                Package = $name
                Version = $ver
            }
        }
    }
}

# ---------------------------------------------------------------------
# Remove packages that already exist in C:\Repos\nupkg (only if folder exists)
# ---------------------------------------------------------------------
if (Test-Path $nupkgFolder) {

    $existing = Get-ChildItem $nupkgFolder -Filter *.nupkg |
                ForEach-Object {
                    $base = $_.BaseName
                    $lastDot = $base.LastIndexOf(".")
                    if ($lastDot -gt 0) {
                        $pkg = $base.Substring(0, $lastDot)
                        $ver = $base.Substring($lastDot + 1)
                        "$pkg,$ver"
                    }
                }

    foreach ($key in $existing) {
        if ($all.ContainsKey($key)) {
            $all.Remove($key)
        }
    }
}

# ---------------------------------------------------------------------
# Sort output
# ---------------------------------------------------------------------
$sorted = $all.Values | Sort-Object Package, Version

# ---------------------------------------------------------------------
# Write updated CSV
# ---------------------------------------------------------------------
"Package,Version" | Out-File $temp -Encoding utf8

foreach ($entry in $sorted) {
    "`"$($entry.Package)`",`"$($entry.Version)`"" | Out-File $temp -Append -Encoding utf8
}

Move-Item -Force $temp $csv

Write-Host ""
Write-Host "Dependency expansion complete."
Write-Host "Updated file: $csv"
Write-Host "Total packages after filtering: $($sorted.Count)"
