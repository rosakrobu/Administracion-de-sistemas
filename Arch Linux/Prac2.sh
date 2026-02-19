#!/bin/bash
# ============================================================
#  Practica 2 - Administracion de Servidor DHCP
#  Sistema: Arch Linux | Paquete: dhcp (isc-dhcp-server)
#  Alumna: Rosa Karina Rosas Burgueño
# ============================================================

# ── Paleta de colores ──────────────────────────────────────
C_OK='\033[0;32m'       # verde
C_WARN='\033[0;33m'     # amarillo
C_ERR='\033[0;31m'      # rojo
C_INFO='\033[0;36m'     # cian
C_BOLD='\033[1;37m'     # blanco brillante
C_RST='\033[0m'         # reset

# ── Rutas del sistema ──────────────────────────────────────
CONF_DHCP="/etc/dhcpd.conf"
LEASES_FILE="/var/lib/dhcp/dhcpd.leases"
SERVICIO="dhcpd4"

# ══════════════════════════════════════════════════════════
#  UTILIDADES
# ══════════════════════════════════════════════════════════

titulo() {
    echo -e "\n${C_BOLD}╔══════════════════════════════════════╗${C_RST}"
    echo -e "${C_BOLD}║  $1${C_RST}"
    echo -e "${C_BOLD}╚══════════════════════════════════════╝${C_RST}\n"
}

msg_ok()   { echo -e "  ${C_OK}[✔]${C_RST} $1"; }
msg_err()  { echo -e "  ${C_ERR}[✘]${C_RST} $1"; }
msg_warn() { echo -e "  ${C_WARN}[!]${C_RST} $1"; }
msg_info() { echo -e "  ${C_INFO}[→]${C_RST} $1"; }

# ── Convierte IP a entero de 32 bits ──────────────────────
ip_a_entero() {
    local ip="$1"
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    echo $(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))
}

# ── Calcula diferencia entre dos IPs ──────────────────────
diferencia_ips() {
    local e1 e2
    e1=$(ip_a_entero "$1")
    e2=$(ip_a_entero "$2")
    echo $(( e2 - e1 ))
}

# ── Mascara en bits → notacion decimal ────────────────────
bits_a_mascara() {
    local bits=$1
    local mask=0
    for ((i=0; i<bits; i++)); do
        mask=$(( mask | (1 << (31 - i)) ))
    done
    echo "$(( (mask >> 24) & 255 )).$(( (mask >> 16) & 255 )).$(( (mask >> 8) & 255 )).$(( mask & 255 ))"
}

# ── Mascara decimal → bits CIDR ───────────────────────────
mascara_a_bits() {
    local masc="$1"
    IFS='.' read -r a b c d <<< "$masc"
    local bits=0
    for oct in $a $b $c $d; do
        local n=$oct
        while [[ $n -gt 0 ]]; do
            bits=$(( bits + (n & 1) ))
            n=$(( n >> 1 ))
        done
    done
    echo $bits
}

# ── Sugiere mascara segun tamaño de rango ─────────────────
sugerir_mascara() {
    local rango=$1
    local bits=32
    local n=2
    while [[ $n -lt $(( rango + 2 )) ]]; do
        bits=$(( bits - 1 ))
        n=$(( n * 2 ))
    done
    bits_a_mascara $bits
}

# ══════════════════════════════════════════════════════════
#  VALIDACIONES
# ══════════════════════════════════════════════════════════

es_ip_valida() {
    local ip="$1"

    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || {
        msg_err "Formato incorrecto. Use X.X.X.X con numeros del 0 al 255."
        return 1
    }

    IFS='.' read -r a b c d <<< "$ip"

    for oct in $a $b $c $d; do
        [[ "$oct" -lt 0 || "$oct" -gt 255 ]] && {
            msg_err "Octeto fuera de rango: $oct (debe ser 0-255)."
            return 1
        }
        [[ "$oct" =~ ^0[0-9]+ ]] && {
            msg_err "No se permiten ceros a la izquierda (ej: 08)."
            return 1
        }
    done

    [[ "$a" -eq 0 ]]   && { msg_err "El primer octeto no puede ser 0."; return 1; }
    [[ "$d" -eq 0 ]]   && { msg_err "El ultimo octeto no puede ser 0 (reservado para red)."; return 1; }
    [[ "$a" -eq 127 ]] && { msg_err "Rango 127.x.x.x reservado para loopback."; return 1; }
    [[ "$ip" == "255.255.255.255" ]] && { msg_err "Broadcast global no es una IP asignable."; return 1; }
    [[ "$a" -ge 224 && "$a" -le 239 ]] && { msg_err "Rango 224-239.x.x.x reservado para multicast."; return 1; }
    [[ "$a" -ge 240 && "$a" -le 254 ]] && { msg_err "Rango 240-254.x.x.x reservado para uso experimental."; return 1; }

    return 0
}

