$ErrorActionPreference = "Stop"
Write-Host "Applying Accounting OS versioned migrations..." -ForegroundColor Cyan
npm run migrate

Write-Host "Running database QA..." -ForegroundColor Cyan
npm run test:db

Write-Host "Migration + tax QA complete." -ForegroundColor Green
