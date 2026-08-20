param(
  [string]$Passphrase = $env:BACKUP_ENCRYPTION_PASSPHRASE
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Passphrase)) {
  throw "Set BACKUP_ENCRYPTION_PASSPHRASE before running encrypted backup."
}

New-Item -ItemType Directory -Force -Path ".\backups" | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$containerFile = "/tmp/accounting-os-$stamp.dump"
$plainFile = (Resolve-Path ".\backups").Path + "\accounting-os-$stamp.dump"
$encryptedFile = "$plainFile.enc"
$manifestFile = "$encryptedFile.manifest.json"

Write-Host "Creating PostgreSQL custom-format backup inside DB container..." -ForegroundColor Cyan
docker compose exec -T db sh -lc "pg_dump -U accounting -d accounting_os -Fc -f '$containerFile'"

Write-Host "Verifying backup catalog inside container..."
docker compose exec -T db pg_restore -l $containerFile | Out-Null
if ($LASTEXITCODE -ne 0) { throw "pg_restore catalog verification failed." }

docker cp "accounting-os-db:$containerFile" $plainFile
docker compose exec -T db rm -f $containerFile | Out-Null

$salt = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
$nonce = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
$kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Passphrase, $salt, 310000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$key = $kdf.GetBytes(32)
$plain = [System.IO.File]::ReadAllBytes($plainFile)
$cipher = [byte[]]::new($plain.Length)
$tag = [byte[]]::new(16)
$aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
$aes.Encrypt($nonce, $plain, $cipher, $tag)
$aes.Dispose()

$payload = New-Object byte[] ($salt.Length + $nonce.Length + $tag.Length + $cipher.Length)
[Array]::Copy($salt, 0, $payload, 0, $salt.Length)
[Array]::Copy($nonce, 0, $payload, $salt.Length, $nonce.Length)
[Array]::Copy($tag, 0, $payload, $salt.Length + $nonce.Length, $tag.Length)
[Array]::Copy($cipher, 0, $payload, $salt.Length + $nonce.Length + $tag.Length, $cipher.Length)
[System.IO.File]::WriteAllBytes($encryptedFile, $payload)
Remove-Item $plainFile

$sha = [System.Security.Cryptography.SHA256]::HashData($payload)
$manifest = [ordered]@{
  file = [System.IO.Path]::GetFileName($encryptedFile)
  cipher = "AES-256-GCM"
  kdf = "PBKDF2-SHA256"
  iterations = 310000
  sha256 = [Convert]::ToHexString($sha).ToLowerInvariant()
  createdAt = (Get-Date).ToString("o")
}
$manifest | ConvertTo-Json | Set-Content $manifestFile

Write-Host "Encrypted backup verified: $encryptedFile" -ForegroundColor Green
Write-Host "Manifest: $manifestFile"
