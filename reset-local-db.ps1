$ErrorActionPreference = "Stop"
Write-Host "WARNING: This deletes the LOCAL Accounting OS database volume." -ForegroundColor Yellow
$answer = Read-Host "Type RESET to continue"
if ($answer -ne "RESET") {
  Write-Host "Cancelled."
  exit 0
}
docker compose down -v
docker compose up -d db
Write-Host "Local database reset and re-seeded."
