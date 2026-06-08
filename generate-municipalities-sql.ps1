<#
.SYNOPSIS
    Genera co_municipalities_seed.sql con los 1122 municipios de Colombia.

.DESCRIPTION
    Intenta descargar el dataset oficial desde varias fuentes. Si todas
    fallan, da instrucciones para hacerlo manualmente.

.NOTES
    Fuentes intentadas en orden:
      1) https://www.datos.gov.co/resource/xdk5-pm3f.json (Socrata API DANE)
      2) https://geoportal.dane.gov.co/descargas/divipola/DIVIPOLA_Municipios.xlsx
      3) https://www.dane.gov.co/files/geo/divipola.xlsx

    Si ninguna funciona, descargar manualmente desde
    https://www.datos.gov.co/Geograf-a-y-Clima/Municipios-de-Colombia/xdk5-pm3f
    y guardar como municipios_colombia.csv en la carpeta de descargas
#>

$ErrorActionPreference = "Stop"
$urls = @(
  @{ name="Socrata JSON"; url="https://www.datos.gov.co/resource/xdk5-pm3f.json?`$limit=2000"; type="json" },
  @{ name="DIVIPOLA XLSX"; url="https://geoportal.dane.gov.co/descargas/divipola/DIVIPOLA_Municipios.xlsx"; type="xlsx" },
  @{ name="DANE directo"; url="https://www.dane.gov.co/files/geo/divipola.xlsx"; type="xlsx" }
)

$success = $false
foreach ($src in $urls) {
  Write-Host "Probando: $($src.name)..."
  $tmp = Join-Path $env:TEMP "co_municipalities_raw.$($src.type)"
  try {
    Invoke-WebRequest -Uri $src.url -OutFile $tmp -UseBasicParsing -TimeoutSec 30
    Write-Host "  Descargado: $tmp ($((Get-Item $tmp).Length) bytes)"
    # Parsear segun tipo
    if ($src.type -eq "json") {
      $rows = Get-Content $tmp -Raw | ConvertFrom-Json
    } else {
      # XLSX requiere modulo ImportExcel
      if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Warning "Modulo ImportExcel no instalado. Ejecutar: Install-Module ImportExcel -Scope CurrentUser"
        continue
      }
      $rows = Import-Excel $tmp
    }
    # Normalizar nombres de columnas (los CSV del DANE tienen encoding raro)
    Write-Host "  Columnas detectadas: $($rows[0].PSObject.Properties.Name -join ', ')"
    $success = $true
    break
  } catch {
    Write-Host "  FAIL: $($_.Exception.Message)"
  }
}

if (-not $success) {
  Write-Host ""
  Write-Host "No se pudo descargar automaticamente. Pasos manuales:" -ForegroundColor Yellow
  Write-Host "  1) Ve a https://www.datos.gov.co/Geograf-a-y-Clima/Municipios-de-Colombia/xdk5-pm3f"
  Write-Host "  2) Click 'Exportar' -> 'CSV'"
  Write-Host "  3) Guarda como municipios_colombia.csv en tu carpeta de descargas"
  Write-Host "  4) Re-corre este script: el script lo detectara y generara el SQL"
  exit 1
}

# Generar SQL (ajustar nombres de columna segun dataset real)
$values = @()
foreach ($r in $rows) {
  # Mapeo flexible: el nombre exacto depende del dataset
  $muniCode = $r.codigo_dane_municipio ?? $r.cod_municipio ?? $r.'C_digo_Dane_Municipio'
  $muniName = $r.nombre_municipio ?? $r.municipio ?? $r.'Nombre_Municipio'
  $deptCode = $r.codigo_dane_departamento ?? $r.cod_departamento ?? $r.'C_digo_Dane_Departamento'
  $isCapital = if (($r.tipo ?? "") -match "Capital") { "TRUE" } else { "FALSE" }
  if ($muniCode -and $muniName -and $deptCode) {
    $safeName = ($muniName -replace "''", "''''")
    $values += "  ($muniCode, $deptCode, ''$safeName'', $isCapital)"
  }
}

$out = @(
  "-- 1122 Municipios de Colombia (DIVIPOLA DANE)",
  "-- Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC",
  "-- Total: $($values.Count) municipios",
  "",
  "INSERT INTO co_municipalities (code, department_code, name, is_capital) VALUES",
  ($values -join ",`n"),
  "ON CONFLICT (code) DO NOTHING;"
)

$sqlPath = Join-Path $PSScriptRoot "co_municipalities_seed.sql"
$out | Out-File -FilePath $sqlPath -Encoding utf8
Write-Host "Generado: $sqlPath ($($values.Count) municipios, $((Get-Item $sqlPath).Length) bytes)" -ForegroundColor Green
