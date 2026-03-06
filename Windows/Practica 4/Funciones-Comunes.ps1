# ============================================================
# Funciones-Comunes.ps1
# Biblioteca de funciones utilitarias compartidas
# Practica 4 - Administracion de Sistemas
# Rosa Karina Rosas Burgueño
# ============================================================

# --- Colores ---
$VERDE   = "Green"
$ROJO    = "Red"
$AMARILLO = "Yellow"
$CYAN    = "Cyan"
$NC      = "White"

function ok     { param($m) Write-Host "[OK] $m"    -ForegroundColor $VERDE }
function err    { param($m) Write-Host "[ERROR] $m" -ForegroundColor $ROJO }
function info   { param($m) Write-Host "[INFO] $m"  -ForegroundColor $AMARILLO }
function titulo { param($m) Write-Host "`n=== $m ===" -ForegroundColor $CYAN }

# --- Verificar permisos de Administrador ---
function Verificar-Admin {
    $admin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        err "Este script debe ejecutarse como Administrador."
        exit 1
    }
    ok "Ejecutando como Administrador."
}

# --- Validar formato de IP ---
function Validar-IP {
    param($ip)
    if ($ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        err "Formato invalido. Usa el formato: X.X.X.X"
        return $false
    }
    $nums = $ip -split '\.'
    foreach ($n in $nums) {
        if ([int]$n -lt 0 -or [int]$n -gt 255) {
            err "Numero fuera de rango (0-255): $n"
            return $false
        }
    }
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") {
        err "Esa IP no es valida para un host."
        return $false
    }
    return $true
}

# --- Listar interfaces de red disponibles ---
function Listar-Interfaces {
    info "Interfaces de red disponibles:"
    Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" } | `
        Format-Table InterfaceAlias, IPAddress -AutoSize
}

# --- Configurar IP estatica en una interfaz ---
function Configurar-IP-Estatica {
    param($interfaz, $ip, $mascara)

    titulo "Configurando IP estatica"
    info "Interfaz : $interfaz"
    info "IP       : $ip/$mascara"

    Remove-NetIPAddress -InterfaceAlias $interfaz -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $interfaz -IPAddress $ip -PrefixLength $mascara | Out-Null
    ok "IP $ip/$mascara configurada en '$interfaz'."
}

# --- Verificar si un servicio esta activo ---
function Servicio-Activo {
    param($nombre)
    $svc = Get-Service -Name $nombre -ErrorAction SilentlyContinue
    return ($svc -and $svc.Status -eq "Running")
}

# --- Habilitar e iniciar servicio ---
function Habilitar-Servicio {
    param($nombre)
    Set-Service -Name $nombre -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name $nombre -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Servicio-Activo $nombre) {
        ok "Servicio '$nombre' activo y habilitado para el arranque."
    } else {
        err "El servicio '$nombre' no pudo iniciarse."
        info "Revisa el Visor de Eventos para mas detalles."
    }
}