es_mascara_valida() {
    local masc="$1"
    local mascaras_validas=(
        "255.0.0.0"     "255.128.0.0"   "255.192.0.0"   "255.224.0.0"
        "255.240.0.0"   "255.248.0.0"   "255.252.0.0"   "255.254.0.0"
        "255.255.0.0"   "255.255.128.0" "255.255.192.0" "255.255.224.0"
        "255.255.240.0" "255.255.248.0" "255.255.252.0" "255.255.254.0"
        "255.255.255.0" "255.255.255.128" "255.255.255.192" "255.255.255.224"
        "255.255.255.240" "255.255.255.248" "255.255.255.252"
    )
    for m in "${mascaras_validas[@]}"; do
        [[ "$masc" == "$m" ]] && return 0
    done
    msg_err "Mascara '$masc' no es valida. Ejemplo valido: 255.255.255.0"
    return 1
}

ips_misma_red() {
    local ip1="$1" ip2="$2" masc="$3"
    IFS='.' read -r a1 b1 c1 d1 <<< "$ip1"
    IFS='.' read -r a2 b2 c2 d2 <<< "$ip2"
    IFS='.' read -r ma mb mc md <<< "$masc"
    local red1="$((a1 & ma)).$((b1 & mb)).$((c1 & mc)).$((d1 & md))"
    local red2="$((a2 & ma)).$((b2 & mb)).$((c2 & mc)).$((d2 & md))"
    [[ "$red1" == "$red2" ]] && return 0
    msg_err "Las IPs no pertenecen a la misma red con la mascara indicada."
    return 1
}

# ══════════════════════════════════════════════════════════
#  FUNCION: VERIFICAR / INSTALAR
# ══════════════════════════════════════════════════════════

verificar_paquete() {
    titulo "Verificacion de Paqueteria DHCP"
    msg_info "Comprobando si 'dhcp' esta instalado en el sistema..."

    if pacman -Q dhcp &>/dev/null; then
        local version
        version=$(pacman -Q dhcp | awk '{print $2}')
        msg_ok "Paquete 'dhcp' instalado (version: $version)"

        msg_info "Estado del servicio $SERVICIO:"
        systemctl is-active --quiet "$SERVICIO" \
            && msg_ok "Servicio activo y corriendo." \
            || msg_warn "Servicio inactivo."
    else
        msg_err "El paquete 'dhcp' NO esta instalado."
        read -rp "  ¿Desea instalarlo ahora? (s/n): " resp
        [[ "$resp" =~ ^[Ss]$ ]] && instalar_paquete
    fi
}

instalar_paquete() {
    titulo "Instalacion de Servidor DHCP"

    if pacman -Q dhcp &>/dev/null; then
        msg_ok "El paquete 'dhcp' ya esta instalado. No se requiere accion."
    else
        msg_info "Descargando e instalando paquete 'dhcp' con pacman..."
        sudo pacman -S --noconfirm dhcp &>/dev/null &
        local pid=$!
        local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0
        while kill -0 $pid 2>/dev/null; do
            printf "\r  ${C_WARN}%s${C_RST} Instalando..." "${spinner:$((i % ${#spinner})):1}"
            sleep 0.1
            ((i++))
        done
        wait $pid
        echo ""

        if pacman -Q dhcp &>/dev/null; then
            msg_ok "Paquete instalado correctamente."
        else
            msg_err "La instalacion fallo. Revise su conexion o ejecute: sudo pacman -S dhcp"
            return 1
        fi
    fi

    # ¿Hay configuracion previa?
    if [[ -f "$CONF_DHCP" && -s "$CONF_DHCP" ]]; then
        msg_warn "Se encontro una configuracion previa en $CONF_DHCP"
        read -rp "  ¿Sobreescribir y reconfigurar? (s/n): " resp
        [[ "$resp" =~ ^[Ss]$ ]] && configurar_servidor || return 0
    else
        echo ""
        echo -e "  ¿Como desea continuar?"
        echo -e "    ${C_INFO}1)${C_RST} Configurar manualmente"
        echo -e "    ${C_INFO}2)${C_RST} Usar valores de practica (192.168.100.0/24)"
        read -rp "  Opcion: " opc
        case "$opc" in
            1) configurar_servidor ;;
            2) configurar_predeterminado ;;
            *) msg_warn "Opcion invalida. Saliendo sin configurar." ;;
        esac
    fi
}

