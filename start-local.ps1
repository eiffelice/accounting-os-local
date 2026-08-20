$ErrorActionPreference = "Stop"

Write-Host "== Accounting OS Local v0.3 ==" -ForegroundColor Cyan

if (-not (Test-Path ".env")) {
  $dbPassword = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd("=")
  $databaseUrl = "postgresql://accounting:$dbPassword@127.0.0.1:5432/accounting_os"
  @"
ACCOUNTING_DB_PASSWORD=$dbPassword
DATABASE_URL=$databaseUrl
INITIAL_ADMIN_EMAIL=owner@local.accounting
INITIAL_ADMIN_DISPLAY_NAME=Local Owner
ACCOUNTING_MCP_IDENTITY_ID=
ACCOUNTING_MCP_TOKEN=
APP_BASE_URL=http://localhost:3000
SESSION_TTL_HOURS=12
LOCAL_DOCUMENTS_DIR=./data/documents
COMPANY_TIMEZONE=Asia/Bangkok
"@ | Set-Content ".env" -NoNewline
  Write-Host "Created .env with a random local database password"
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

Write-Host "Installing Node dependencies..."
npm install

Write-Host "Applying versioned migrations..."
npm run migrate

Write-Host "Bootstrapping initial admin if database has no users..."
npm run bootstrap:admin

Write-Host "Running v0.3 tax golden QA..." -ForegroundColor Cyan
npm run test:db

Write-Host ""
Write-Host "Database: 127.0.0.1:5432 (local only)"
Write-Host "Documents: .\data\documents (local only)"
Write-Host "Web UI: http://localhost:3000" -ForegroundColor Green
Write-Host "Tax Core: VAT/WHT deterministic rules enabled" -ForegroundColor Green
Write-Host ""
Write-Host "Use the generated initial admin password shown above once, then change it." -ForegroundColor Yellow

npm run dev:web
