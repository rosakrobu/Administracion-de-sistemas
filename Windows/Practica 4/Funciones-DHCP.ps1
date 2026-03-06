# ============================================================
# Funciones-DHCP.ps1
# Biblioteca de funciones para gestion del servidor DHCP
# Refactorizacion de Practica-2.ps1
# ============================================================

function DHCP-Verificar {
    titulo "Verificando instalacion DHCP"
    $rol = Get-WindowsFeature -Name DHCP
    if ($rol.InstallState -eq "Installed") {
        ok "Rol DHCP: INSTALADO"
        if (Servicio-Activo "DHCPServer") { ok "Servicio: ACTIVO" } else { err "Servicio: INACTIVO" }
    } else {
        err "Rol DHCP: NO INSTALADO"
    }
}

function DHCP-Instalar {
    titulo "Instalacion del servidor DHCP"
    $rol = Get-WindowsFeature -Name DHCP
    if ($rol.InstallState -eq "Installed") {
        ok "El rol DHCP ya esta instalado."
        return
    }
    info "Instalando rol DHCP..."
    Install-WindowsFeature -Name DHCP -IncludeManagementTools
    if ((Get-WindowsFeature -Name DHCP).InstallState -eq "Installed") {
        ok "Rol DHCP instalado correctamente."
    } else {
        err "Fallo la instalacion."
    }
}

function DHCP-Configurar {
    titulo "Configuracion del servidor DHCP"

    $SCOPE = Read-Host "Nombre del ambito (scope)"
    if ([string]::IsNullOrEmpty($SCOPE)) { $SCOPE = "MiServidor" }

    do { $IP_INICIO = Read-Host "IP de inicio del rango" } while (-not (Validar-IP $IP_INICIO))

    do {
        $IP_FIN = Read-Host "IP de fin del rango"
        $ok = Validar-IP $IP_FIN
        if ($ok) {
            $o1 = $IP_INICIO -split '\.'; $o2 = $IP_FIN -split '\.'
            $N1 = [int]$o1[0]*16777216+[int]$o1[1]*65536+[int]$o1[2]*256+[int]$o1[3]
            $N2 = [int]$o2[0]*16777216+[int]$o2[1]*65536+[int]$o2[2]*256+[int]$o2[3]
            if ($N2 -le $N1) { err "La IP final debe ser mayor que la inicial."; $ok = $false }
        }
    } while (-not $ok)

    do {
        $LEASE = Read-Host "Tiempo de concesion en segundos"
        $leaseOk = $LEASE -match '^\d+$' -and [int]$LEASE -gt 0
        if (-not $leaseOk) { err "Ingresa un numero valido mayor a 0." }
    } while (-not $leaseOk)

    do {
        $GATEWAY = Read-Host "Gateway (Enter para omitir)"
        if ([string]::IsNullOrEmpty($GATEWAY)) { info "Sin gateway."; break }
    } while (-not (Validar-IP $GATEWAY))

    do {
        $DNS = Read-Host "DNS principal (Enter para omitir)"
        if ([string]::IsNullOrEmpty($DNS)) { info "Sin DNS."; break }
    } while (-not (Validar-IP $DNS))

    $oct = $IP_INICIO -split '\.'
    $RED     = "$($oct[0]).$($oct[1]).$($oct[2]).0"
    $MASCARA = "255.255.255.0"
    $IP_RANGO_INICIO = "$($oct[0]).$($oct[1]).$($oct[2]).$([int]$oct[3]+1)"

    Write-Host "`n-------------------------------"
    Write-Host "   RESUMEN DE CONFIGURACION"
    Write-Host "-------------------------------"
    Write-Host "  Scope  : $SCOPE"
    Write-Host "  Red    : $RED/24"
    Write-Host "  Rango  : $IP_INICIO - $IP_FIN"
    Write-Host "  Lease  : $LEASE segundos"
    Write-Host "  Gateway: $(if([string]::IsNullOrEmpty($GATEWAY)){'(sin gateway)'}else{$GATEWAY})"
    Write-Host "  DNS    : $(if([string]::IsNullOrEmpty($DNS)){'(sin DNS)'}else{$DNS})"
    Write-Host "-------------------------------"

    $CONF = Read-Host "¿Aplicar? (s/n)"
    if ($CONF -notmatch '^[Ss]$') { info "Cancelado."; return }

    try {
        Add-DhcpServerv4Scope -Name $SCOPE -StartRange $IP_RANGO_INICIO -EndRange $IP_FIN -SubnetMask $MASCARA -State Active
        ok "Scope creado."
        if (-not [string]::IsNullOrEmpty($GATEWAY)) { Set-DhcpServerv4OptionValue -ScopeId $RED -OptionId 3 -Value $GATEWAY; ok "Gateway configurado." }
        if (-not [string]::IsNullOrEmpty($DNS))     { Set-DhcpServerv4OptionValue -ScopeId $RED -OptionId 6 -Value $DNS; ok "DNS configurado." }
        $duracion = New-TimeSpan -Seconds ([int]$LEASE)
        Set-DhcpServerv4Scope -ScopeId $RED -LeaseDuration $duracion
        ok "Lease configurado."
        Habilitar-Servicio "DHCPServer"
    } catch { err "Error: $_" }
}

function DHCP-Concesiones {
    titulo "Concesiones activas"
    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if (-not $scopes) { err "No hay scopes configurados."; return }
    $total = 0
    foreach ($scope in $scopes) {
        $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
        if ($leases) {
            Write-Host "  IP asignada          MAC                  Hostname"
            Write-Host "  -----------------------------------------------------------"
            foreach ($l in $leases) {
                Write-Host ("  {0,-20} {1,-20} {2}" -f $l.IPAddress, $l.ClientId, $l.HostName)
                $total++
            }
        }
    }
    Write-Host "`n  Total concesiones: $total"
}

function DHCP-Estado {
    titulo "Estado servidor DHCP"
    $rol = Get-WindowsFeature -Name DHCP
    if ($rol.InstallState -eq "Installed") { ok "Rol DHCP: INSTALADO" } else { err "Rol DHCP: NO INSTALADO" }
    if (Servicio-Activo "DHCPServer") { ok "Servicio: ACTIVO" } else { err "Servicio: INACTIVO" }
    $svc = Get-Service DHCPServer -ErrorAction SilentlyContinue
    if ($svc.StartType -eq "Automatic") { ok "Inicio auto: HABILITADO" } else { info "Inicio auto: DESHABILITADO" }
    Write-Host ""
    Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Format-Table ScopeId, Name, StartRange, EndRange, State -AutoSize
}

function DHCP-Apagar {
    titulo "Apagar servidor DHCP"
    $r = Read-Host "¿Seguro? (s/n)"
    if ($r -notmatch '^[Ss]$') { info "Cancelado."; return }
    Stop-Service DHCPServer -Force
    Start-Sleep -Seconds 2
    if (-not (Servicio-Activo "DHCPServer")) { ok "Servidor DHCP detenido." } else { err "No se pudo detener." }
    $d = Read-Host "¿Deshabilitar inicio automatico? (s/n)"
    if ($d -match '^[Ss]$') { Set-Service DHCPServer -StartupType Disabled; ok "Inicio automatico deshabilitado." }
}
