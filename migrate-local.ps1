$ErrorActionPreference = "Stop"
Write-Host "Applying Accounting OS v0.3 migrations..." -ForegroundColor Cyan

$migrations = @(
  ".\db\migrations\002_v0_2.sql",
  ".\db\migrations\002_5_v0_3_pre.sql",
  ".\db\migrations\003_v0_3_tax.sql",
  ".\db\migrations\004_v0_3_tax_patch.sql",
  ".\db\migrations\005_v0_3_wht_contract_threshold.sql"
)

foreach ($migration in $migrations) {
  Write-Host "Applying $migration ..."
  Get-Content $migration -Raw |
    docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d accounting_os
}

Write-Host "Running v0.3 tax golden QA..." -ForegroundColor Cyan
Get-Content ".\db\qa_v0_3_tax.sql" -Raw |
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d accounting_os

Write-Host "Migration + tax QA complete." -ForegroundColor Green
