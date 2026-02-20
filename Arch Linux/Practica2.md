#!/bin/bash
# Practica 2 - Automatización y Gestión del Servidor DHCP
# Arch Linux
# Rosa Karina Rosas Burgueño

VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${VERDE}[OK]${NC} $1"; }
err()  { echo -e "${ROJO}[ERROR]${NC} $1"; }
info() { echo -e "${AMARILLO}[INFO]${NC} $1"; }

# Verificar
verificar_instalacion() {
    echo ""
    echo "--- Verificando instalacion DHCP ---"
    if pacman -Q dhcp &>/dev/null; then
        ok "El paquete dhcp esta instalado."
        echo ""
        info "Estado del servicio:"
        systemctl status dhcpd4 --no-pager -l
    else
        err "El paquete dhcp NO esta instalado."
    fi
    echo ""
}

# instalar
instalar_dhcp() {
    echo ""
    echo "--- Instalacion de DHCP ---"

    # Si ya esta instalado no hace nada
    if pacman -Q dhcp &>/dev/null; then
        ok "dhcp ya esta instalado, no se necesita hacer nada."
        echo ""
        return
    fi

    info "Instalando dhcp con pacman..."
    pacman -S --noconfirm dhcp

    if pacman -Q dhcp &>/dev/null; then
        ok "dhcp instalado correctamente."
    else
        err "Fallo la instalacion. Intenta manualmente: pacman -S dhcp"
        return
    fi
    echo ""
}

# validar IP
validar_ip() {
    local ip="$1"

    # Verificar formato X.X.X.X
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        err "Formato invalido. Usa el formato: X.X.X.X"
        return 1
    fi

    # Verificar que cada numero este entre 0 y 255
    IFS='.' read -r a b c d <<< "$ip"
    for num in $a $b $c $d; do
        if [[ $num -lt 0 || $num -gt 255 ]]; then
            err "Numero fuera de rango (0-255): $num"
            return 1
        fi
    done

    # No puede ser 0.0.0.0 ni 255.255.255.255
    if [[ "$ip" == "0.0.0.0" || "$ip" == "255.255.255.255" ]]; then
        err "Esa IP no es valida."
        return 1
    fi

    return 0
}

