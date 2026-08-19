param(
  [Parameter(Mandatory=$true)]
  [string]$BackupFile
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $BackupFile)) {
  throw "Backup file not found: $BackupFile"
}

Write-Host "DANGER: This replaces the current local Accounting OS database." -ForegroundColor Red
$answer = Read-Host "Type RESTORE to continue"
if ($answer -ne "RESTORE") {
  Write-Host "Cancelled."
  exit 0
}

$containerFile = "/tmp/accounting-os-restore.dump"
docker cp $BackupFile "accounting-os-db:$containerFile"

Write-Host "Verifying backup catalog..."
docker compose exec -T db pg_restore -l $containerFile | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Backup verification failed." }

Write-Host "Terminating connections and recreating database..."
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='accounting_os' AND pid <> pg_backend_pid();"
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "DROP DATABASE IF EXISTS accounting_os;"
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "CREATE DATABASE accounting_os OWNER accounting;"

Write-Host "Restoring..."
docker compose exec -T db pg_restore -v -U accounting -d accounting_os --no-owner $containerFile
docker compose exec -T db rm -f $containerFile | Out-Null

Write-Host "Restore completed. Run db/tests QA before resuming accounting work." -ForegroundColor Green
