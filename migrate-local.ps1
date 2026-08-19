$ErrorActionPreference = "Stop"
Write-Host "Applying Accounting OS v0.2 migrations..." -ForegroundColor Cyan
Get-Content ".\db\migrations\002_v0_2.sql" -Raw |
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d accounting_os
Write-Host "Migration complete." -ForegroundColor Green
