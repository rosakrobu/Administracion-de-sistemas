#!/bin/bash
# ============================================
# Script de configuracion DNS - BIND9
# Practica 3 - Administracion de Sistemas
# Rosa Karina Rosas Burgueno
# ============================================

VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${VERDE}[OK]${NC} $1"; }
err()  { echo -e "${ROJO}[ERROR]${NC} $1"; }
info() { echo -e "${AMARILLO}[INFO]${NC} $1"; }

# Variable global de IP
IP_SERVIDOR=""

# ============================================
# BLOQUE 1: Verificar root
# ============================================
verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Este script debe ejecutarse como root."
        exit 1
    fi
    ok "Ejecutando como root."
}

# ============================================
# BLOQUE 2: Detectar IP del servidor
# ============================================
detectar_ip() {
    echo ""
    info "Interfaces disponibles:"
    ip -br addr show | grep -v "^lo"
    echo ""

    read -p "Ingresa la interfaz de red interna (ej: enp0s8): " INTERFAZ
    IP_SERVIDOR=$(ip addr show "$INTERFAZ" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

    if [ -z "$IP_SERVIDOR" ]; then
        err "No se encontro IP en $INTERFAZ."
        read -p "Ingresa la IP manualmente: " IP_SERVIDOR
    fi

    ok "IP del servidor DNS: $IP_SERVIDOR en $INTERFAZ"
}

# ============================================
# BLOQUE 3: Escribir named.conf correcto
# ============================================
escribir_named_conf() {
    info "Escribiendo /etc/named.conf..."

    cat > /etc/named.conf << EOF
// named.conf - Practica 3 DNS
// IP Servidor: $IP_SERVIDOR

options {
    directory "/var/named";
    pid-file "/run/named/named.pid";

    // Solo IPv4, desactivar IPv6 para evitar crashes
    listen-on port 53 { 127.0.0.1; $IP_SERVIDOR; };
    listen-on-v6 { none; };

    allow-query     { any; };
    allow-recursion { any; };
    allow-transfer  { any; };
    allow-update    { none; };

    // Sin DNSSEC para red interna
    dnssec-validation no;

    version none;
    hostname none;
    server-id none;
};

zone "localhost" IN {
    type master;
    file "localhost.zone";
};

zone "0.0.127.in-addr.arpa" IN {
    type master;
    file "127.0.0.zone";
};

zone "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa" IN {
    type master;
    file "localhost.ip6.zone";
};
EOF

    # Reagregar zonas existentes conservando dominios previos
    for ARCHIVO in /var/named/*.zone; do
        [ -f "$ARCHIVO" ] || continue
        ZONA=$(basename "$ARCHIVO" .zone)
        [[ "$ZONA" == "localhost" || "$ZONA" == "127.0.0" || "$ZONA" == "localhost.ip6" ]] && continue

        # Actualizar IP del ns1 en el archivo de zona
        sed -i "s/^ns1 IN  A.*/ns1 IN  A       $IP_SERVIDOR/" "$ARCHIVO"

        cat >> /etc/named.conf << EOF

zone "$ZONA" IN {
    type master;
    file "/var/named/$ZONA.zone";
    allow-update { none; };
};
EOF
        info "Zona $ZONA reagregada."
    done

    named-checkconf /etc/named.conf
    if [ $? -ne 0 ]; then
        err "Error en named.conf."
        return 1
    fi
    ok "named.conf correcto."
    return 0
}

# ============================================
# BLOQUE 4: Configurar firewall
# ============================================
configurar_firewall() {
    info "Abriendo puerto 53 en firewall..."
    iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
    iptables -C INPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport 53 -j ACCEPT
    ok "Puerto 53 abierto."
}

# ============================================
# BLOQUE 5: Iniciar BIND9
# ============================================
iniciar_bind9() {
    systemctl stop named 2>/dev/null
    sleep 1
    systemctl start named
    sleep 2

    if systemctl is-active --quiet named; then
        ok "BIND9 activo y corriendo."
        return 0
    else
        err "BIND9 no pudo iniciarse."
        journalctl -xeu named --no-pager | grep "error\|Error\|failed" | tail -5
        return 1
    fi
}

# ============================================
# OPCION 1: Instalar y configurar BIND9
# ============================================
instalar_bind9() {
    echo ""
    echo "=== Instalando y configurando BIND9 ==="

    # Instalar si no esta
    if ! pacman -Q bind &>/dev/null; then
        info "Instalando bind..."
        pacman -Sy --noconfirm bind
        [ $? -ne 0 ] && err "Fallo instalacion." && return
        ok "bind instalado."
    else
        ok "bind ya esta instalado."
    fi

    # Detectar IP si no esta definida
    [ -z "$IP_SERVIDOR" ] && detectar_ip

    # Escribir named.conf correcto
    escribir_named_conf || return

    # Configurar firewall
    configurar_firewall

    # Habilitar e iniciar
    systemctl enable named --quiet
    iniciar_bind9
}

# ============================================
# OPCION 2: Reconfigurar DNS con IP actual
# ============================================
reconfigurar_dns() {
    echo ""
    echo "=== Reconfigurando DNS ==="

    detectar_ip

    escribir_named_conf || return

    configurar_firewall

    iniciar_bind9
}

# ============================================
# OPCION 3: Agregar dominio
# ============================================
agregar_dominio() {
    echo ""
    echo "=== Agregar dominio ==="

    # Verificar que BIND9 este corriendo, si no iniciarlo
    if ! systemctl is-active --quiet named; then
        info "BIND9 no esta corriendo. Iniciando..."
        [ -z "$IP_SERVIDOR" ] && detectar_ip
        escribir_named_conf || return
        configurar_firewall
        iniciar_bind9 || return
    fi

    read -p "Nombre del dominio (ej: reprobados.com): " ZONA
    read -p "IP del cliente (ej: 192.168.100.101): " IP_CLIENTE

    [ -z "$ZONA" ] || [ -z "$IP_CLIENTE" ] && err "Dominio e IP son obligatorios." && return

    ARCHIVO_ZONA="/var/named/$ZONA.zone"

    if grep -q "zone \"$ZONA\"" /etc/named.conf 2>/dev/null; then
        info "El dominio $ZONA ya existe."
        return
    fi

    # Agregar zona a named.conf
    cat >> /etc/named.conf << EOF

zone "$ZONA" IN {
    type master;
    file "$ARCHIVO_ZONA";
    allow-update { none; };
};
EOF

    # Crear archivo de zona
    cat > "$ARCHIVO_ZONA" << EOF
\$TTL 86400
@   IN  SOA     ns1.$ZONA. admin.$ZONA. (
                2024010101  ; Serial
                3600        ; Refresh
                1800        ; Retry
                604800      ; Expire
                86400 )     ; Minimum TTL

; Servidor de nombres
@   IN  NS      ns1.$ZONA.

; Registros A
ns1 IN  A       $IP_SERVIDOR
@   IN  A       $IP_CLIENTE

; CNAME para www
www IN  CNAME   $ZONA.
EOF

    chown named:named "$ARCHIVO_ZONA"
    chmod 640 "$ARCHIVO_ZONA"

    named-checkzone "$ZONA" "$ARCHIVO_ZONA" || { err "Error en archivo de zona."; return; }
    named-checkconf /etc/named.conf || { err "Error en named.conf."; return; }

    iniciar_bind9 && ok "Dominio $ZONA → $IP_CLIENTE agregado correctamente."
}

# ============================================
# OPCION 4: Ver dominios
# ============================================
ver_dominios() {
    echo ""
    echo "=== Dominios configurados ==="

    ZONAS=$(grep "^zone" /etc/named.conf | awk '{print $2}' | tr -d '"' | \
        grep -v "arpa\|localhost\|example")

    if [ -z "$ZONAS" ]; then
        info "No hay dominios configurados."
        return
    fi

    echo "Dominios encontrados:"
    echo ""
    CONTADOR=1
    for ZONA in $ZONAS; do
        ARCHIVO="/var/named/$ZONA.zone"
        if [ -f "$ARCHIVO" ]; then
            IP=$(grep "^@" "$ARCHIVO" | grep " A " | awk '{print $4}')
            echo "  $CONTADOR. $ZONA → $IP"
        else
            echo "  $CONTADOR. $ZONA → (archivo no encontrado)"
        fi
        CONTADOR=$((CONTADOR + 1))
    done
}

# ============================================
# OPCION 5: Eliminar dominio
# ============================================
eliminar_dominio() {
    echo ""
    echo "=== Eliminar dominio ==="

    ver_dominios
    echo ""
    read -p "Dominio a eliminar: " ZONA_ELIMINAR

    [ -z "$ZONA_ELIMINAR" ] && err "El dominio no puede estar vacio." && return

    if ! grep -q "zone \"$ZONA_ELIMINAR\"" /etc/named.conf 2>/dev/null; then
        err "El dominio $ZONA_ELIMINAR no existe."
        return
    fi

    ARCHIVO_ZONA="/var/named/$ZONA_ELIMINAR.zone"
    [ -f "$ARCHIVO_ZONA" ] && rm -f "$ARCHIVO_ZONA" && ok "Archivo de zona eliminado."

    sed -i "/zone \"$ZONA_ELIMINAR\"/,/};/d" /etc/named.conf
    ok "Zona $ZONA_ELIMINAR eliminada."

    iniciar_bind9
}

# ============================================
# OPCION 6: Ver estado
# ============================================
ver_estado() {
    echo ""
    echo "=== Estado del servicio DNS ==="

    if systemctl is-active --quiet named; then
        ok "BIND9 esta corriendo."
    else
        err "BIND9 NO esta corriendo."
    fi

    echo ""
    info "Puertos escuchando:"
    ss -tulnp | grep named

    echo ""
    read -p "Dominio a consultar (ej: reprobados.com): " DOMINIO_TEST
    [ -z "$DOMINIO_TEST" ] && return

    echo ""
    nslookup "$DOMINIO_TEST" "$IP_SERVIDOR"
}

# ============================================
# MENU PRINCIPAL
# ============================================
mostrar_menu() {
    echo ""
    echo "----------------------------------"
    echo "   Configuracion DNS - BIND9"
    echo "----------------------------------"
    echo " 1. Instalar y configurar BIND9"
    echo " 2. Reconfigurar DNS con IP actual"
    echo " 3. Agregar dominio"
    echo " 4. Ver dominios configurados"
    echo " 5. Eliminar dominio"
    echo " 6. Ver estado del servicio"
    echo " 7. Salir"
    echo "----------------------------------"
    read -p " Elige una opcion: " OPCION
}

# ============================================
# INICIO
# ============================================
verificar_root

while true; do
    mostrar_menu
    case $OPCION in
        1) instalar_bind9 ;;
        2) reconfigurar_dns ;;
        3) agregar_dominio ;;
        4) ver_dominios ;;
        5) eliminar_dominio ;;
        6) ver_estado ;;
        7) echo "Saliendo..."; exit 0 ;;
        *) err "Opcion invalida." ;;
    esac
done
