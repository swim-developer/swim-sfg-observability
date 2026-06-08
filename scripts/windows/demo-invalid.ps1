$ErrorActionPreference = "Stop"

curl.exe -s -X POST http://localhost:8000/publish/invalid | ConvertFrom-Json | ForEach-Object {
    $t = $_.traceparent -split "-"
    Write-Host "  Trace ID: $($t[1])"
    Write-Host "  Status  : $($_.status)"
    Write-Host "  Runway  : $($_.metadata.runway)"
}
