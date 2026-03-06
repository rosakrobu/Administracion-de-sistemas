# ============================================================
# Main.ps1
# Punto de entrada unico - Practicas 2, 3 y 4 (Windows)
# Administracion de Sistemas - Windows Server
# Rosa Karina Rosas Burgueño
# Universidad Autonoma de Sinaloa
# ============================================================

# --- Cargar bibliotecas ---
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$SCRIPT_DIR\lib\Funciones-Comunes.ps1"
. "$SCRIPT_DIR\lib\Funciones-Sistema.ps1"
. "$SCRIPT_DIR\lib\Funciones-SSH.ps1"
. "$SCRIPT_DIR\lib\Funciones-DHCP.ps1"
. "$SCRIPT_DIR\lib\Funciones-DNS.ps1"

# --- Verificar administrador ---
Verificar-Admin

# ============================================================
# MENUS
# ============================================================

function Menu-SSH {
    while ($true) {
        Clear-Host
        Write-Host "`n  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host   "  ║        PRACTICA 4 - SSH              ║" -ForegroundColor Cyan
        Write-Host   "  ╚══════════════════════════════════════╝`n" -ForegroundColor Cyan
        Write-Host "  1. Setup completo SSH (recomendado)"
        Write-Host "  2. Instalar OpenSSH Server"
        Write-Host "  3. Configurar firewall (puerto 22)"
        Write-Host "  4. Ver estado del servicio"
        Write-Host "  5. Reiniciar SSH"
        Write-Host "  0. Volver al menu principal`n"
        $opc = Read-Host "  Selecciona"
        switch ($opc) {
            "1" { SSH-SetupCompleto }
            "2" { SSH-Instalar }
            "3" { SSH-ConfigurarFirewall }
            "4" { SSH-Estado }
            "5" { SSH-Reiniciar }
            "0" { return }
            default { err "Opcion invalida." }
        }
        Read-Host "`n  Presiona Enter para continuar"
    }
}

function Menu-Sistema {
    while ($true) {
        Clear-Host
        Write-Host "`n  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host   "  ║     PRACTICA 1 - DIAGNOSTICO         ║" -ForegroundColor Cyan
        Write-Host   "  ╚══════════════════════════════════════╝`n" -ForegroundColor Cyan
        Write-Host "  1. Estado completo del sistema"
        Write-Host "  2. Nombre del equipo"
        Write-Host "  3. Direcciones IP"
        Write-Host "  4. Espacio en disco"
        Write-Host "  0. Volver al menu principal`n"
        $opc = Read-Host "  Selecciona"
        switch ($opc) {
            "1" { Sistema-EstadoCompleto }
            "2" { Sistema-Hostname }
            "3" { Sistema-IP }
            "4" { Sistema-Disco }
            "0" { return }
            default { err "Opcion invalida." }
        }
        Read-Host "`n  Presiona Enter para continuar"
    }
}

function Menu-DHCP {
    while ($true) {
        Clear-Host
        Write-Host "`n  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host   "  ║        PRACTICA 2 - DHCP             ║" -ForegroundColor Cyan
        Write-Host   "  ╚══════════════════════════════════════╝`n" -ForegroundColor Cyan
        Write-Host "  1. Verificar instalacion"
        Write-Host "  2. Instalar servidor DHCP"
        Write-Host "  3. Configurar DHCP"
        Write-Host "  4. Ver concesiones activas"
        Write-Host "  5. Ver estado del servidor"
        Write-Host "  6. Apagar servidor DHCP"
        Write-Host "  0. Volver al menu principal`n"
        $opc = Read-Host "  Selecciona"
        switch ($opc) {
            "1" { DHCP-Verificar }
            "2" { DHCP-Instalar }
            "3" { DHCP-Configurar }
            "4" { DHCP-Concesiones }
            "5" { DHCP-Estado }
            "6" { DHCP-Apagar }
            "0" { return }
            default { err "Opcion invalida." }
        }
        Read-Host "`n  Presiona Enter para continuar"
    }
}

function Menu-DNS {
    while ($true) {
        Clear-Host
        Write-Host "`n  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host   "  ║        PRACTICA 3 - DNS              ║" -ForegroundColor Cyan
        Write-Host   "  ╚══════════════════════════════════════╝`n" -ForegroundColor Cyan
        Write-Host "  1. Instalar rol DNS"
        Write-Host "  2. Agregar dominio"
        Write-Host "  3. Ver dominios configurados"
        Write-Host "  4. Eliminar dominio"
        Write-Host "  5. Ver estado del servicio"
        Write-Host "  0. Volver al menu principal`n"
        $opc = Read-Host "  Selecciona"
        switch ($opc) {
            "1" { DNS-Instalar }
            "2" { DNS-AgregarZona }
            "3" { DNS-VerZonas }
            "4" { DNS-EliminarZona }
            "5" { DNS-Estado }
            "0" { return }
            default { err "Opcion invalida." }
        }
        Read-Host "`n  Presiona Enter para continuar"
    }
}

# --- Menu Principal ---
while ($true) {
    Clear-Host
    Write-Host "`n  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host   "  ║   ADMINISTRACION DE SISTEMAS             ║" -ForegroundColor Cyan
    Write-Host   "  ║   Rosa Karina Rosas Burgueño             ║" -ForegroundColor Cyan
    Write-Host   "  ║   Universidad Autonoma de Sinaloa        ║" -ForegroundColor Cyan
    Write-Host   "  ╠══════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host   "  ║  1. Diagnostico Sistema  (Practica 1)   ║" -ForegroundColor Cyan
    Write-Host   "  ║  2. SSH - Acceso Remoto  (Practica 4)   ║" -ForegroundColor Cyan
    Write-Host   "  ║  3. DHCP - Servidor      (Practica 2)   ║" -ForegroundColor Cyan
    Write-Host   "  ║  4. DNS  - Servidor      (Practica 3)   ║" -ForegroundColor Cyan
    Write-Host   "  ║  0. Salir                               ║" -ForegroundColor Cyan
    Write-Host   "  ╚══════════════════════════════════════════╝`n" -ForegroundColor Cyan
    $opc = Read-Host "  Selecciona modulo"
    switch ($opc) {
        "1" { Menu-Sistema }
        "2" { Menu-SSH }
        "3" { Menu-DHCP }
        "4" { Menu-DNS }
        "0" { Write-Host "Saliendo..."; exit 0 }
        default { err "Opcion invalida." }
    }
}