# ══════════════════════════════════════════════════════════
#  FUNCION: CONFIGURAR (INTERACTIVO)
# ══════════════════════════════════════════════════════════

configurar_servidor() {
    titulo "Configuracion Dinamica del Servidor DHCP"

    # -- Nombre del ambito --
    read -rp "  Nombre descriptivo del ambito/scope: " nombre_scope
    [[ -z "$nombre_scope" ]] && nombre_scope="Mi_Red_DHCP"

    # -- Mascara --
    local mascara="" uso_mascara_manual=false
    while true; do
        read -rp "  Mascara de subred (Enter = calcular automaticamente): " mascara
        if [[ -z "$mascara" ]]; then
            break
        elif es_mascara_valida "$mascara"; then
            uso_mascara_manual=true
            break
        fi
    done

    # -- IP Inicial --
    local ip_inicio=""
    while true; do
        read -rp "  IP de inicio del rango: " ip_inicio
        es_ip_valida "$ip_inicio" && break
    done

    # -- IP Final --
    local ip_fin=""
    while true; do
        read -rp "  IP de fin del rango: " ip_fin
        if es_ip_valida "$ip_fin"; then
            local diff
            diff=$(diferencia_ips "$ip_inicio" "$ip_fin")
            if [[ $diff -le 2 ]]; then
                msg_err "El rango debe contener al menos 3 direcciones."
                continue
            fi
            if $uso_mascara_manual; then
                ips_misma_red "$ip_inicio" "$ip_fin" "$mascara" && break
            else
                mascara=$(sugerir_mascara "$diff")
                msg_info "Mascara calculada automaticamente: ${C_OK}$mascara${C_RST}"
                break
            fi
        fi
    done

    # -- Lease time --
    local lease_time=""
    while true; do
        read -rp "  Tiempo de concesion en segundos [600]: " lease_time
        [[ -z "$lease_time" ]] && lease_time=600
        [[ "$lease_time" =~ ^[0-9]+$ && "$lease_time" -gt 0 ]] && break
        msg_err "Ingrese un numero entero positivo."
    done

    # -- Gateway --
    local gateway=""
    while true; do
        read -rp "  Puerta de enlace/gateway (Enter para omitir): " gateway
        if [[ -z "$gateway" ]]; then
            msg_warn "Sin gateway definido. Los clientes no tendran salida a internet."
            break
        elif es_ip_valida "$gateway"; then
            break
        fi
    done

    # -- DNS Primario --
    local dns1=""
    while true; do
        read -rp "  DNS primario (Enter para omitir): " dns1
        [[ -z "$dns1" ]] && break
        es_ip_valida "$dns1" && break
    done

    # -- DNS Alternativo --
    local dns2=""
    if [[ -n "$dns1" ]]; then
        while true; do
            read -rp "  DNS secundario (Enter para omitir): " dns2
            [[ -z "$dns2" ]] && break
            es_ip_valida "$dns2" && break
        done
    fi

    # -- Interfaz de red --
    echo -e "\n  ${C_WARN}Interfaces de red disponibles:${C_RST}"
    ip -br link show | grep -v "^lo" | awk '{printf "    %-12s %s\n", $1, $3}'
    local interfaz=""
    read -rp "  Interfaz a usar para el servidor DHCP: " interfaz

    # -- Calcular red y broadcast --
    IFS='.' read -r a b c d <<< "$ip_inicio"
    IFS='.' read -r ma mb mc md <<< "$mascara"
    local dir_red="$((a & ma)).$((b & mb)).$((c & mc)).$((d & md))"
    local broadcast="$((a | (255-ma))).$((b | (255-mb))).$((c | (255-mc))).$((d | (255-md)))"
    local cidr
    cidr=$(mascara_a_bits "$mascara")

    # -- Resumen --
    echo -e "\n${C_BOLD}  ┌─── Resumen de configuracion ─────────────────┐${C_RST}"
    echo -e "  │  Scope      : ${C_OK}$nombre_scope${C_RST}"
    echo -e "  │  Red        : ${C_OK}$dir_red/$cidr${C_RST}"
    echo -e "  │  Rango      : ${C_OK}$ip_inicio  →  $ip_fin${C_RST}"
    echo -e "  │  Mascara    : ${C_OK}$mascara${C_RST}"
    echo -e "  │  Broadcast  : ${C_OK}$broadcast${C_RST}"
    echo -e "  │  Lease      : ${C_OK}$lease_time seg${C_RST}"
    echo -e "  │  Gateway    : ${C_OK}${gateway:-"(sin gateway)"}${C_RST}"
    echo -e "  │  DNS 1      : ${C_OK}${dns1:-"(ninguno)"}${C_RST}"
    echo -e "  │  DNS 2      : ${C_OK}${dns2:-"(ninguno)"}${C_RST}"
    echo -e "  │  Interfaz   : ${C_OK}$interfaz${C_RST}"
    echo -e "${C_BOLD}  └───────────────────────────────────────────────┘${C_RST}\n"

    read -rp "  ¿Confirmar y aplicar esta configuracion? (s/n): " confirmar
    [[ ! "$confirmar" =~ ^[Ss]$ ]] && { msg_warn "Configuracion cancelada. Volviendo..."; configurar_servidor; return; }

    _escribir_configuracion \
        "$nombre_scope" "$dir_red" "$mascara" "$broadcast" \
        "$ip_inicio" "$ip_fin" "$lease_time" \
        "$gateway" "$dns1" "$dns2" "$interfaz" "$cidr"
}

