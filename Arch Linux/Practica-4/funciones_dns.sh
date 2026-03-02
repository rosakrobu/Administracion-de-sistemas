#!/bin/bash
# ============================================================
# funciones_dns.sh
# Biblioteca de funciones para gestion del servidor DNS
# Refactorizacion de Practica3.sh
# ============================================================

# --- Instalar BIND9 ---
dns_instalar() {
    titulo "Instalacion de BIND9 (DNS)"

    if servicio_activo "named"; then
        ok "BIND9 ya esta corriendo. Se omite instalacion."
        return
    fi

    instalar_paquete "bind"
    habilitar_servicio "named"
}

# --- Configurar zona DNS ---
dns_configurar_zona() {
    titulo "Configuracion de zona DNS"

    # Obtener IP del servidor actual en enp0s8
    IP_SERVIDOR=$(ip addr show enp0s8 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [ -z "$IP_SERVIDOR" ]; then
        err "No se encontro IP en enp0s8. Configura la IP del servidor primero."
        return 1
    fi
    info "IP del servidor DNS: $IP_SERVIDOR"

    read -rp "Nombre del dominio (ej: midominio.com): " ZONA
    read -rp "IP del cliente/registro A principal (ej: 192.168.100.30): " IP_CLIENTE

    if [[ -z "$ZONA" || -z "$IP_CLIENTE" ]]; then
        err "El dominio y la IP no pueden estar vacios."
        return 1
    fi

    ARCHIVO_ZONA="/var/named/$ZONA.zone"
    CONF_LOCAL="/etc/named.conf"

    if grep -q "\"$ZONA\"" "$CONF_LOCAL" 2>/dev/null; then
        ok "La zona '$ZONA' ya existe en named.conf. Se omite."
    else
        cat >> "$CONF_LOCAL" << EOF

zone "$ZONA" IN {
    type master;
    file "$ARCHIVO_ZONA";
    allow-update { none; };
};
EOF
        ok "Zona '$ZONA' agregada a named.conf"
    fi

    if [ -f "$ARCHIVO_ZONA" ]; then
        ok "Archivo de zona '$ARCHIVO_ZONA' ya existe. Se omite."
    else
        cat > "$ARCHIVO_ZONA" << EOF
\$TTL 86400
@   IN  SOA     ns1.$ZONA. admin.$ZONA. (
                2024010101  ; Serial
                3600        ; Refresh
                1800        ; Retry
                604800      ; Expire
                86400 )     ; Minimum TTL

@   IN  NS      ns1.$ZONA.
ns1 IN  A       $IP_SERVIDOR
@   IN  A       $IP_CLIENTE
www IN  CNAME   $ZONA.
EOF
        chown named:named "$ARCHIVO_ZONA"
        ok "Archivo de zona creado: $ARCHIVO_ZONA"
    fi

    systemctl restart named
    ok "Servicio DNS reiniciado."
}

# --- Eliminar zona DNS ---
dns_eliminar_zona() {
    titulo "Eliminar zona DNS"
    read -rp "Dominio a eliminar: " ZONA_ELIMINAR
    [[ -z "$ZONA_ELIMINAR" ]] && { err "El dominio no puede estar vacio."; return; }

    local ARCHIVO="/var/named/$ZONA_ELIMINAR.zone"
    [ -f "$ARCHIVO" ] && { rm -f "$ARCHIVO"; ok "Archivo de zona eliminado."; } || info "No se encontro el archivo de zona."

    if grep -q "\"$ZONA_ELIMINAR\"" /etc/named.conf 2>/dev/null; then
        sed -i "/zone \"$ZONA_ELIMINAR\"/,/};/d" /etc/named.conf
        ok "Zona eliminada de named.conf"
    else
        info "No se encontro la zona en named.conf"
    fi

    systemctl restart named
    ok "Servicio reiniciado."
}

# --- Cambiar zona DNS ---
dns_cambiar_zona() {
    titulo "Cambiar dominio DNS"
    info "Primero se eliminara el dominio actual."
    dns_eliminar_zona
    echo ""
    info "Ahora se configurara el nuevo dominio."
    dns_configurar_zona
}

# --- Estado del DNS ---
dns_estado() {
    titulo "Estado del servicio DNS"
    servicio_activo "named" && ok "BIND9: ACTIVO" || err "BIND9: INACTIVO"
    echo ""
    read -rp "Dominio a consultar (ej: midominio.com): " DOMINIO_TEST
    nslookup "$DOMINIO_TEST" 127.0.0.1
}
