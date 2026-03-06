# ============================================================
# Funciones-SSH.ps1
# Biblioteca de funciones para gestion del servicio SSH
# Practica 4 - Acceso Remoto Windows Server
# ============================================================

$global:IP_SSH = ""
$global:INTERFAZ_SSH = "Ethernet 3"   # adaptador host-only

# --- Detectar IP del adaptador host-only ---
function SSH-DetectarIP {
    $ip = (Get-NetIPAddress -InterfaceAlias $global:INTERFAZ_SSH `
        -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress

    if ($ip -and $ip -notlike "169.254.*") {
        $global:IP_SSH = $ip
        ok "IP detectada en $($global:INTERFAZ_SSH): $ip"
    } else {
        Listar-Interfaces
        $global:INTERFAZ_SSH = Read-Host "Interfaz para SSH (ej: Ethernet 3)"
        $global:IP_SSH = Read-Host "IP para el servidor SSH (ej: 192.168.56.101)"
        Configurar-IP-Estatica $global:INTERFAZ_SSH $global:IP_SSH 24
    }
}

# --- Instalar OpenSSH Server ---
function SSH-Instalar {
    titulo "Instalacion de OpenSSH Server"

    # Verificar si ya esta instalado
    $estado = Get-WindowsCapability -Online | Where-Object Name -like "*OpenSSH.Server*"
    if ($estado.State -eq "Installed") {
        ok "OpenSSH Server ya esta instalado."
    } else {
        info "Descargando e instalando OpenSSH Server..."

        # Metodo 1: Windows Capability
        $resultado = Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue

        # Verificar si instalo
        $estado = Get-WindowsCapability -Online | Where-Object Name -like "*OpenSSH.Server*"
        if ($estado.State -ne "Installed") {
            # Metodo 2: Descarga manual desde GitHub
            info "Instalacion via Windows Update fallo. Descargando desde GitHub..."
            $url  = "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip"
            $dest = "C:\OpenSSH-Win64.zip"
            $dir  = "C:\OpenSSH"

            info "Descargando OpenSSH..."
            curl.exe -L -o $dest $url

            info "Descomprimiendo..."
            Expand-Archive -Path $dest -DestinationPath $dir -Force

            info "Instalando servicio..."
            $carpeta = Get-ChildItem $dir | Select-Object -First 1
            & "$dir\$($carpeta.Name)\install-sshd.ps1"

            if ($?) {
                ok "OpenSSH instalado correctamente desde GitHub."
            } else {
                err "Fallo la instalacion de OpenSSH."
                return
            }
        } else {
            ok "OpenSSH Server instalado correctamente."
        }
    }

    # Habilitar e iniciar el servicio
    info "Habilitando servicio sshd..."
    Habilitar-Servicio "sshd"
}

# --- Configurar firewall para SSH ---
function SSH-ConfigurarFirewall {
    titulo "Configurando firewall para SSH"

    $regla = Get-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" -ErrorAction SilentlyContinue
    if (-not $regla) {
        New-NetFirewallRule `
            -Name        "OpenSSH-Server-In" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled     True `
            -Direction   Inbound `
            -Protocol    TCP `
            -Action      Allow `
            -LocalPort   22 | Out-Null
        ok "Regla de firewall creada: puerto 22 TCP abierto."
    } else {
        ok "Regla de firewall para puerto 22 ya existe."
    }
}

# --- Ver estado de SSH ---
function SSH-Estado {
    titulo "Estado del servicio SSH"

    $estado = Get-WindowsCapability -Online | Where-Object Name -like "*OpenSSH.Server*"
    if ($estado.State -eq "Installed") {
        ok "OpenSSH Server: INSTALADO"
    } else {
        err "OpenSSH Server: NO INSTALADO"
    }

    if (Servicio-Activo "sshd") {
        ok "Servicio sshd: ACTIVO"
    } else {
        err "Servicio sshd: INACTIVO"
    }

    $svc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
    if ($svc.StartType -eq "Automatic") {
        ok "Inicio automatico: HABILITADO"
    } else {
        info "Inicio automatico: DESHABILITADO"
    }

    Write-Host ""
    info "Puerto en escucha:"
    netstat -an | findstr ":22"

    Write-Host ""
    info "IP del servidor SSH:"
    SSH-DetectarIP

    Write-Host ""
    info "Regla de firewall:"
    $regla = Get-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" -ErrorAction SilentlyContinue
    if ($regla) {
        ok "Regla firewall encontrada: puerto 22 TCP permitido"
    } else {
        err "No se encontro regla de firewall para puerto 22"
    }
}

# --- Setup completo SSH ---
function SSH-SetupCompleto {
    titulo "Setup completo de SSH"
    SSH-DetectarIP
    Write-Host ""
    SSH-Instalar
    Write-Host ""
    SSH-ConfigurarFirewall
    Write-Host ""
    SSH-Estado
    Write-Host ""
    ok "============================================"
    ok "  SSH listo. Conectate con:"
    ok "  ssh Administrator@$($global:IP_SSH)"
    ok "============================================"
    info "Desde ahora usa SSH para toda configuracion."
}

# --- Reiniciar SSH ---
function SSH-Reiniciar {
    titulo "Reiniciando servicio SSH"
    Restart-Service sshd -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Servicio-Activo "sshd") {
        ok "SSH reiniciado correctamente."
    } else {
        err "Error al reiniciar SSH."
    }
}
