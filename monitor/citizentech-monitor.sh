#!/usr/bin/env bash
# Monitor da infraestrutura CitizenTech (roda como serviço systemd: citizentech-monitor).
# A cada ciclo mede CPU, memória e disco, confere se a aplicação responde e registra tudo em log.
# Gera ALERTA quando um limite é ultrapassado e RECUPERACAO quando volta ao normal.
# Se a aplicação parar de responder, tenta religar o nginx sozinho.

set -uo pipefail

ARQ_CONFIG="/etc/citizentech/monitor.env"

carregar_config() {
  LIMITE_CPU=80; LIMITE_MEMORIA=80; LIMITE_DISCO=85; INTERVALO_SEGUNDOS=15; LOG_DIR=/var/log/citizentech
  # shellcheck disable=SC1090
  [[ -r "$ARQ_CONFIG" ]] && source "$ARQ_CONFIG"
  LOG_MONITOR="$LOG_DIR/monitor.log"
  LOG_ALERTAS="$LOG_DIR/alertas.log"
  mkdir -p "$LOG_DIR"
}

registrar() { # nivel mensagem
  local linha
  linha="$(date '+%Y-%m-%d %H:%M:%S') [$1] $2"
  echo "$linha" >> "$LOG_MONITOR"
  if [[ "$1" != "INFO" ]]; then
    echo "$linha" >> "$LOG_ALERTAS"
  fi
  logger -t citizentech-monitor "[$1] $2" || true
}

cpu_anterior_total=0
cpu_anterior_ocioso=0
CPU_ATUAL=0
APP_ESTADO="ok"
medir_cpu() {
  local _ user nice system idle iowait irq softirq steal total ocioso dt di
  read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  ocioso=$((idle + iowait))
  dt=$((total - cpu_anterior_total))
  di=$((ocioso - cpu_anterior_ocioso))
  cpu_anterior_total=$total
  cpu_anterior_ocioso=$ocioso
  # Resultado em variável global (uma subshell $(...) perderia os valores anteriores)
  if (( dt > 0 )); then CPU_ATUAL=$(( (100 * (dt - di)) / dt )); else CPU_ATUAL=0; fi
}

medir_memoria() {
  awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END { if (t>0) printf "%d", (100*(t-a))/t; else print 0 }' /proc/meminfo
}

medir_disco() {
  df -P / | awk 'NR==2 { gsub("%","",$5); print $5 }'
}

declare -A em_alerta=([cpu]=0 [memoria]=0 [disco]=0 [aplicacao]=0)

avaliar() { # recurso valor limite
  local recurso="$1" valor="$2" limite="$3"
  if (( valor >= limite )); then
    if (( em_alerta[$recurso] == 0 )); then
      registrar ALERTA "$recurso em ${valor}% (limite ${limite}%)"
      em_alerta[$recurso]=1
    fi
  elif (( em_alerta[$recurso] == 1 )); then
    registrar RECUPERACAO "$recurso voltou ao normal: ${valor}% (limite ${limite}%)"
    em_alerta[$recurso]=0
  fi
}

falhas_aplicacao=0
verificar_aplicacao() {
  if curl -fsS -m 3 -o /dev/null http://127.0.0.1/health 2>/dev/null; then
    if (( em_alerta[aplicacao] == 1 )); then
      registrar RECUPERACAO "aplicacao voltou a responder no /health"
      em_alerta[aplicacao]=0
    fi
    falhas_aplicacao=0
    APP_ESTADO="ok"
    return
  fi
  falhas_aplicacao=$((falhas_aplicacao + 1))
  if (( em_alerta[aplicacao] == 0 )); then
    registrar ALERTA "aplicacao nao respondeu no /health"
    em_alerta[aplicacao]=1
  fi
  if (( falhas_aplicacao >= 2 )); then
    registrar ACAO "tentando religar o nginx (systemctl restart nginx)"
    if systemctl restart nginx 2>/dev/null; then
      registrar ACAO "nginx religado pelo monitor"
    else
      registrar ALERTA "falha ao religar o nginx"
    fi
    falhas_aplicacao=0
  fi
  APP_ESTADO="falha"
}

trap 'registrar INFO "monitor encerrado (sinal recebido)"; exit 0' TERM INT

carregar_config
registrar INFO "monitor iniciado (pid $$) limites: cpu=${LIMITE_CPU}% memoria=${LIMITE_MEMORIA}% disco=${LIMITE_DISCO}% intervalo=${INTERVALO_SEGUNDOS}s"
medir_cpu
sleep 1

while true; do
  carregar_config
  medir_cpu
  cpu="$CPU_ATUAL"
  mem="$(medir_memoria)"
  disco="$(medir_disco)"
  avaliar cpu "$cpu" "$LIMITE_CPU"
  avaliar memoria "$mem" "$LIMITE_MEMORIA"
  avaliar disco "$disco" "$LIMITE_DISCO"
  verificar_aplicacao
  app="$APP_ESTADO"
  registrar INFO "cpu=${cpu}% memoria=${mem}% disco=${disco}% aplicacao=${app}"
  sleep "$INTERVALO_SEGUNDOS" &
  wait $!
done