# configurar servidor
configurar_dhcp() {
    echo ""
    echo "--- Configuracion del servidor DHCP ---"
    echo ""

    # Pedir nombre del scope
    read -rp "Nombre del scope (ej: MiRed): " SCOPE
    if [[ -z "$SCOPE" ]]; then SCOPE="MiServidor"; fi

    # Pedir IP inicio del rango
    while true; do
        read -rp "IP de inicio del rango (ej: 192.168.100.50): " IP_INICIO
        validar_ip "$IP_INICIO" && break
    done

    # Pedir IP fin del rango
    while true; do
        read -rp "IP de fin del rango   (ej: 192.168.100.150): " IP_FIN
        if validar_ip "$IP_FIN"; then
            # Verificar que fin sea mayor que inicio
            IFS='.' read -r a1 b1 c1 d1 <<< "$IP_INICIO"
            IFS='.' read -r a2 b2 c2 d2 <<< "$IP_FIN"
            N1=$(( a1*16777216 + b1*65536 + c1*256 + d1 ))
            N2=$(( a2*16777216 + b2*65536 + c2*256 + d2 ))
            if [[ $N2 -gt $N1 ]]; then
                break
            else
                err "La IP final debe ser mayor que la IP inicial."
            fi
        fi
    done

    # Pedir tiempo de concesion
    while true; do
        read -rp "Tiempo de concesion en segundos (ej: 600): " LEASE
        if [[ "$LEASE" =~ ^[0-9]+$ && "$LEASE" -gt 0 ]]; then
            break
        else
            err "Ingresa un numero valido mayor a 0."
        fi
    done

    # Pedir Gateway (opcional)
    while true; do
        read -rp "Gateway/puerta de enlace (Enter para omitir): " GATEWAY
        if [[ -z "$GATEWAY" ]]; then
            info "Sin gateway configurado."
            break
        elif validar_ip "$GATEWAY"; then
            break
        fi
    done

    # Pedir DNS (opcional)
    while true; do
        read -rp "DNS principal (Enter para omitir): " DNS
        if [[ -z "$DNS" ]]; then
            info "Sin DNS configurado."
            break
        elif validar_ip "$DNS"; then
            break
        fi
    done

    # Mostrar interfaces de red disponibles
    echo ""
    info "Interfaces de red disponibles:"
    ip -br link show | grep -v "^lo"
    echo ""
    read -rp "Nombre de la interfaz para DHCP (ej: enp0s8): " INTERFAZ

    # Calcular la direccion de red (AND bit a bit)
    IFS='.' read -r a b c d     <<< "$IP_INICIO"
    # Usamos mascara /24 por defecto para redes clase C
    RED="${a}.${b}.${c}.0"
    MASCARA="255.255.255.0"
    BROADCAST="${a}.${b}.${c}.255"
    IP_SERVIDOR="${a}.${b}.${c}.$((d - 1))"
    if [[ $((d - 1)) -le 0 ]]; then IP_SERVIDOR="${a}.${b}.${c}.1"; fi

    # Mostrar resumen antes de aplicar
    echo ""
    echo "==============================="
    echo "   RESUMEN DE CONFIGURACION"
    echo "==============================="
    echo "  Scope     : $SCOPE"
    echo "  Red       : $RED/24"
    echo "  Mascara   : $MASCARA"
    echo "  Rango     : $IP_INICIO - $IP_FIN"
    echo "  Lease     : $LEASE segundos"
    echo "  Gateway   : ${GATEWAY:-"(sin gateway)"}"
    echo "  DNS       : ${DNS:-"(sin DNS)"}"
    echo "  Interfaz  : $INTERFAZ"
    echo "  IP servidor: $IP_SERVIDOR"
    echo "==============================="
    echo ""
    read -rp "¿Aplicar esta configuracion? (s/n): " CONF
    if [[ ! "$CONF" =~ ^[Ss]$ ]]; then
        info "Cancelado."
        return
    fi

    # --- Crear archivo de configuracion DHCP ---
    info "Creando /etc/dhcpd.conf ..."
    cat > /etc/dhcpd.conf << EOF
# Configuracion DHCP - $SCOPE
default-lease-time $LEASE;
max-lease-time $(( LEASE * 2 ));
authoritative;

subnet $RED netmask $MASCARA {
    range $IP_INICIO $IP_FIN;
    option subnet-mask $MASCARA;
    option broadcast-address $BROADCAST;
$(  [[ -n "$GATEWAY" ]] && echo "    option routers $GATEWAY;")
$(  [[ -n "$DNS"     ]] && echo "    option domain-name-servers $DNS;")
}
EOF
    ok "Archivo /etc/dhcpd.conf creado."

    # --- Configurar interfaz de red ---
    info "Configurando interfaz $INTERFAZ con IP $IP_SERVIDOR ..."
    ip addr flush dev "$INTERFAZ" 2>/dev/null
    ip addr add "$IP_SERVIDOR/24" dev "$INTERFAZ"
    ip link set "$INTERFAZ" up
    ok "Interfaz configurada."

    # --- Crear archivo de leases si no existe ---
    if [[ ! -f /var/lib/dhcp/dhcpd.leases ]]; then
        mkdir -p /var/lib/dhcp
        touch /var/lib/dhcp/dhcpd.leases
        ok "Archivo de leases creado."
    fi

    # --- Crear archivo de configuracion del servicio ---
    info "Configurando servicio dhcpd4 para la interfaz $INTERFAZ ..."
    mkdir -p /etc/systemd/system/dhcpd4.service.d
    cat > /etc/systemd/system/dhcpd4.service.d/interface.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dhcpd -4 -q -cf /etc/dhcpd.conf -pf /run/dhcpd4/dhcpd.pid $INTERFAZ
EOF

    # --- Iniciar servicio ---
    info "Iniciando servicio dhcpd4 ..."
    systemctl daemon-reload
    systemctl enable dhcpd4 --quiet
    systemctl restart dhcpd4

    sleep 2
    if systemctl is-active --quiet dhcpd4; then
        ok "¡Servidor DHCP activo y funcionando!"
    else
        err "El servicio no inicio. Revisa el log con: journalctl -xeu dhcpd4"
    fi
    echo ""
}

