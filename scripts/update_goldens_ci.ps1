# Regenera y descarga los golden baselines generados en CI (ubuntu-latest).
#
# Los goldens son autoritativos para la plataforma de CI porque el rasterizado
# de texto difiere entre SO (FreeType en Linux vs DirectWrite en Windows) y las
# imágenes deben generarse en el mismo entorno que las valida. Este script:
#   1) Dispara el workflow golden-update.yml (a menos que -SkipTrigger).
#   2) Espera a que termine.
#   3) Descarga el artefacto 'goldens' (PNGs generados en Linux).
#   4) Copia los PNGs en test/goldens/, reemplazando los locales.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/update_goldens_ci.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/update_goldens_ci.ps1 -SkipTrigger
#
# -SkipTrigger: solo descarga el artefacto del run más reciente (útil si el
#   proceso anterior fue interrumpido, el workflow ya corrió en CI).
param(
    [string]$Ref = '',
    [int]$TimeoutSeconds = 1200,
    [switch]$SkipTrigger
)

$ErrorActionPreference = 'Stop'

$repo = 'lescobarl/D-0-Pension'
$workflow = 'golden-update.yml'

# --- Token (Git Credential Manager, sin imprimirlo) ---
$cred = "protocol=https`nhost=github.com`n`n" | git credential fill
$token = ($cred | Select-String '^password=').Line -replace '^password=',''
if (-not $token) {
    Write-Output 'ERROR: No se pudo obtener el token de GitHub desde el Credential Manager.'
    exit 1
}

$headers = @{
    Authorization = "Bearer $token"
    'User-Agent'  = 'Roo-Devops'
    Accept        = 'application/vnd.github+json'
}

if (-not $Ref) { $Ref = git rev-parse --abbrev-ref HEAD }
Write-Output "Ref objetivo: $Ref"

# --- 1) Disparar el workflow ---
if (-not $SkipTrigger) {
    $dispatchUri = "https://api.github.com/repos/$repo/actions/workflows/$workflow/dispatches"
    $body = @{ ref = $Ref; inputs = @{ ref = $Ref } } | ConvertTo-Json -Depth 5
    try {
        Invoke-RestMethod -Method Post -Uri $dispatchUri -Headers $headers -Body $body -ContentType 'application/json' | Out-Null
        Write-Output 'Workflow dispatch enviado.'
    } catch {
        Write-Output "ERROR al disparar el workflow: $($_.Exception.Message)"
        exit 1
    }
}

# --- 2) Esperar a que aparezca el run ---
$runsUri = "https://api.github.com/repos/$repo/actions/workflows/$workflow/runs?per_page=10"
$run = $null
$started = Get-Date
while (-not $run) {
    if (((Get-Date) - $started).TotalSeconds -gt 120) {
        Write-Output 'ERROR: No apareció ningún run del workflow.'
        exit 1
    }
    Start-Sleep -Seconds 10
    $runs = Invoke-RestMethod -Uri $runsUri -Headers $headers
    $run = $runs.workflow_runs |
        Where-Object { $_.event -eq 'workflow_dispatch' -and $_.head_branch -eq $Ref } |
        Select-Object -First 1
}
Write-Output "RUN: id=$($run.id) | status=$($run.status) | conclusion=$($run.conclusion)"
Write-Output "URL: $($run.html_url)"

# --- 3) Esperar a que termine ---
$started = Get-Date
while ($run.status -ne 'completed') {
    if (((Get-Date) - $started).TotalSeconds -gt $TimeoutSeconds) {
        Write-Output "ERROR: Timeout esperando al run $($run.id)."
        exit 1
    }
    Start-Sleep -Seconds 30
    $run = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/actions/runs/$($run.id)" -Headers $headers
    Write-Output "  ... status=$($run.status) conclusion=$($run.conclusion)"
}

Write-Output "CONCLUSION: $($run.conclusion)"

if ($run.conclusion -ne 'success') {
    # Mostrar el log del job fallido para diagnosticar
    $jobs = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/actions/runs/$($run.id)/jobs" -Headers $headers
    foreach ($job in $jobs.jobs) {
        if ($job.conclusion -eq 'failure') {
            Write-Output "----- LOG JOB: $($job.name) -----"
            $logUrl = "https://api.github.com/repos/$repo/actions/jobs/$($job.id)/logs"
            $resp = Invoke-WebRequest -Uri $logUrl -Headers $headers -UseBasicParsing
            Write-Output $resp.Content
        }
    }
    exit 1
}

# --- 4) Descargar el artefacto 'goldens' ---
$arts = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/actions/runs/$($run.id)/artifacts" -Headers $headers
$artifact = $arts.artifacts | Where-Object { $_.name -eq 'goldens' } | Select-Object -First 1
if (-not $artifact) {
    Write-Output 'ERROR: No se encontró el artefacto "goldens".'
    exit 1
}

$zipUrl = "https://api.github.com/repos/$repo/actions/artifacts/$($artifact.id)/zip"
$tmpZip = Join-Path $env:TEMP "goldens-$($run.id).zip"
Write-Output "Descargando artefacto (id $($artifact.id))..."
# curl.exe no reenvía el Authorization a hosts distintos en el redirect, a
# diferencia de Invoke-WebRequest, y el endpoint responde con una URL firmada.
curl.exe -sSL -H "Authorization: Bearer $token" -o $tmpZip $zipUrl
if (-not (Test-Path $tmpZip) -or (Get-Item $tmpZip).Length -eq 0) {
    Write-Output 'ERROR: No se pudo descargar el artefacto.'
    exit 1
}

$tmpDir = Join-Path $env:TEMP "goldens-$($run.id)"
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

# --- 5) Copiar los PNGs generados en Linux a test/goldens ---
$dest = Join-Path (Get-Location) 'test\goldens'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$pngs = Get-ChildItem -Path $tmpDir -Filter *.png -Recurse
if (-not $pngs) {
    Write-Output 'ERROR: El artefacto no contiene PNGs.'
    exit 1
}
foreach ($png in $pngs) {
    Copy-Item -Path $png.FullName -Destination (Join-Path $dest $png.Name) -Force
    Write-Output "Actualizado: test/goldens/$($png.Name) ($($png.Length) bytes)"
}

Write-Output ''
Write-Output 'Goldens Linux listos en test/goldens/. Revise con git status y haga commit.'
