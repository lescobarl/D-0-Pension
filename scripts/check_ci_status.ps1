# Consulta el estado de GitHub Actions del repositorio D-0-Pension.
# Usa el token almacenado por Git Credential Manager (sin imprimirlo en pantalla).
$ErrorActionPreference = 'Stop'

$cred = "protocol=https`nhost=github.com`n`n" | git credential fill
$token = ($cred | Select-String '^password=').Line -replace '^password=',''

if (-not $token) {
    Write-Output "ERROR: No se pudo obtener el token de GitHub desde el Credential Manager."
    exit 1
}

$headers = @{ Authorization = "Bearer $token"; "User-Agent" = "Roo-Devops" }
$runUri = "https://api.github.com/repos/lescobarl/D-0-Pension/actions/runs?per_page=5"

$runs = Invoke-RestMethod -Uri $runUri -Headers $headers

if (-not $runs.workflow_runs -or $runs.workflow_runs.Count -eq 0) {
    Write-Output "No se encontraron workflow runs."
    exit 0
}

$targetRun = $runs.workflow_runs | Select-Object -First 1

if (-not $targetRun) {
    Write-Output "No se encontraron workflow runs."
    exit 0
}

Write-Output "RUN MAS RECIENTE: $($targetRun.name) | id: $($targetRun.id) | commit: $($targetRun.head_sha.Substring(0,7)) | rama: $($targetRun.head_branch) | status: $($targetRun.status) | conclusion: $($targetRun.conclusion)"
Write-Output "URL: $($targetRun.html_url)"
Write-Output ""

# Detalle de jobs del run objetivo
$jobsUri = "https://api.github.com/repos/lescobarl/D-0-Pension/actions/runs/$($targetRun.id)/jobs"
$jobs = Invoke-RestMethod -Uri $jobsUri -Headers $headers
$failedJob = $null
$monitorJob = $null
foreach ($job in $jobs.jobs) {
    Write-Output "JOB: $($job.name) | status: $($job.status) | conclusion: $($job.conclusion) | id: $($job.id)"
    foreach ($step in $job.steps) {
        $marker = if ($step.conclusion -eq 'failure') { '<<< FALLO' } else { '' }
        "{0}   -> {1} | {2} | {3} {4}" -f $step.number, $step.name, $step.status, $step.conclusion, $marker
        if ($step.conclusion -eq 'failure') { $failedJob = $job }
        if ($step.name -eq 'Run tests' -and $step.status -eq 'in_progress') { $monitorJob = $job }
    }
    Write-Output ""
}

# Descargar log del job a diagnosticar: el fallido (si terminó) o el de tests en curso (monitoreo)
$diagnoseJob = if ($failedJob -and $targetRun.status -eq 'completed') { $failedJob } elseif ($monitorJob) { $monitorJob } else { $null }
if ($diagnoseJob) {
    Write-Output "===== LOG JOB (id $($diagnoseJob.id)) ====="
    $logUrl = "https://api.github.com/repos/lescobarl/D-0-Pension/actions/jobs/$($diagnoseJob.id)/logs"
    try {
        $resp = Invoke-WebRequest -Uri $logUrl -Headers $headers -UseBasicParsing
        $lines = $resp.Content -split "`r?`n"
        Write-Output "Total lineas de log: $($lines.Count)"
        Write-Output "----- Ultimas 30 lineas (no vacias) -----"
        $lines | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 30
        if ($targetRun.status -eq 'completed') {
            Write-Output "----- Lineas con 'error'/'fail'/exception -----"
            $lines | Where-Object { $_ -match 'error|fail|exception|Cannot|unable|Failed' }
        }
    } catch {
        Write-Output "No se pudo descargar el log: $($_.Exception.Message)"
    }
}