# Monitoriar concesiones a
monitorear_concesiones() {
    echo ""
    echo "--- Concesiones activas ---"
    echo ""

    LEASES="/var/lib/dhcp/dhcpd.leases"

    if [[ ! -f "$LEASES" ]]; then
        err "No se encontro el archivo de leases: $LEASES"
        info "El servidor DHCP aun no ha asignado ninguna IP."
        echo ""
        return
    fi

    # Extraer IPs activas
    echo "  IP asignada          MAC                  Hostname"
    echo "  -----------------------------------------------------------"
    awk '
        /^lease/            { ip = $2; activo = 0; mac = ""; host = "N/A" }
        /hardware ethernet/ { mac = $3; gsub(";", "", mac) }
        /client-hostname/   { host = $2; gsub(/[";]/, "", host) }
        /binding state active/ { activo = 1 }
        /^}/ {
            if (activo)
                printf "  %-20s %-20s %s\n", ip, mac, host
        }
    ' "$LEASES"

    echo ""
    TOTAL=$(grep -c "^lease" "$LEASES" 2>/dev/null || echo 0)
    ACTIVOS=$(grep -c "binding state active" "$LEASES" 2>/dev/null || echo 0)
    echo "  Total de concesiones activas: $ACTIVOS"
    echo ""
}

# 5) Monitorear estado del servidor
monitorear_estado() {
    echo ""
    echo "--- Estado del servidor DHCP ---"
    echo ""

    if pacman -Q dhcp &>/dev/null; then
        ok "Paquete dhcp: INSTALADO"
    else
        err "Paquete dhcp: NO INSTALADO"
    fi

    echo ""
    if systemctl is-active --quiet dhcpd4; then
        ok "Servicio dhcpd4: ACTIVO"
    else
        err "Servicio dhcpd4: INACTIVO"
    fi

    if systemctl is-enabled --quiet dhcpd4 2>/dev/null; then
        ok "Inicio automatico: HABILITADO"
    else
        info "Inicio automatico: deshabilitado"
    fi

    echo ""
    echo "--- Informacion detallada del servicio ---"
    systemctl status dhcpd4 --no-pager
    echo ""
}

# Apagar el servidor DHCP
apagar_dhcp() {
    echo ""
    echo "--- Apagar servidor DHCP ---"
    echo ""
    read -rp "¿Esta seguro que desea detener el servidor DHCP? (s/n): " RESP
    if [[ ! "$RESP" =~ ^[Ss]$ ]]; then
        info "Cancelado."
        echo ""
        return
    fi

    info "Deteniendo servidor DHCP..."
    systemctl stop dhcpd4

    if ! systemctl is-active --quiet dhcpd4; then
        ok "Servidor DHCP detenido exitosamente."
    else
        err "No se pudo detener el servidor."
    fi

    echo ""
    read -rp "¿Deshabilitar el inicio automatico tambien? (s/n): " DESH
    if [[ "$DESH" =~ ^[Ss]$ ]]; then
        systemctl disable dhcpd4 --quiet
        ok "Inicio automatico deshabilitado."
    fi
    echo ""
}

# Menu
menu() {
    while true; do
        clear
        echo "------------------------------------"
        echo "      Gestor Servidor DHCP"
        echo "------------------------------------"
        echo ""
        echo "  1. Verificar instalacion"
        echo "  2. Instalar servidor"
        echo "  3. Configurar DHCP"
        echo "  4. Monitorear Concesiones activas"
        echo "  5. Monitorear estado del servidor"
        echo "  6. Apagar servidor DHCP"
        echo "  0. Salir del menu"
        echo ""
        echo "------------------------------------"
        read -rp "Seleccione una opcion: " OPC
        echo ""

        case "$OPC" in
            1) verificar_instalacion ;;
            2) instalar_dhcp ;;
            3) configurar_dhcp ;;
            4) monitorear_concesiones ;;
            5) monitorear_estado ;;
            6) apagar_dhcp ;;
            0) echo "Saliendo..."; exit 0 ;;
            *) err "Opcion invalida." ;;
        esac

        read -rp "Presiona Enter para continuar: "
    done
}

menu