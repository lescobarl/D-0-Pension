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

$failedRun = $runs.workflow_runs | Where-Object { $_.conclusion -eq 'failure' } | Select-Object -First 1

if (-not $failedRun) {
    $latest = $runs.workflow_runs | Select-Object -First 1
    Write-Output "Ultimo run: $($latest.name) | rama: $($latest.head_branch) | status: $($latest.status) | conclusion: $($latest.conclusion)"
    exit 0
}

Write-Output "RUN FALLIDO: $($failedRun.name) | id: $($failedRun.id) | rama: $($failedRun.head_branch)"
Write-Output "URL: $($failedRun.html_url)"
Write-Output ""

# Detalle de jobs del run fallido
$jobsUri = "https://api.github.com/repos/lescobarl/D-0-Pension/actions/runs/$($failedRun.id)/jobs"
$jobs = Invoke-RestMethod -Uri $jobsUri -Headers $headers
$failedJob = $null
foreach ($job in $jobs.jobs) {
    Write-Output "JOB: $($job.name) | status: $($job.status) | conclusion: $($job.conclusion) | id: $($job.id)"
    foreach ($step in $job.steps) {
        $marker = if ($step.conclusion -eq 'failure') { '<<< FALLO' } else { '' }
        "{0}   -> {1} | {2} | {3} {4}" -f $step.number, $step.name, $step.status, $step.conclusion, $marker
        if ($step.conclusion -eq 'failure') { $failedJob = $job }
    }
    Write-Output ""
}

# Descargar y mostrar el log del job fallido (filtrado a las lineas relevantes)
if ($failedJob) {
    Write-Output "===== LOG JOB FALLIDO (id $($failedJob.id)) ====="
    $logUrl = "https://api.github.com/repos/lescobarl/D-0-Pension/actions/jobs/$($failedJob.id)/logs"
    try {
        $resp = Invoke-WebRequest -Uri $logUrl -Headers $headers -UseBasicParsing
        $lines = $resp.Content -split "`r?`n"
        Write-Output "Total lineas de log: $($lines.Count)"
        Write-Output "----- Ultimas 40 lineas -----"
        $lines | Select-Object -Last 40
        Write-Output "----- Lineas con 'error'/'fail'/pub -----"
        $lines | Where-Object { $_ -match 'error|fail|exception|pub get|Cannot|unable' }
    } catch {
        Write-Output "No se pudo descargar el log: $($_.Exception.Message)"
    }
}
