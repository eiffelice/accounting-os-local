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
$expectedName = [System.IO.Path]::GetFileName((Resolve-Path $BackupFile).Path)
if ($manifest.file -ne $expectedName -or $manifest.cipher -ne "AES-256-GCM" -or $manifest.kdf -ne "PBKDF2-SHA256") {
  throw "Backup manifest metadata is invalid."
}
$iterations = [int]$manifest.iterations
if ($iterations -lt 100000 -or $iterations -gt 2000000) { throw "Backup KDF iteration count is invalid." }
$payload = [System.IO.File]::ReadAllBytes((Resolve-Path $BackupFile).Path)
if ($payload.Length -lt 45) { throw "Encrypted backup payload is truncated." }
$actualSha = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($payload)).ToLowerInvariant()
if ($actualSha -ne $manifest.sha256) { throw "Encrypted backup SHA-256 mismatch." }

$salt = $payload[0..15]
$nonce = $payload[16..27]
$tag = $payload[28..43]
$cipher = $payload[44..($payload.Length - 1)]
$kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Passphrase, [byte[]]$salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$key = $kdf.GetBytes(32)
$plain = [byte[]]::new($cipher.Length)
$aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
$aes.Decrypt([byte[]]$nonce, [byte[]]$cipher, [byte[]]$tag, $plain)
$aes.Dispose()
$kdf.Dispose()
[Array]::Clear($key, 0, $key.Length)

$plainFile = (Resolve-Path ".\backups").Path + "\restore-verified.dump"
$containerFile = "/tmp/accounting-os-restore.dump"
[System.IO.File]::WriteAllBytes($plainFile, $plain)
[Array]::Clear($plain, 0, $plain.Length)

try {
  Write-Host "Verifying decrypted backup catalog..."
  docker cp $plainFile "accounting-os-db:$containerFile"
  docker compose exec -T db pg_restore -l $containerFile | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Backup catalog verification failed." }

  Write-Host "DANGER: This replaces the current local Accounting OS database." -ForegroundColor Red
  $answer = Read-Host "Type RESTORE to continue"
  if ($answer -ne "RESTORE") {
    Write-Host "Cancelled."
    exit 0
  }

  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='accounting_os' AND pid <> pg_backend_pid();"
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "DROP DATABASE IF EXISTS accounting_os;"
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U accounting -d postgres -c "CREATE DATABASE accounting_os OWNER accounting;"

  Write-Host "Restoring..."
  docker compose exec -T db pg_restore -v -U accounting -d accounting_os --no-owner $containerFile
} finally {
  docker compose exec -T db rm -f $containerFile | Out-Null
  if (Test-Path $plainFile) { Remove-Item $plainFile -Force }
}

Write-Host "Restore completed. Run npm run test:db before resuming accounting work." -ForegroundColor Green
