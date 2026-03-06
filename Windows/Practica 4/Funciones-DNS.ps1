# ============================================================
# Funciones-DNS.ps1
# Biblioteca de funciones para gestion del servidor DNS
# Refactorizacion de Practica3.ps1
# ============================================================

$global:IP_SERVIDOR_DNS = ""

function DNS-Instalar {
    titulo "Instalacion del servidor DNS"
    $rol = Get-WindowsFeature -Name DNS -ErrorAction SilentlyContinue
    if ($rol.Installed) {
        ok "El rol DNS ya esta instalado."
    } else {
        info "Instalando rol DNS..."
        Install-WindowsFeature -Name DNS -IncludeManagementTools
        if ($?) { ok "Rol DNS instalado correctamente." } else { err "Fallo la instalacion."; return }
    }
    if (-not $global:IP_SERVIDOR_DNS) { DNS-DetectarIP }
    DNS-ConfigurarFirewall
    DNS-IniciarServicio
}

function DNS-DetectarIP {
    Write-Host ""
    Listar-Interfaces
    $interfaz = Read-Host "Nombre de la interfaz (ej: Ethernet 2)"
    $ip = (Get-NetIPAddress -InterfaceAlias $interfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if (-not $ip) {
        err "No se encontro IP en '$interfaz'."
        $ip = Read-Host "Ingresa la IP manualmente"
    }
    $global:IP_SERVIDOR_DNS = $ip
    ok "IP del servidor DNS: $global:IP_SERVIDOR_DNS"
}

function DNS-ConfigurarFirewall {
    info "Abriendo puerto 53 en firewall..."
    if (-not (Get-NetFirewallRule -DisplayName "DNS Puerto 53 UDP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "DNS Puerto 53 UDP" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow | Out-Null
    }
    if (-not (Get-NetFirewallRule -DisplayName "DNS Puerto 53 TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "DNS Puerto 53 TCP" -Direction Inbound -Protocol TCP -LocalPort 53 -Action Allow | Out-Null
    }
    ok "Puerto 53 abierto en firewall."
}

function DNS-IniciarServicio {
    Stop-Service -Name DNS -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Service -Name DNS
    if ((Get-Service -Name DNS).Status -eq "Running") {
        ok "Servicio DNS activo."
        Set-Service -Name DNS -StartupType Automatic
    } else {
        err "El servicio DNS no pudo iniciarse."
    }
}

function DNS-AgregarZona {
    titulo "Agregar dominio DNS"
    if ((Get-Service -Name DNS -ErrorAction SilentlyContinue).Status -ne "Running") {
        info "DNS no esta corriendo. Iniciando..."; DNS-IniciarServicio
    }
    if (-not $global:IP_SERVIDOR_DNS) { DNS-DetectarIP }

    $zona      = Read-Host "Nombre del dominio (ej: midominio.com)"
    $ipCliente = Read-Host "IP del cliente"
    if (-not $zona -or -not $ipCliente) { err "Dominio e IP son obligatorios."; return }

    if (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue) {
        info "El dominio $zona ya existe."; return
    }

    Add-DnsServerPrimaryZone -Name $zona -ZoneFile "$zona.dns" -DynamicUpdate None
    ok "Zona $zona creada."
    Add-DnsServerResourceRecordA -ZoneName $zona -Name "@" -IPv4Address $ipCliente
    ok "Registro A: $zona → $ipCliente"
    Add-DnsServerResourceRecordA -ZoneName $zona -Name "ns1" -IPv4Address $global:IP_SERVIDOR_DNS
    ok "Registro A: ns1.$zona → $global:IP_SERVIDOR_DNS"
    Add-DnsServerResourceRecordCName -ZoneName $zona -Name "www" -HostNameAlias "$zona."
    ok "Registro CNAME: www.$zona → $zona"
}

function DNS-VerZonas {
    titulo "Dominios configurados"
    $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue | `
        Where-Object { $_.ZoneType -eq "Primary" -and $_.ZoneName -notmatch "arpa|localhost|TrustAnchors" }
    if (-not $zonas) { info "No hay dominios configurados."; return }
    $i = 1
    foreach ($z in $zonas) {
        $ip = (Get-DnsServerResourceRecord -ZoneName $z.ZoneName -RRType A -ErrorAction SilentlyContinue | `
            Where-Object { $_.HostName -eq "@" }).RecordData.IPv4Address
        Write-Host "  $i. $($z.ZoneName) → $ip"
        $i++
    }
}

function DNS-EliminarZona {
    titulo "Eliminar dominio DNS"
    DNS-VerZonas
    $zona = Read-Host "`nDominio a eliminar"
    if (-not $zona) { err "El dominio no puede estar vacio."; return }
    if (-not (Get-DnsServerZone -Name $zona -ErrorAction SilentlyContinue)) {
        err "El dominio $zona no existe."; return
    }
    Remove-DnsServerZone -Name $zona -Force
    ok "Dominio $zona eliminado."
}

function DNS-Estado {
    titulo "Estado del servidor DNS"
    if ((Get-WindowsFeature -Name DNS).Installed) { ok "Rol DNS: INSTALADO" } else { err "Rol DNS: NO INSTALADO" }
    if (Servicio-Activo "DNS") { ok "Servicio: ACTIVO" } else { err "Servicio: INACTIVO" }
    Write-Host ""
    DNS-VerZonas
    Write-Host ""
    $dominio = Read-Host "Dominio a consultar (Enter para omitir)"
    if ($dominio -and $global:IP_SERVIDOR_DNS) {
        Resolve-DnsName -Name $dominio -Server $global:IP_SERVIDOR_DNS -ErrorAction SilentlyContinue
    }
}
