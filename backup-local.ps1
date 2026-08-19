$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path ".\backups" | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$containerFile = "/tmp/accounting-os-$stamp.dump"
$hostFile = (Resolve-Path ".\backups").Path + "\accounting-os-$stamp.dump"

Write-Host "Creating PostgreSQL custom-format backup inside DB container..." -ForegroundColor Cyan
docker compose exec -T db sh -lc "pg_dump -U accounting -d accounting_os -Fc -f '$containerFile'"

Write-Host "Verifying backup catalog inside container..."
docker compose exec -T db pg_restore -l $containerFile | Out-Null
if ($LASTEXITCODE -ne 0) { throw "pg_restore catalog verification failed." }

Write-Host "Copying verified backup to local disk..."
docker cp "accounting-os-db:$containerFile" $hostFile
docker compose exec -T db rm -f $containerFile | Out-Null

if (-not (Test-Path $hostFile) -or (Get-Item $hostFile).Length -lt 1024) {
  throw "Backup file is missing or unexpectedly small."
}

Write-Host "Backup verified: $hostFile" -ForegroundColor Green
Write-Host "Store a second copy on an encrypted external disk."
