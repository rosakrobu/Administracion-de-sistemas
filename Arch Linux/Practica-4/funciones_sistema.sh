#!/bin/bash
# ============================================================
# funciones_sistema.sh
# Biblioteca de diagnóstico del sistema
# Integra lógica de Práctica 1 (check_status), 
# Práctica 2 (DHCP) y Práctica 3 (DNS)
# ============================================================

# --- Mostrar nombre del equipo (Práctica 1) ---
sistema_hostname() {
    info "Nombre del equipo:"
    echo "  $(hostname)"
    echo ""
}

# --- Mostrar IPs activas excluyendo loopback (Práctica 1) ---
sistema_ip() {
    info "Direccion IP:"
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | while read -r ip; do
        echo "  $ip"
    done
    echo ""
}

# --- Mostrar uso de disco (Práctica 1) ---
sistema_disco() {
    info "Espacio en disco:"
    df -h / | tail -n 1 | awk '{
        print "  Tamaño total : " $2
        print "  Usado        : " $3 " (" $5 ")"
        print "  Disponible   : " $4
    }'
    echo ""
}

# --- Verificar estado del servidor DHCP (Práctica 2) ---
sistema_estado_dhcp() {
    info "Servidor DHCP (dhcpd4):"

    if ! pacman -Q dhcp &>/dev/null; then
        echo "  Paquete dhcp  : NO INSTALADO"
        echo ""
        return
    fi

    if servicio_activo "dhcpd4"; then
        echo "  Servicio      : ACTIVO"
    else
        echo "  Servicio      : INACTIVO"
    fi

    systemctl is-enabled --quiet dhcpd4 2>/dev/null \
        && echo "  Inicio auto   : HABILITADO" \
        || echo "  Inicio auto   : DESHABILITADO"

    # Mostrar rango configurado si existe el archivo
    if [ -f /etc/dhcpd.conf ]; then
        RANGO=$(grep "range" /etc/dhcpd.conf | awk '{print $2, "-", $3}' | tr -d ';')
        SUBNET=$(grep "^subnet" /etc/dhcpd.conf | awk '{print $2}')
        [ -n "$SUBNET" ] && echo "  Red           : $SUBNET/24"
        [ -n "$RANGO"  ] && echo "  Rango         : $RANGO"
    fi

    # Contar concesiones activas (de Práctica 2 - monitorear_concesiones)
    if [ -f /var/lib/dhcp/dhcpd.leases ]; then
        ACTIVOS=$(grep -c "binding state active" /var/lib/dhcp/dhcpd.leases 2>/dev/null || echo 0)
        echo "  Concesiones   : $ACTIVOS activa(s)"
    fi

    echo ""
}

# --- Verificar estado del servidor DNS (Práctica 3) ---
sistema_estado_dns() {
    info "Servidor DNS (BIND9 / named):"

    if ! pacman -Q bind &>/dev/null; then
        echo "  Paquete bind  : NO INSTALADO"
        echo ""
        return
    fi

    if servicio_activo "named"; then
        echo "  Servicio      : ACTIVO"
    else
        echo "  Servicio      : INACTIVO"
    fi

    systemctl is-enabled --quiet named 2>/dev/null \
        && echo "  Inicio auto   : HABILITADO" \
        || echo "  Inicio auto   : DESHABILITADO"

    # Mostrar zonas configuradas (de Práctica 3 - configurar_zona_dns)
    if [ -f /etc/named.conf ]; then
        ZONAS=$(grep "^zone" /etc/named.conf | grep -v '"."' | awk '{print $2}' | tr -d '"')
        if [ -n "$ZONAS" ]; then
            echo "  Zonas activas :"
            while IFS= read -r zona; do
                echo "    - $zona"
            done <<< "$ZONAS"
        else
            echo "  Zonas activas : ninguna configurada"
        fi
    fi

    echo ""
}

# --- Verificar estado de SSH (Práctica 4) ---
sistema_estado_ssh() {
    info "Servidor SSH (sshd):"

    if ! pacman -Q openssh &>/dev/null; then
        echo "  Paquete openssh : NO INSTALADO"
        echo ""
        return
    fi

    if servicio_activo "sshd"; then
        echo "  Servicio      : ACTIVO"
    else
        echo "  Servicio      : INACTIVO"
    fi

    systemctl is-enabled --quiet sshd 2>/dev/null \
        && echo "  Inicio auto   : HABILITADO" \
        || echo "  Inicio auto   : DESHABILITADO"

    IP_SSH=$(ip addr show enp0s9 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    [ -n "$IP_SSH" ] && echo "  IP (enp0s9)   : $IP_SSH" || echo "  IP (enp0s9)   : sin asignar"

    PUERTO=$(ss -tlnp 2>/dev/null | grep ":22 " | awk '{print $4}')
    [ -n "$PUERTO" ] && echo "  Escuchando en : $PUERTO" || echo "  Puerto 22     : no en escucha"

    echo ""
}

# --- Diagnóstico completo: todo junto (Prácticas 1, 2, 3 y 4) ---
sistema_estado_completo() {
    clear
    echo ""
    echo "  ============================================"
    echo "       BIENVENIDO A ARCH LINUX"
    echo "  ============================================"
    echo ""
    sistema_hostname
    sistema_ip
    sistema_disco
    sistema_estado_dhcp
    sistema_estado_dns
    sistema_estado_ssh
    echo "  ============================================"
    echo ""
}
