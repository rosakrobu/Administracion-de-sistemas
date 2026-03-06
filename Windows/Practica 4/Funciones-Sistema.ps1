# ============================================================
# Funciones-Sistema.ps1
# Diagnostico del sistema - Refactorizacion Practica 1
# Integra informacion de DHCP, DNS y SSH
# ============================================================

# --- Nombre del equipo ---
function Sistema-Hostname {
    info "Nombre del equipo:"
    Write-Host "  $env:COMPUTERNAME"
    Write-Host ""
}

# --- IPs activas ---
function Sistema-IP {
    info "Direcciones IP:"
    Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" } | `
        ForEach-Object { Write-Host "  $($_.InterfaceAlias) : $($_.IPAddress)" }
    Write-Host ""
}

# --- Espacio en disco ---
function Sistema-Disco {
    info "Espacio en disco:"
    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
        $total = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
        $usado = [math]::Round($_.Used / 1GB, 1)
        $libre = [math]::Round($_.Free / 1GB, 1)
        $pct   = [math]::Round(($_.Used / ($_.Used + $_.Free)) * 100, 0)
        Write-Host "  $($_.Name): Total: ${total}GB  Usado: ${usado}GB (${pct}%)  Libre: ${libre}GB"
    }
    Write-Host ""
}

# --- Estado DHCP (Practica 2) ---
function Sistema-EstadoDHCP {
    info "Servidor DHCP:"
    $rol = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue
    if ($rol.Installed) {
        Write-Host "  Rol DHCP      : INSTALADO"
        if (Servicio-Activo "DHCPServer") {
            Write-Host "  Servicio      : ACTIVO"
        } else {
            Write-Host "  Servicio      : INACTIVO"
        }
        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
        Write-Host "  Scopes activos: $($scopes.Count)"
    } else {
        Write-Host "  Rol DHCP      : NO INSTALADO"
    }
    Write-Host ""
}

# --- Estado DNS (Practica 3) ---
function Sistema-EstadoDNS {
    info "Servidor DNS:"
    $rol = Get-WindowsFeature -Name DNS -ErrorAction SilentlyContinue
    if ($rol.Installed) {
        Write-Host "  Rol DNS       : INSTALADO"
        if (Servicio-Activo "DNS") {
            Write-Host "  Servicio      : ACTIVO"
        } else {
            Write-Host "  Servicio      : INACTIVO"
        }
        $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue | `
            Where-Object { $_.ZoneType -eq "Primary" -and $_.ZoneName -notmatch "arpa|localhost|TrustAnchors" }
        if ($zonas) {
            Write-Host "  Zonas activas :"
            foreach ($z in $zonas) { Write-Host "    - $($z.ZoneName)" }
        } else {
            Write-Host "  Zonas activas : ninguna configurada"
        }
    } else {
        Write-Host "  Rol DNS       : NO INSTALADO"
    }
    Write-Host ""
}

# --- Estado SSH (Practica 4) ---
function Sistema-EstadoSSH {
    info "Servidor SSH:"
    $estado = Get-WindowsCapability -Online | Where-Object Name -like "*OpenSSH.Server*"
    if ($estado.State -eq "Installed") {
        Write-Host "  OpenSSH       : INSTALADO"
        if (Servicio-Activo "sshd") {
            Write-Host "  Servicio      : ACTIVO"
        } else {
            Write-Host "  Servicio      : INACTIVO"
        }
        $ip = (Get-NetIPAddress -InterfaceAlias "Ethernet 3" -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        if ($ip) { Write-Host "  IP SSH        : $ip" }
    } else {
        Write-Host "  OpenSSH       : NO INSTALADO"
    }
    Write-Host ""
}

# --- Diagnostico completo ---
function Sistema-EstadoCompleto {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "       BIENVENIDO A WINDOWS SERVER"           -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
    Sistema-Hostname
    Sistema-IP
    Sistema-Disco
    Sistema-EstadoDHCP
    Sistema-EstadoDNS
    Sistema-EstadoSSH
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
}
