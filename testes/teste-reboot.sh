#!/usr/bin/env bash
# Teste de falha 7: reinicialização da VM. Os serviços devem voltar sozinhos no boot.
# Uso (duas vezes):
#   sudo bash testes/teste-reboot.sh     -> registra o boot atual
#   sudo reboot
#   sudo bash testes/teste-reboot.sh     -> confere a situação depois de religar

set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
set +e
exigir_root
preparar_logs

ESTADO=/var/lib/citizentech/teste-reboot
BOOT_ATUAL="$(cat /proc/sys/kernel/random/boot_id)"
estado() { printf '    %-22s inicia no boot: %-9s agora: %s\n' "$1" "$(systemctl is-enabled "$1")" "$(systemctl is-active "$1")"; }

if [[ ! -f "$ESTADO" ]]; then
  mkdir -p "$(dirname "$ESTADO")"
  echo "$BOOT_ATUAL" > "$ESTADO"
  echo; echo ">>> TESTE 7 (parte 1) - reinicializacao da VM"
  log TESTE "TESTE 7 parte 1: boot $BOOT_ATUAL registrado, aguardando reinicializacao"
  echo "    ligada desde: $(uptime -s)"
  echo
  echo "    Agora reinicie a VM:            sudo reboot"
  echo "    Depois que ela voltar, rode:    sudo bash testes/teste-reboot.sh"
  exit 0
fi

if [[ "$(cat "$ESTADO")" == "$BOOT_ATUAL" ]]; then
  echo "A VM ainda nao foi reiniciada. Rode: sudo reboot"
  exit 1
fi

echo; echo ">>> TESTE 7 (parte 2) - situacao depois da reinicializacao"
log TESTE "TESTE 7 parte 2: VM reiniciada (boot anterior $(cat "$ESTADO"), boot atual $BOOT_ATUAL)"
echo "    ligada desde: $(uptime -s)  (boot novo)"
sleep 3
estado nginx
estado citizentech-monitor
estado auditd
if curl -fsS -m 5 -o /dev/null http://127.0.0.1/health; then
  echo "    aplicacao: no ar"; log OK "TESTE 7: aplicacao no ar apos reinicializacao"
else
  echo "    aplicacao: FORA DO AR"; log ERRO "TESTE 7: aplicacao fora do ar apos reinicializacao"
fi
echo "    monitor depois do boot (monitor.log):"
grep 'monitor iniciado' "$LOG_DIR/monitor.log" | tail -n 1 | sed 's/^/      /'
tail -n 1 "$LOG_DIR/monitor.log" | sed 's/^/      /'
rm -f "$ESTADO"
