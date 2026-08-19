$ErrorActionPreference = "Stop"

Write-Host "== Accounting OS Local v0.3 ==" -ForegroundColor Cyan

if (-not (Test-Path ".env")) {
  Copy-Item ".env.example" ".env"
  Write-Host "Created .env from .env.example"
}

New-Item -ItemType Directory -Force -Path ".\data\documents" | Out-Null
New-Item -ItemType Directory -Force -Path ".\backups" | Out-Null

Write-Host "Starting local PostgreSQL..."
docker compose up -d db

Write-Host "Waiting for PostgreSQL..."
for ($i=0; $i -lt 30; $i++) {
  docker compose exec -T db pg_isready -U accounting -d accounting_os | Out-Null
  if ($LASTEXITCODE -eq 0) { break }
  Start-Sleep -Seconds 1
}

$migrations = @(
  ".\db\migrations\002_v0_2.sql",
  ".\db\migrations\002_5_v0_3_pre.sql",
  ".\db\migrations\003_v0_3_tax.sql",
  ".\db\migrations\004_v0_3_tax_patch.sql"
)

foreach ($migration in $migrations) {
  Write-Host "Applying $migration ..."
  Get-Content $migration -Raw |
    docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d accounting_os
}

Write-Host "Running v0.3 tax golden QA..." -ForegroundColor Cyan
Get-Content ".\db\qa_v0_3_tax.sql" -Raw |
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d accounting_os

Write-Host "Installing Node dependencies..."
npm install

Write-Host ""
Write-Host "Database: 127.0.0.1:5432 (local only)"
Write-Host "Documents: .\data\documents (local only)"
Write-Host "Web UI: http://localhost:3000" -ForegroundColor Green
Write-Host "Tax Core: VAT/WHT deterministic rules enabled" -ForegroundColor Green
Write-Host ""
Write-Host "Demo login: owner@local.accounting / change-me-now" -ForegroundColor Yellow
Write-Host "CHANGE THE DEMO PASSWORD before using real data." -ForegroundColor Yellow

npm run dev:web
