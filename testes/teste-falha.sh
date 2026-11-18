#!/usr/bin/env bash
# Teste de falha: derruba serviços e força alertas para mostrar a recuperação automática.
# Uso: sudo bash testes/teste-falha.sh        (leva cerca de 3 minutos)

set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
set +e   # o teste continua mesmo se um passo der erro
exigir_root
preparar_logs

ENV_MONITOR=/etc/citizentech/monitor.env
INTERVALO="$(grep '^INTERVALO_SEGUNDOS=' "$ENV_MONITOR" | cut -d= -f2)"
INTERVALO="${INTERVALO:-15}"
ESPERA_MONITOR=$(( INTERVALO * 3 + 5 ))

passo() { echo; echo ">>> $*"; log TESTE "$*"; }
estado() { printf '    %-22s %s\n' "$1" "$(systemctl is-active "$1")"; }
aplicacao() { curl -fsS -m 3 -o /dev/null http://127.0.0.1/health && echo "no ar" || echo "FORA DO AR"; }

passo "TESTE 1 - nginx morto com kill -9 (simula travamento). O systemd deve religar sozinho."
systemctl kill -s SIGKILL nginx
sleep 1
echo "    logo apos o kill:   aplicacao $(aplicacao)"
sleep 6
echo "    6 s depois:         aplicacao $(aplicacao)"
estado nginx

passo "TESTE 2 - monitor morto com kill -9. O systemd deve religar o monitor."
PID_ANTES="$(systemctl show -p MainPID --value citizentech-monitor)"
systemctl kill -s SIGKILL citizentech-monitor
sleep 7
PID_DEPOIS="$(systemctl show -p MainPID --value citizentech-monitor)"
echo "    PID antes: $PID_ANTES   PID depois: $PID_DEPOIS"
estado citizentech-monitor

passo "TESTE 3 - nginx parado com 'systemctl stop' (o systemd NAO religa). O monitor deve detectar e religar."
systemctl stop nginx
echo "    aplicacao: $(aplicacao)  (aguardando o monitor, ate ${ESPERA_MONITOR}s)"
for _ in $(seq 1 "$ESPERA_MONITOR"); do
  systemctl is-active --quiet nginx && break
  sleep 1
done
echo "    aplicacao: $(aplicacao)"
estado nginx
grep -E 'ACAO|aplicacao' "$LOG_DIR/alertas.log" | tail -n 3 | sed 's/^/    /'

passo "TESTE 4 - CPU a 100% por $ESPERA_MONITOR s. O monitor deve gerar ALERTA de CPU."
PIDS=()
for _ in $(seq 1 "$(nproc)"); do yes > /dev/null & PIDS+=("$!"); done
sleep "$ESPERA_MONITOR"
kill "${PIDS[@]}" 2>/dev/null
wait "${PIDS[@]}" 2>/dev/null
grep 'cpu' "$LOG_DIR/alertas.log" | tail -n 1 | sed 's/^/    /'

passo "TESTE 5 - limites de memoria e disco baixados para 1% (simula falta de recurso)."
cp "$ENV_MONITOR" /tmp/monitor.env.bak
sed -i -e 's/^LIMITE_MEMORIA=.*/LIMITE_MEMORIA=1/' -e 's/^LIMITE_DISCO=.*/LIMITE_DISCO=1/' "$ENV_MONITOR"
sleep "$ESPERA_MONITOR"
grep -E 'memoria|disco' "$LOG_DIR/alertas.log" | tail -n 2 | sed 's/^/    /'
cp /tmp/monitor.env.bak "$ENV_MONITOR"
echo "    limites restaurados; aguardando a RECUPERACAO..."
sleep "$ESPERA_MONITOR"

passo "RESULTADO - ultimos registros de alertas e recuperacoes"
tail -n 15 "$LOG_DIR/alertas.log" | sed 's/^/    /'
echo
echo "Servicos ao final:"
estado nginx
estado citizentech-monitor
echo "Aplicacao: $(aplicacao)"
