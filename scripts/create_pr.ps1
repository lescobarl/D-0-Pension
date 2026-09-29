# Crea el Pull Request feature/estado-inicial -> main mediante la API de GitHub.
# Usa el token almacenado por Git Credential Manager (sin imprimirlo en pantalla).
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/create_pr.ps1
$ErrorActionPreference = 'Stop'

$cred = "protocol=https`nhost=github.com`n`n" | git credential fill
$token = ($cred | Select-String '^password=').Line -replace '^password=',''

if (-not $token) {
    Write-Output "ERROR: No se pudo obtener el token de GitHub desde el Credential Manager."
    exit 1
}

$headers = @{
    Authorization = "Bearer $token"
    "User-Agent"  = "Roo-Devops"
    Accept        = "application/vnd.github+json"
}

$title = "feat(estado-inicial): motor pensiones alineado a Excel + seguridad PII + CI/QA"
$body = @"
## Resumen

Integracion del estado inicial de la calculadora de pension Ley 73 IMSS:

- **Motor de calculo alineado a Excel** (FACT. + ASIG. MOD.40, PENSION MOD. 40, COSTO MOD. 40, PAGO RETROACTIVO, FINANCIAMIENTO, PROYECTO DE PENSION) con paridad verificada: Salario diario 2914.9328685715745, C7 22.75 UMAs, PensionMensual 87540.51695739396.
- **Refactor SRP**: separacion de responsabilidades en lib/core, lib/services, lib/presentation (commit d9a3cb1).
- **Seguridad PII en reposo (v13)**: fechas, salarios, periodos y datos familiares ofuscados via PiiCipher (base64+XOR); migracion idempotente que preserva datos legacy.
- **QA**: `flutter analyze` sin issues; 13 tests de regresion curados + 13 tests de PII; CI verde (test + android + web); gate Codecov informativo 40%.
- Los archivos de diagnostico/comparacion que codifican valores esperados obsoletos quedan excluidos del CI por diseno (ver comentario en flutter-ci.yml).
"@

$payload = @{
    title = $title
    head  = "feature/estado-inicial"
    base  = "main"
    body  = $body
} | ConvertTo-Json -Depth 5

$uri = "https://api.github.com/repos/lescobarl/D-0-Pension/pulls"
try {
    $resp = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($payload))
    Write-Output "PR_CREADO #$($resp.number): $($resp.html_url)"
} catch {
    Write-Output "ERROR al crear el PR: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) { Write-Output $_.ErrorDetails.Message }
    exit 1
}
