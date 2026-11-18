#!/usr/bin/env bash
# Provisionamento completo e automático do servidor CitizenTech.
# Uso (dentro da VM, na pasta do projeto):  sudo bash provisionar.sh
# Pode ser executado de novo sem problemas: cada etapa reaplica a configuração.

set -euo pipefail
cd "$(dirname "$0")"
source scripts/lib.sh
exigir_root
preparar_logs

chmod +x scripts/*.sh monitor/*.sh testes/*.sh

INICIO=$(date +%s)
log INFO "######## PROVISIONAMENTO CITIZENTECH INICIADO ########"

bash scripts/01-infra.sh
bash scripts/02-aplicacao.sh
bash scripts/03-monitoramento.sh
bash scripts/04-auditoria.sh

log INFO "######## PROVISIONAMENTO CONCLUIDO EM $(( $(date +%s) - INICIO )) s ########"
echo
bash testes/verificar.sh
