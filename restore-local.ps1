param(
  [Parameter(Mandatory=$true)]
  [string]$BackupFile,
  [string]$Passphrase = $env:BACKUP_ENCRYPTION_PASSPHRASE
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $BackupFile)) { throw "Backup file not found: $BackupFile" }
if ([string]::IsNullOrWhiteSpace($Passphrase)) {
  throw "Set BACKUP_ENCRYPTION_PASSPHRASE before restore."
}

$manifestFile = "$BackupFile.manifest.json"
if (-not (Test-Path $manifestFile)) { throw "Backup manifest not found: $manifestFile" }
$manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json
$payload = [System.IO.File]::ReadAllBytes((Resolve-Path $BackupFile).Path)
$actualSha = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($payload)).ToLowerInvariant()
if ($actualSha -ne $manifest.sha256) { throw "Encrypted backup SHA-256 mismatch." }

$salt = $payload[0..15]
$nonce = $payload[16..27]
$tag = $payload[28..43]
$cipher = $payload[44..($payload.Length - 1)]
$kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Passphrase, [byte[]]$salt, 310000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$key = $kdf.GetBytes(32)
$plain = [byte[]]::new($cipher.Length)
$aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
$aes.Decrypt([byte[]]$nonce, [byte[]]$cipher, [byte[]]$tag, $plain)
$aes.Dispose()

$plainFile = (Resolve-Path ".\backups").Path + "\restore-verified.dump"
[System.IO.File]::WriteAllBytes($plainFile, $plain)

Write-Host "Verifying decrypted backup catalog..."
$containerFile = "/tmp/accounting-os-restore.dump"
docker cp $plainFile "accounting-os-db:$containerFile"
docker compose exec -T db pg_restore -l $containerFile | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Backup catalog verification failed." }

Write-Host "DANGER: This replaces the current local Accounting OS database." -ForegroundColor Red
$answer = Read-Host "Type RESTORE to continue"
if ($answer -ne "RESTORE") {
  docker compose exec -T db rm -f $containerFile | Out-Null
  Remove-Item $plainFile
  Write-Host "Cancelled."
  exit 0
}

docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='accounting_os' AND pid <> pg_backend_pid();"
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "DROP DATABASE IF EXISTS accounting_os;"
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "CREATE DATABASE accounting_os OWNER accounting;"

Write-Host "Restoring..."
docker compose exec -T db pg_restore -v -U accounting -d accounting_os --no-owner $containerFile
docker compose exec -T db rm -f $containerFile | Out-Null
Remove-Item $plainFile

Write-Host "Restore completed. Run npm run test:db before resuming accounting work." -ForegroundColor Green
