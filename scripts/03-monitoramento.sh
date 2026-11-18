#!/usr/bin/env bash
# Etapa 3 — Monitoramento: instala o monitor de CPU, memória, disco e aplicação como serviço systemd.

source "$(dirname "$0")/lib.sh"
exigir_root
preparar_logs

log INFO "=== ETAPA 3: monitoramento como servico ==="

# Limites e intervalo ficam num arquivo próprio: o monitor relê a cada ciclo, sem reiniciar.
mkdir -p /etc/citizentech
cat > /etc/citizentech/monitor.env <<EOF
# Gerado por scripts/03-monitoramento.sh — o monitor relê este arquivo a cada ciclo
LIMITE_CPU=$LIMITE_CPU
LIMITE_MEMORIA=$LIMITE_MEMORIA
LIMITE_DISCO=$LIMITE_DISCO
INTERVALO_SEGUNDOS=$INTERVALO_SEGUNDOS
LOG_DIR=$LOG_DIR
EOF
chmod 644 /etc/citizentech/monitor.env

executar install -m 755 "$RAIZ_PROJETO/monitor/citizentech-monitor.sh" /usr/local/bin/citizentech-monitor.sh
executar install -m 644 "$RAIZ_PROJETO/systemd/citizentech-monitor.service" /etc/systemd/system/citizentech-monitor.service
executar install -m 644 "$RAIZ_PROJETO/logrotate/citizentech" /etc/logrotate.d/citizentech

executar systemctl daemon-reload
executar systemctl enable citizentech-monitor.service
executar systemctl restart citizentech-monitor.service

sleep 2
if systemctl is-active --quiet citizentech-monitor.service; then
  log OK "citizentech-monitor ativo; logs em $LOG_DIR/monitor.log e $LOG_DIR/alertas.log"
else
  log ERRO "citizentech-monitor nao iniciou (veja: journalctl -u citizentech-monitor)"
  exit 1
fi

log INFO "=== ETAPA 3 concluida ==="