_escribir_configuracion() {
    local scope="$1" red="$2" masc="$3" bcast="$4"
    local ip_i="$5" ip_f="$6" lease="$7"
    local gw="$8" dns1="$9" dns2="${10}" iface="${11}" cidr="${12}"

    msg_info "Generando archivo $CONF_DHCP ..."

    sudo tee "$CONF_DHCP" > /dev/null <<DHCPCONF
# ──────────────────────────────────────────────────
#  Servidor DHCP - Arch Linux
#  Scope: $scope
#  Generado por dhcp_arch.sh
# ──────────────────────────────────────────────────

default-lease-time $lease;
max-lease-time $(( lease * 2 ));
authoritative;
log-facility local7;

subnet $red netmask $masc {
    range $ip_i $ip_f;
    option subnet-mask $masc;
    option broadcast-address $bcast;
$(  [[ -n "$gw"   ]] && echo "    option routers $gw;")
$(  if [[ -n "$dns1" && -n "$dns2" ]]; then
        echo "    option domain-name-servers $dns1, $dns2;"
    elif [[ -n "$dns1" ]]; then
        echo "    option domain-name-servers $dns1;"
    fi)
}
DHCPCONF

    # Configurar interfaz en /etc/conf.d/dhcpd
    msg_info "Configurando interfaz '$iface' en /etc/conf.d/dhcpd ..."
    sudo bash -c "echo 'DHCPD_ARGS=\"-4 -pf /run/dhcpd.pid\"' > /etc/conf.d/dhcpd"

    # Asignar IP estatica al servidor en la interfaz
    local ip_servidor
    ip_servidor=$(echo "$ip_i" | awk -F. '{print $1"."$2"."$3"."($4-1)}')
    [[ $(echo "$ip_i" | awk -F. '{print $4}') -le 1 ]] && ip_servidor="$red" && ip_servidor="${red%.*}.1"

    msg_info "Asignando IP $ip_servidor/$cidr a la interfaz $iface ..."
    sudo ip addr flush dev "$iface" 2>/dev/null
    sudo ip addr add "$ip_servidor/$cidr" dev "$iface"
    sudo ip link set "$iface" up

    # Habilitar y reiniciar servicio
    msg_info "Habilitando y reiniciando $SERVICIO ..."
    sudo systemctl enable "$SERVICIO" --quiet
    sudo systemctl restart "$SERVICIO"

    sleep 1
    if systemctl is-active --quiet "$SERVICIO"; then
        msg_ok "¡Servidor DHCP activo y funcionando!"
        echo ""
        sudo systemctl status "$SERVICIO" --no-pager -l
    else
        msg_err "El servicio no pudo iniciarse. Revise los logs:"
        echo "       sudo journalctl -xeu $SERVICIO"
    fi
}

