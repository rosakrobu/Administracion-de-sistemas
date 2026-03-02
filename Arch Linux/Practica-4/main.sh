#!/bin/bash
# ============================================================
# main.sh
# Punto de entrada unico - Practicas 2, 3 y 4
# Administracion de Sistemas - Arch Linux
# Rosa Karina Rosas Burgueño
# Universidad Autonoma de Sinaloa
# ============================================================

# --- Cargar bibliotecas de funciones ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/funciones_comunes.sh"
source "$SCRIPT_DIR/lib/funciones_dhcp.sh"
source "$SCRIPT_DIR/lib/funciones_dns.sh"
source "$SCRIPT_DIR/lib/funciones_ssh.sh"

# --- Verificar root antes de cualquier cosa ---
verificar_root

# ============================================================
# MENUS
# ============================================================

menu_ssh() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo "  ╔══════════════════════════════════════╗"
        echo "  ║        PRACTICA 4 - SSH              ║"
        echo "  ╚══════════════════════════════════════╝"
        echo -e "${NC}"
        echo "  1. Setup completo SSH (recomendado)"
        echo "  2. Configurar IP estatica persistente"
        echo "  3. Instalar / Habilitar OpenSSH"
        echo "  4. Ver estado del servicio"
        echo "  5. Ver configuracion de sshd"
        echo "  6. Reiniciar SSH"
        echo "  0. Volver al menu principal"
        echo ""
        read -rp "  Selecciona: " OPC
        case "$OPC" in
            1) ssh_setup_completo ;;
            2) ssh_configurar_ip ;;
            3) ssh_instalar ;;
            4) ssh_estado ;;
            5) ssh_ver_config ;;
            6) ssh_reiniciar ;;
            0) return ;;
            *) err "Opcion invalida." ;;
        esac
        read -rp "  Presiona Enter para continuar..." _
    done
}

menu_dhcp() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo "  ╔══════════════════════════════════════╗"
        echo "  ║        PRACTICA 2 - DHCP             ║"
        echo "  ╚══════════════════════════════════════╝"
        echo -e "${NC}"
        echo "  1. Verificar instalacion"
        echo "  2. Instalar servidor DHCP"
        echo "  3. Configurar DHCP"
        echo "  4. Ver concesiones activas"
        echo "  5. Ver estado del servidor"
        echo "  6. Apagar servidor DHCP"
        echo "  0. Volver al menu principal"
        echo ""
        read -rp "  Selecciona: " OPC
        case "$OPC" in
            1) dhcp_verificar ;;
            2) dhcp_instalar ;;
            3) dhcp_configurar ;;
            4) dhcp_concesiones ;;
            5) dhcp_estado ;;
            6) dhcp_apagar ;;
            0) return ;;
            *) err "Opcion invalida." ;;
        esac
        read -rp "  Presiona Enter para continuar..." _
    done
}

menu_dns() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo "  ╔══════════════════════════════════════╗"
        echo "  ║        PRACTICA 3 - DNS              ║"
        echo "  ╚══════════════════════════════════════╝"
        echo -e "${NC}"
        echo "  1. Instalar BIND9"
        echo "  2. Configurar zona DNS"
        echo "  3. Cambiar dominio"
        echo "  4. Eliminar dominio"
        echo "  5. Ver estado del DNS"
        echo "  0. Volver al menu principal"
        echo ""
        read -rp "  Selecciona: " OPC
        case "$OPC" in
            1) dns_instalar ;;
            2) dns_configurar_zona ;;
            3) dns_cambiar_zona ;;
            4) dns_eliminar_zona ;;
            5) dns_estado ;;
            0) return ;;
            *) err "Opcion invalida." ;;
        esac
        read -rp "  Presiona Enter para continuar..." _
    done
}

menu_principal() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo "  ╔══════════════════════════════════════════╗"
        echo "  ║   ADMINISTRACION DE SISTEMAS             ║"
        echo "  ║   Rosa Karina Rosas Burgueño             ║"
        echo "  ║   Universidad Autonoma de Sinaloa        ║"
        echo "  ╠══════════════════════════════════════════╣"
        echo "  ║  1. SSH - Acceso Remoto  (Practica 4)   ║"
        echo "  ║  2. DHCP - Servidor      (Practica 2)   ║"
        echo "  ║  3. DNS  - Servidor      (Practica 3)   ║"
        echo "  ║  0. Salir                               ║"
        echo "  ╚══════════════════════════════════════════╝"
        echo -e "${NC}"
        read -rp "  Selecciona modulo: " OPC
        case "$OPC" in
            1) menu_ssh ;;
            2) menu_dhcp ;;
            3) menu_dns ;;
            0) echo "Saliendo..."; exit 0 ;;
            *) err "Opcion invalida." ;;
        esac
    done
}

# --- Punto de entrada ---
menu_principal
