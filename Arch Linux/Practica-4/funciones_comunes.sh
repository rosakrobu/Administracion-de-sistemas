#!/bin/bash
# ============================================================
# funciones_comunes.sh
# Biblioteca de funciones utilitarias compartidas
# Practica 4 - Administracion de Sistemas
# Rosa Karina Rosas Burgueño
# ============================================================

# --- Colores ---
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${VERDE}[OK]${NC} $1"; }
err()  { echo -e "${ROJO}[ERROR]${NC} $1"; }
info() { echo -e "${AMARILLO}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# --- Verificar permisos de root ---
verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Este script debe ejecutarse como root."
        echo "    Usa: sudo bash main.sh"
        exit 1
    fi
    ok "Ejecutando como root."
}

# --- Validar formato de IP ---
validar_ip() {
    local ip="$1"
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        err "Formato invalido. Usa el formato: X.X.X.X"
        return 1
    fi
    IFS='.' read -r a b c d <<< "$ip"
    for num in $a $b $c $d; do
        if [[ $num -lt 0 || $num -gt 255 ]]; then
            err "Numero fuera de rango (0-255): $num"
            return 1
        fi
    done
    if [[ "$ip" == "0.0.0.0" || "$ip" == "255.255.255.255" ]]; then
        err "Esa IP no es valida para un host."
        return 1
    fi
    return 0
}

# --- Instalar paquete con pacman si no está instalado ---
instalar_paquete() {
    local paquete="$1"
    if pacman -Q "$paquete" &>/dev/null; then
        ok "Paquete '$paquete' ya esta instalado."
    else
        info "Instalando '$paquete'..."
        pacman -Sy --noconfirm "$paquete"
        if pacman -Q "$paquete" &>/dev/null; then
            ok "Paquete '$paquete' instalado correctamente."
        else
            err "Fallo la instalacion de '$paquete'."
            return 1
        fi
    fi
}

# --- Listar interfaces de red (excluyendo loopback) ---
listar_interfaces() {
    info "Interfaces de red disponibles:"
    ip -br link show | grep -v "^lo" | awk '{print "  -", $1, "["$2"]"}'
    echo ""
}

# --- Configurar IP estatica persistente via systemd-networkd ---
# Uso: configurar_ip_estatica <interfaz> <ip> <cidr>
configurar_ip_estatica() {
    local interfaz="$1"
    local ip="$2"
    local cidr="$3"

    titulo "Configurando IP estatica persistente"
    info "Interfaz : $interfaz"
    info "IP       : $ip/$cidr"

    mkdir -p /etc/systemd/network

    cat > /etc/systemd/network/20-static-${interfaz}.network << EOF
[Match]
Name=${interfaz}

[Network]
Address=${ip}/${cidr}
EOF

    # Aplicar en sesion actual tambien
    ip addr flush dev "$interfaz" 2>/dev/null
    ip addr add "${ip}/${cidr}" dev "$interfaz"
    ip link set "$interfaz" up

    systemctl enable systemd-networkd --quiet
    systemctl restart systemd-networkd
    sleep 2

    ok "IP $ip/$cidr configurada en $interfaz (persiste tras reinicio)."
}

# --- Verificar si un servicio esta activo ---
servicio_activo() {
    local servicio="$1"
    systemctl is-active --quiet "$servicio"
}

# --- Habilitar e iniciar servicio ---
habilitar_servicio() {
    local servicio="$1"
    systemctl enable "$servicio" --quiet
    systemctl start "$servicio"
    sleep 1
    if servicio_activo "$servicio"; then
        ok "Servicio '$servicio' activo y habilitado para el arranque."
    else
        err "El servicio '$servicio' no pudo iniciarse."
        info "Revisa con: journalctl -xeu $servicio"
        return 1
    fi
}