configurar_predeterminado() {
    titulo "Configuracion Predeterminada (Practica)"
    msg_info "Aplicando configuracion de la practica: 192.168.100.0/24"

    sudo tee "$CONF_DHCP" > /dev/null <<'PREDEF'
# Configuracion DHCP - Practica 2
default-lease-time 600;
max-lease-time 1200;
authoritative;

subnet 192.168.100.0 netmask 255.255.255.0 {
    range 192.168.100.50 192.168.100.150;
    option routers 192.168.100.1;
    option subnet-mask 255.255.255.0;
    option broadcast-address 192.168.100.255;
    option domain-name-servers 192.168.100.1;
}
PREDEF

    sudo systemctl enable "$SERVICIO" --quiet
    sudo systemctl restart "$SERVICIO"
    sleep 1
    systemctl is-active --quiet "$SERVICIO" \
        && msg_ok "Configuracion predeterminada aplicada y servicio activo." \
        || msg_err "Servicio no inicio. Revise: journalctl -xeu $SERVICIO"
}

# ══════════════════════════════════════════════════════════
#  FUNCION: MONITOREO
# ══════════════════════════════════════════════════════════

monitorear() {
    titulo "Modulo de Monitoreo DHCP"

    if [[ ! -f "$LEASES_FILE" ]]; then
        msg_err "Archivo de leases no encontrado: $LEASES_FILE"
        msg_warn "Asegurese de que el servidor este activo y haya asignado al menos una IP."
        return 1
    fi

    echo -e "  Seleccione una opcion de monitoreo:\n"
    echo -e "    ${C_INFO}1)${C_RST} Listar todos los leases (historico)"
    echo -e "    ${C_INFO}2)${C_RST} Solo leases activos (tabla resumida)"
    echo -e "    ${C_INFO}3)${C_RST} Seguimiento en tiempo real (tail -f)"
    echo -e "    ${C_INFO}4)${C_RST} Estadisticas generales"
    echo -e "    ${C_INFO}5)${C_RST} Exportar reporte a archivo .txt"
    echo ""
    read -rp "  Opcion: " opc

    case "$opc" in
        1)
            titulo "Historico Completo de Leases"
            cat "$LEASES_FILE"
            ;;
        2)
            titulo "Leases Activos"
            printf "  %-18s %-20s %-20s %-25s\n" "IP" "MAC" "Hostname" "Vencimiento"
            echo "  $(printf '─%.0s' {1..83})"
            awk '
                /^lease/            { ip=$2; act=0; mac=""; host="N/A"; exp="" }
                /hardware ethernet/ { mac=$3; gsub(";","",mac) }
                /client-hostname/   { host=$2; gsub(/[";]/,"",host) }
                /binding state active/ { act=1 }
                /ends/ {
                    if(act) {
                        exp=$3" "$4; gsub(";","",exp)
                        printf "  %-18s %-20s %-20s %-25s\n", ip, mac, host, exp
                    }
                }
            ' "$LEASES_FILE" | sort -u
            ;;
        3)
            msg_info "Seguimiento en tiempo real. Presione Ctrl+C para salir."
            tail -f "$LEASES_FILE"
            ;;
        4)
            titulo "Estadisticas del Servidor"
            local total activos
            total=$(grep -c "^lease" "$LEASES_FILE" 2>/dev/null || echo 0)
            activos=$(grep -c "binding state active" "$LEASES_FILE" 2>/dev/null || echo 0)
            echo -e "  Total de leases registrados : ${C_OK}$total${C_RST}"
            echo -e "  Leases actualmente activos  : ${C_OK}$activos${C_RST}"
            echo ""
            msg_info "Estado del servicio:"
            systemctl is-active --quiet "$SERVICIO" \
                && echo -e "  ${C_OK}dhcpd4 → activo${C_RST}" \
                || echo -e "  ${C_ERR}dhcpd4 → inactivo${C_RST}"
            ;;
        5)
            local archivo="reporte_dhcp_$(date +%d%m%Y_%H%M%S).txt"
            {
                echo "==============================="
                echo " REPORTE DHCP - $(date)"
                echo "==============================="
                echo ""
                echo "LEASES ACTIVOS:"
                printf "%-18s %-20s %-20s %-25s\n" "IP" "MAC" "Hostname" "Vencimiento"
                echo "$(printf '─%.0s' {1..83})"
                awk '
                    /^lease/            { ip=$2; act=0; mac=""; host="N/A" }
                    /hardware ethernet/ { mac=$3; gsub(";","",mac) }
                    /client-hostname/   { host=$2; gsub(/[";]/,"",host) }
                    /binding state active/ { act=1 }
                    /ends/ {
                        if(act){ exp=$3" "$4; gsub(";","",exp)
                        printf "%-18s %-20s %-20s %-25s\n", ip, mac, host, exp }
                    }
                ' "$LEASES_FILE" | sort -u
                echo ""
                echo "TOTAL LEASES  : $(grep -c "^lease" "$LEASES_FILE")"
                echo "ACTIVOS       : $(grep -c "binding state active" "$LEASES_FILE")"
            } > "$archivo"
            msg_ok "Reporte guardado en: $archivo"
            cat "$archivo"
            ;;
        *)
            msg_err "Opcion no reconocida."
            ;;
    esac
}

# ══════════════════════════════════════════════════════════
#  FUNCION: ESTADO Y CONTROL DEL SERVICIO
# ══════════════════════════════════════════════════════════

estado_servicio() {
    titulo "Estado del Servidor DHCP"
    sudo systemctl status "$SERVICIO" --no-pager -l
}

reiniciar_servicio() {
    titulo "Reinicio del Servidor DHCP"
    if systemctl is-active --quiet "$SERVICIO"; then
        msg_info "Reiniciando servicio..."
        sudo systemctl restart "$SERVICIO"
    else
        msg_warn "El servicio no esta activo."
        read -rp "  ¿Desea iniciarlo? (s/n): " resp
        [[ "$resp" =~ ^[Ss]$ ]] && sudo systemctl start "$SERVICIO" || return 1
    fi
    sleep 1
    systemctl is-active --quiet "$SERVICIO" \
        && msg_ok "Servicio reiniciado correctamente." \
        || msg_err "El servicio no pudo reiniciarse. Revise: journalctl -xeu $SERVICIO"
}

mostrar_configuracion() {
    titulo "Configuracion Actual"
    if [[ ! -f "$CONF_DHCP" ]]; then
        msg_err "No existe archivo de configuracion en $CONF_DHCP"
        return 1
    fi
    echo -e "  ${C_WARN}Archivo:${C_RST} $CONF_DHCP\n"
    cat "$CONF_DHCP"
    echo ""
    msg_info "Estado del servicio:"
    systemctl is-active --quiet "$SERVICIO" \
        && msg_ok "dhcpd4 activo" \
        || msg_warn "dhcpd4 inactivo"
}

# ══════════════════════════════════════════════════════════
#  MENU DE AYUDA
# ══════════════════════════════════════════════════════════

mostrar_ayuda() {
    echo -e "\n${C_BOLD}Uso:${C_RST}  sudo $0 [OPCION]\n"
    echo -e "  ${C_INFO}-v, --verificar${C_RST}      Verifica si el paquete dhcp esta instalado"
    echo -e "  ${C_INFO}-i, --instalar${C_RST}       Instala y configura el servidor DHCP"
    echo -e "  ${C_INFO}-c, --configurar${C_RST}     Lanza el asistente de configuracion interactiva"
    echo -e "  ${C_INFO}-m, --monitorear${C_RST}     Modulo de monitoreo de clientes y leases"
    echo -e "  ${C_INFO}-s, --estado${C_RST}         Muestra el estado del servicio dhcpd4"
    echo -e "  ${C_INFO}-r, --reiniciar${C_RST}      Reinicia (o inicia) el servicio dhcpd4"
    echo -e "  ${C_INFO}-k, --config${C_RST}         Muestra la configuracion actual en $CONF_DHCP"
    echo -e "  ${C_INFO}-h, --ayuda${C_RST}          Muestra este mensaje\n"
}

# ══════════════════════════════════════════════════════════
#  PUNTO DE ENTRADA
# ══════════════════════════════════════════════════════════

case "$1" in
    -v | --verificar)   verificar_paquete ;;
    -i | --instalar)    instalar_paquete ;;
    -c | --configurar)  configurar_servidor ;;
    -m | --monitorear)  monitorear ;;
    -s | --estado)      estado_servicio ;;
    -r | --reiniciar)   reiniciar_servicio ;;
    -k | --config)      mostrar_configuracion ;;
    -h | --ayuda | "")  mostrar_ayuda ;;
    *)
        msg_err "Opcion desconocida: '$1'"
        mostrar_ayuda
        exit 1
        ;;
esac