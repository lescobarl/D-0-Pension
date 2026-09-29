# Cancela un workflow run de GitHub Actions en D-0-Pension.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/cancel_ci_run.ps1 -RunId <id>
param(
    [Parameter(Mandatory = $true)]
    [long]$RunId
)

$ErrorActionPreference = 'Stop'

$cred = "protocol=https`nhost=github.com`n`n" | git credential fill
$token = ($cred | Select-String '^password=').Line -replace '^password=',''

if (-not $token) {
    Write-Output "ERROR: No se pudo obtener el token de GitHub desde el Credential Manager."
    exit 1
}

$headers = @{ Authorization = "Bearer $token"; "User-Agent" = "Roo-Devops" }
$cancelUri = "https://api.github.com/repos/lescobarl/D-0-Pension/actions/runs/$RunId/cancel"

try {
    $resp = Invoke-WebRequest -Uri $cancelUri -Method Post -Headers $headers -UseBasicParsing
    Write-Output "Run $RunId cancelado. HTTP $($resp.StatusCode)"
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Output "No se pudo cancelar run ${RunId}: HTTP $status - $($_.Exception.Message)"
    exit 1
}
