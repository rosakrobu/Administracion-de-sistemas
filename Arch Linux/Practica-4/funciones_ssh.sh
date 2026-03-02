#!/bin/bash
# ============================================================
# funciones_ssh.sh
# Biblioteca de funciones para gestion del servicio SSH
# Practica 4 - Acceso Remoto
# ============================================================

IP_OBJETIVO="172.16.0.15"
CIDR_OBJETIVO="24"
INTERFAZ_SSH="enp0s9"   # interfaz host-only para SSH

# --- Detectar la interfaz correcta para la IP objetivo ---
ssh_detectar_interfaz() {
    # Busca que interfaz tiene o puede tener la red 172.16.0.x
    local iface
    iface=$(ip route show | grep "172.16.0" | awk '{print $3}' | head -1)
    if [ -n "$iface" ]; then
        INTERFAZ_SSH="$iface"
    else
        # Mostrar interfaces y preguntar
        listar_interfaces
        read -rp "¿En qué interfaz configurar SSH (ej: enp0s9)? " INTERFAZ_SSH
    fi
    info "Interfaz SSH: $INTERFAZ_SSH"
}

# --- Configurar IP estatica para SSH ---
ssh_configurar_ip() {
    titulo "Configurando red para SSH"

    ssh_detectar_interfaz

    IP_ACTUAL=$(ip addr show "$INTERFAZ_SSH" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

    if [ "$IP_ACTUAL" == "$IP_OBJETIVO" ]; then
        ok "La IP $IP_OBJETIVO ya esta asignada a $INTERFAZ_SSH"
        # Verificar que sea persistente
        if [ ! -f "/etc/systemd/network/20-static-${INTERFAZ_SSH}.network" ]; then
            info "La IP existe pero no es persistente. Configurando persistencia..."
            configurar_ip_estatica "$INTERFAZ_SSH" "$IP_OBJETIVO" "$CIDR_OBJETIVO"
        else
            ok "La IP es persistente (archivo .network encontrado)."
        fi
    else
        info "Configurando IP estatica $IP_OBJETIVO en $INTERFAZ_SSH ..."
        configurar_ip_estatica "$INTERFAZ_SSH" "$IP_OBJETIVO" "$CIDR_OBJETIVO"
    fi
}

# --- Instalar y habilitar OpenSSH ---
ssh_instalar() {
    titulo "Instalacion de OpenSSH"

    instalar_paquete "openssh"

    # Configurar sshd_config para permitir acceso root con password
    info "Configurando /etc/ssh/sshd_config ..."

    # Habilitar PermitRootLogin
    if grep -q "^#PermitRootLogin\|^PermitRootLogin" /etc/ssh/sshd_config; then
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi

    # Habilitar autenticacion por password
    if grep -q "^#PasswordAuthentication\|^PasswordAuthentication" /etc/ssh/sshd_config; then
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    else
        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    fi

    ok "Configuracion de sshd_config aplicada."
    ok "  PermitRootLogin yes"
    ok "  PasswordAuthentication yes"

    # Habilitar e iniciar el servicio
    habilitar_servicio "sshd"
}

# --- Verificar estado de SSH ---
ssh_estado() {
    titulo "Estado del servicio SSH"

    pacman -Q openssh &>/dev/null && ok "Paquete openssh: INSTALADO" || err "Paquete openssh: NO INSTALADO"

    servicio_activo "sshd" && ok "Servicio sshd: ACTIVO" || err "Servicio sshd: INACTIVO"

    systemctl is-enabled --quiet sshd 2>/dev/null \
        && ok "Inicio automatico: HABILITADO (inicia con el sistema)" \
        || err "Inicio automatico: DESHABILITADO (no inicia tras reinicio)"

    echo ""
    info "Puertos en escucha:"
    ss -tlnp | grep ":22"

    echo ""
    info "IP configurada en interfaz SSH ($INTERFAZ_SSH):"
    ip addr show "$INTERFAZ_SSH" 2>/dev/null | grep "inet " || err "Sin IP en $INTERFAZ_SSH"

    echo ""
    info "Archivo de persistencia de red:"
    if [ -f "/etc/systemd/network/20-static-${INTERFAZ_SSH}.network" ]; then
        ok "Encontrado: /etc/systemd/network/20-static-${INTERFAZ_SSH}.network"
        cat "/etc/systemd/network/20-static-${INTERFAZ_SSH}.network"
    else
        err "No encontrado. La IP NO persistira tras reinicio."
    fi
}

# --- Setup completo SSH (IP + instalacion + habilitacion) ---
ssh_setup_completo() {
    titulo "Setup completo de SSH"
    ssh_configurar_ip
    echo ""
    ssh_instalar
    echo ""
    ssh_estado
    echo ""
    ok "=== SSH listo. Conéctate con: ssh root@$IP_OBJETIVO ==="
    info "Desde ahora NO toques la consola fisica. Usa SSH para todo."
}

# --- Reiniciar servicio SSH ---
ssh_reiniciar() {
    titulo "Reiniciando servicio SSH"
    systemctl restart sshd
    sleep 1
    servicio_activo "sshd" && ok "SSH reiniciado correctamente." || err "Error al reiniciar SSH."
}

# --- Mostrar configuracion actual de sshd ---
ssh_ver_config() {
    titulo "Configuracion actual de SSH"
    echo ""
    grep -vE "^#|^$" /etc/ssh/sshd_config
}
