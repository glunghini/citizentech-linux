#!/usr/bin/env bash
# Funções comuns a todos os scripts: configuração, log de execução e checagens.

set -euo pipefail

RAIZ_PROJETO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/citizentech.env
source "$RAIZ_PROJETO/config/citizentech.env"

LOG_PROVISIONAMENTO="$LOG_DIR/provisionamento.log"

exigir_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Execute com sudo: sudo $0" >&2
    exit 1
  fi
}

preparar_logs() {
  mkdir -p "$LOG_DIR"
  chmod 750 "$LOG_DIR"
  touch "$LOG_PROVISIONAMENTO"
  chmod 640 "$LOG_PROVISIONAMENTO"
}

# Registra no terminal, no arquivo de log e no journal do sistema.
# Uso: log INFO "mensagem"
log() {
  local nivel="$1"; shift
  local etapa
  etapa="$(basename "${0%.sh}")"
  local linha
  linha="$(date '+%Y-%m-%d %H:%M:%S') [$nivel] [$etapa] [usuario=${SUDO_USER:-${USER:-$(id -un)}}] $*"
  echo "$linha"
  echo "$linha" >> "$LOG_PROVISIONAMENTO"
  logger -t citizentech-provisionamento "[$nivel] [$etapa] $*" || true
}

# Executa um comando registrando início, fim e resultado.
executar() {
  log INFO "executando: $*"
  if "$@"; then
    log OK "concluido: $*"
  else
    local codigo=$?
    log ERRO "falhou (codigo $codigo): $*"
    return "$codigo"
  fi
}

instalar_pacotes() {
  export DEBIAN_FRONTEND=noninteractive
  executar apt-get install -y -q "$@"
}

# Aguarda o apt ficar livre (o Ubuntu às vezes atualiza sozinho logo após o boot).
aguardar_apt() {
  local tentativas=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if (( tentativas == 0 )); then log INFO "aguardando outro processo do apt terminar..."; fi
    tentativas=$((tentativas + 1))
    if (( tentativas > 60 )); then log ERRO "apt continua ocupado depois de 5 minutos"; return 1; fi
    sleep 5
  done
}
