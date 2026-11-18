#!/usr/bin/env bash
# Mostra o estado da infraestrutura: rede, DNS, aplicação, serviços, logs e auditoria.
# Uso: sudo bash testes/verificar.sh

cd "$(dirname "$0")/.."
# shellcheck source=../config/citizentech.env
source config/citizentech.env

titulo() { echo; echo "==================== $* ===================="; }
ok()     { echo "  [OK]    $*"; }
falha()  { echo "  [FALHA] $*"; }

titulo "SISTEMA"
echo "  hostname: $(hostname)   fuso: $(timedatectl show -p Timezone --value 2>/dev/null)"
echo "  uptime:   $(uptime -p)"

titulo "REDE E DNS"
ip -4 -brief address | sed 's/^/  /'
echo "  rota padrao: $(ip route show default | head -n1)"
getent hosts "$SERVIDOR_DOMINIO" >/dev/null && ok "$SERVIDOR_DOMINIO resolve para $(getent hosts "$SERVIDOR_DOMINIO" | awk '{print $1}')" || falha "$SERVIDOR_DOMINIO nao resolve"
if dig +short +time=3 +tries=1 github.com | grep -q .; then ok "DNS externo funcionando (github.com)"; else falha "DNS externo"; fi
ip -4 address | grep -q "$IP_ESTATICO" && ok "IP estatico $IP_ESTATICO configurado" || falha "IP estatico $IP_ESTATICO ausente"

titulo "APLICACAO"
systemctl is-active --quiet nginx && ok "nginx ativo" || falha "nginx parado"
if curl -fsS -m 5 http://127.0.0.1/health; then echo; ok "health respondeu"; else falha "health nao respondeu"; fi
curl -fsS -m 5 http://127.0.0.1/versao.json && echo
echo "  Acesse do PC: http://$IP_ESTATICO"

titulo "MONITORAMENTO"
systemctl is-active --quiet citizentech-monitor && ok "citizentech-monitor ativo (Restart=$(systemctl show -p Restart --value citizentech-monitor))" || falha "citizentech-monitor parado"
echo "  ultimas medicoes:"
tail -n 3 "$LOG_DIR/monitor.log" 2>/dev/null | sed 's/^/    /'
echo "  ultimos alertas:"
tail -n 5 "$LOG_DIR/alertas.log" 2>/dev/null | sed 's/^/    /' || echo "    (nenhum)"

titulo "AUDITORIA"
if command -v auditctl >/dev/null; then
  auditctl -l 2>/dev/null | grep citizentech | sed 's/^/  /'
fi
echo "  log de provisionamento: $LOG_DIR/provisionamento.log ($(wc -l < "$LOG_DIR/provisionamento.log" 2>/dev/null || echo 0) linhas)"
echo
