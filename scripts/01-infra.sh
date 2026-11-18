#!/usr/bin/env bash
# Etapa 1 — Infraestrutura: hostname, fuso, DNS, IP estático na rede host-only e firewall.

source "$(dirname "$0")/lib.sh"
exigir_root
preparar_logs

log INFO "=== ETAPA 1: infraestrutura de rede e sistema ==="

# --- Pacotes base -------------------------------------------------------------
aguardar_apt
executar apt-get update -q
instalar_pacotes curl dnsutils net-tools ufw psmisc logrotate

# --- Hostname e fuso horário --------------------------------------------------
executar hostnamectl set-hostname "$SERVIDOR_HOSTNAME"
executar timedatectl set-timezone "$FUSO_HORARIO"

# Nome local do servidor: citizentech.local -> IP estático
sed -i "/[[:space:]]$SERVIDOR_DOMINIO\b/d" /etc/hosts
sed -i "/^127\.0\.1\.1[[:space:]]/d" /etc/hosts
echo "127.0.1.1 $SERVIDOR_HOSTNAME" >> /etc/hosts
echo "$IP_ESTATICO $SERVIDOR_DOMINIO $SERVIDOR_HOSTNAME" >> /etc/hosts
log OK "hostname=$SERVIDOR_HOSTNAME, dominio local $SERVIDOR_DOMINIO -> $IP_ESTATICO"

# --- DNS (systemd-resolved) ---------------------------------------------------
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/citizentech.conf <<EOF
# Gerado por scripts/01-infra.sh
[Resolve]
DNS=$DNS_PRIMARIO $DNS_SECUNDARIO
FallbackDNS=9.9.9.9
EOF
executar systemctl restart systemd-resolved
log OK "DNS configurado: $DNS_PRIMARIO e $DNS_SECUNDARIO"

# --- IP estático na 2ª placa (host-only) --------------------------------------
# A 1ª placa (NAT) dá internet e tem a rota padrão. A host-only é a outra placa física.
PLACA_NAT="$(ip route show default | awk '{print $5; exit}')"
PLACA_HOSTONLY="$(ls /sys/class/net | grep -v -e '^lo$' -e "^${PLACA_NAT}\$" -e '^docker' -e '^veth' | head -n1 || true)"

if [[ -n "$PLACA_HOSTONLY" ]]; then
  cat > /etc/netplan/60-citizentech.yaml <<EOF
# Gerado por scripts/01-infra.sh — IP fixo na rede host-only do VirtualBox
network:
  version: 2
  ethernets:
    $PLACA_HOSTONLY:
      dhcp4: false
      addresses:
        - $IP_ESTATICO/$PREFIXO_REDE
EOF
  chmod 600 /etc/netplan/60-citizentech.yaml
  executar netplan apply
  log OK "IP estatico $IP_ESTATICO/$PREFIXO_REDE na placa $PLACA_HOSTONLY (NAT em $PLACA_NAT)"
else
  log AVISO "nenhuma 2a placa de rede encontrada: adicione um adaptador 'Host-only' na VM para ter IP fixo"
fi

# --- Firewall -----------------------------------------------------------------
executar ufw allow 22/tcp
executar ufw allow 80/tcp
executar ufw --force enable
log OK "firewall ativo: liberadas as portas 22 (SSH) e 80 (HTTP)"

log INFO "=== ETAPA 1 concluida ==="
