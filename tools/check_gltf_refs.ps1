$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\93343\Desktop\demo'
$found = 0; $missingTotal = 0
Get-ChildItem -Recurse -Include *.gltf -Path fp_viewmodel, actor, resources -ErrorAction SilentlyContinue | ForEach-Object {
    $found++
    $txt = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    $uris = [regex]::Matches($txt, '"uri"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    $missing = @()
    foreach ($u in $uris) {
        if ($u -match '^data:') { continue }
        $p = Join-Path $_.DirectoryName $u
        if (-not (Test-Path -LiteralPath $p)) { $missing += $u }
    }
    if ($missing.Count -gt 0) {
        $script:missingTotal += $missing.Count
        Write-Host ("MISSING: " + $_.Name + " -> " + ($missing -join ', '))
    }
}
Write-Host ("scanned gltf: " + $found + ", missing refs: " + $missingTotal)
