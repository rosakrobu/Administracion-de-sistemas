#!/bin/bash
# ============================================================
# funciones_dhcp.sh
# Biblioteca de funciones para gestion del servidor DHCP
# Refactorizacion de Practica2.sh
# ============================================================

# --- Verificar instalacion de DHCP ---
dhcp_verificar() {
    titulo "Verificando instalacion DHCP"
    if pacman -Q dhcp &>/dev/null; then
        ok "Paquete dhcp: INSTALADO"
        echo ""
        systemctl status dhcpd4 --no-pager -l
    else
        err "Paquete dhcp: NO INSTALADO"
    fi
}

# --- Instalar DHCP ---
dhcp_instalar() {
    titulo "Instalacion del servidor DHCP"
    instalar_paquete "dhcp"
}

# --- Configurar servidor DHCP ---
dhcp_configurar() {
    titulo "Configuracion del servidor DHCP"

    read -rp "Nombre del ambito (scope): " SCOPE
    [[ -z "$SCOPE" ]] && SCOPE="MiServidor"

    while true; do
        read -rp "IP de inicio del rango: " IP_INICIO
        validar_ip "$IP_INICIO" && break
    done

    while true; do
        read -rp "IP de fin del rango: " IP_FIN
        if validar_ip "$IP_FIN"; then
            IFS='.' read -r a1 b1 c1 d1 <<< "$IP_INICIO"
            IFS='.' read -r a2 b2 c2 d2 <<< "$IP_FIN"
            N1=$(( a1*16777216 + b1*65536 + c1*256 + d1 ))
            N2=$(( a2*16777216 + b2*65536 + c2*256 + d2 ))
            [[ $N2 -gt $N1 ]] && break || err "La IP final debe ser mayor que la IP inicial."
        fi
    done

    while true; do
        read -rp "Tiempo de concesion en segundos: " LEASE
        [[ "$LEASE" =~ ^[0-9]+$ && "$LEASE" -gt 0 ]] && break || err "Ingresa un numero valido mayor a 0."
    done

    while true; do
        read -rp "Gateway/puerta de enlace (Enter para omitir): " GATEWAY
        [[ -z "$GATEWAY" ]] && { info "Sin gateway."; break; }
        validar_ip "$GATEWAY" && break
    done

    while true; do
        read -rp "DNS principal (Enter para omitir): " DNS
        [[ -z "$DNS" ]] && { info "Sin DNS."; break; }
        validar_ip "$DNS" && break
    done

    listar_interfaces
    read -rp "Interfaz para DHCP (ej: enp0s8): " INTERFAZ

    IFS='.' read -r a b c d <<< "$IP_INICIO"
    RED="${a}.${b}.${c}.0"
    MASCARA="255.255.255.0"
    BROADCAST="${a}.${b}.${c}.255"
    IP_SERVIDOR="${a}.${b}.${c}.1"
    IP_RANGO_INICIO="${a}.${b}.${c}.$((d))"

    echo ""
    echo "-------------------------------"
    echo "   RESUMEN DE CONFIGURACION"
    echo "-------------------------------"
    echo "  Scope      : $SCOPE"
    echo "  Red        : $RED/24"
    echo "  Rango      : $IP_INICIO - $IP_FIN"
    echo "  Lease      : $LEASE segundos"
    echo "  Gateway    : ${GATEWAY:-"(sin gateway)"}"
    echo "  DNS        : ${DNS:-"(sin DNS)"}"
    echo "  Interfaz   : $INTERFAZ"
    echo "  IP servidor: $IP_SERVIDOR"
    echo "-------------------------------"

    read -rp "¿Aplicar esta configuracion? (s/n): " CONF
    [[ ! "$CONF" =~ ^[Ss]$ ]] && { info "Cancelado."; return; }

    info "Escribiendo /etc/dhcpd.conf ..."
    cat > /etc/dhcpd.conf << EOF
# Configuracion DHCP - $SCOPE
default-lease-time $LEASE;
max-lease-time $(( LEASE * 2 ));
authoritative;

subnet $RED netmask $MASCARA {
    range $IP_RANGO_INICIO $IP_FIN;
    option subnet-mask $MASCARA;
    option broadcast-address $BROADCAST;
$(  [[ -n "$GATEWAY" ]] && echo "    option routers $GATEWAY;")
$(  [[ -n "$DNS"     ]] && echo "    option domain-name-servers $DNS;")
}
EOF
    ok "Archivo /etc/dhcpd.conf creado."

    # IP estatica persistente via funcion comun
    configurar_ip_estatica "$INTERFAZ" "$IP_SERVIDOR" "24"

    [[ ! -f /var/lib/dhcp/dhcpd.leases ]] && {
        mkdir -p /var/lib/dhcp
        touch /var/lib/dhcp/dhcpd.leases
        ok "Archivo de leases creado."
    }

    mkdir -p /etc/systemd/system/dhcpd4.service.d
    cat > /etc/systemd/system/dhcpd4.service.d/interface.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dhcpd -4 -q -cf /etc/dhcpd.conf -pf /run/dhcpd4/dhcpd.pid $INTERFAZ
EOF

    systemctl daemon-reload
    habilitar_servicio "dhcpd4"
}

# --- Monitorear concesiones activas ---
dhcp_concesiones() {
    titulo "Concesiones DHCP activas"
    local LEASES="/var/lib/dhcp/dhcpd.leases"

    if [[ ! -f "$LEASES" ]]; then
        err "No se encontro el archivo de leases: $LEASES"
        return
    fi

    echo "  IP asignada          MAC                  Hostname"
    echo "  -----------------------------------------------------------"
    awk '
        /^lease/               { ip=$2; activo=0; mac=""; host="N/A" }
        /hardware ethernet/    { mac=$3; gsub(";","",mac) }
        /client-hostname/      { host=$2; gsub(/[";]/,"",host) }
        /binding state active/ { activo=1 }
        /^}/ { if(activo) printf "  %-20s %-20s %s\n", ip, mac, host }
    ' "$LEASES"
    echo ""
}

# --- Estado del servidor DHCP ---
dhcp_estado() {
    titulo "Estado del servidor DHCP"
    pacman -Q dhcp &>/dev/null && ok "Paquete dhcp: INSTALADO" || err "Paquete dhcp: NO INSTALADO"
    servicio_activo "dhcpd4" && ok "Servicio: ACTIVO" || err "Servicio: INACTIVO"
    systemctl is-enabled --quiet dhcpd4 2>/dev/null && ok "Inicio automatico: HABILITADO" || info "Inicio automatico: DESHABILITADO"
    echo ""
    systemctl status dhcpd4 --no-pager
}

# --- Apagar DHCP ---
dhcp_apagar() {
    titulo "Apagar servidor DHCP"
    read -rp "¿Seguro que desea detener el DHCP? (s/n): " RESP
    [[ ! "$RESP" =~ ^[Ss]$ ]] && { info "Cancelado."; return; }

    systemctl stop dhcpd4
    servicio_activo "dhcpd4" && err "No se pudo detener." || ok "Servidor DHCP detenido."

    read -rp "¿Deshabilitar inicio automatico? (s/n): " DESH
    [[ "$DESH" =~ ^[Ss]$ ]] && { systemctl disable dhcpd4 --quiet; ok "Inicio automatico deshabilitado."; }
}
