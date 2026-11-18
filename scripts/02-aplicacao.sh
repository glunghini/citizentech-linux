#!/usr/bin/env bash
# Etapa 2 — Aplicação: usuários e permissões, nginx, variáveis de ambiente e publicação do portal CitizenTech.

source "$(dirname "$0")/lib.sh"
exigir_root
preparar_logs

log INFO "=== ETAPA 2: provisionamento da aplicacao web ==="

# --- Dependências -------------------------------------------------------------
aguardar_apt
instalar_pacotes nginx

# --- Usuários e permissões ----------------------------------------------------
# citizentech: usuário de sistema, sem login, dono dos arquivos da aplicação.
# Grupo citizentech: operadores que podem ler os logs sem sudo (o administrador que rodou o script entra nele).
if ! getent group citizentech >/dev/null; then
  executar groupadd --system citizentech
fi
if ! id -u citizentech >/dev/null 2>&1; then
  executar useradd --system --gid citizentech --no-create-home --home-dir "$APP_DIR" --shell /usr/sbin/nologin citizentech
fi
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  executar usermod -aG citizentech "$SUDO_USER"
fi
# Logs: root escreve, grupo citizentech lê, outros não acessam (setgid: arquivos novos herdam o grupo).
chgrp -R citizentech "$LOG_DIR"
chmod 2750 "$LOG_DIR"
find "$LOG_DIR" -type f -exec chmod 640 {} \;
log OK "usuario citizentech e grupo citizentech configurados; logs em $LOG_DIR com permissao 2750/640"

# --- Variáveis de ambiente da aplicação ----------------------------------------
mkdir -p /etc/citizentech
cat > /etc/citizentech/app.env <<EOF
# Gerado por scripts/02-aplicacao.sh
APP_NOME="$APP_NOME"
APP_VERSAO="$APP_VERSAO"
APP_DIR="$APP_DIR"
APP_URL="http://$SERVIDOR_DOMINIO"
EOF
chmod 644 /etc/citizentech/app.env
log OK "variaveis da aplicacao em /etc/citizentech/app.env"

# --- Publicação dos arquivos ---------------------------------------------------
mkdir -p "$APP_DIR"
executar cp -r "$RAIZ_PROJETO/app/." "$APP_DIR/"
echo "{\"aplicacao\":\"$APP_NOME\",\"versao\":\"$APP_VERSAO\",\"publicado_em\":\"$(date -Iseconds)\"}" > "$APP_DIR/versao.json"
# Dono: usuário citizentech; grupo www-data (o nginx) só lê; outros usuários não acessam.
chown -R citizentech:www-data "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 750 {} \;
find "$APP_DIR" -type f -exec chmod 640 {} \;
log OK "aplicacao publicada em $APP_DIR (dono citizentech, grupo www-data, 750/640)"

# --- Site no nginx -------------------------------------------------------------
executar cp "$RAIZ_PROJETO/nginx/citizentech.conf" /etc/nginx/sites-available/citizentech.conf
ln -sf /etc/nginx/sites-available/citizentech.conf /etc/nginx/sites-enabled/citizentech.conf
rm -f /etc/nginx/sites-enabled/default
executar nginx -t

# --- Tolerância a falhas: o systemd reinicia o nginx se ele cair ---------------
mkdir -p /etc/systemd/system/nginx.service.d
executar cp "$RAIZ_PROJETO/systemd/nginx-reiniciar.conf" /etc/systemd/system/nginx.service.d/citizentech-reiniciar.conf
executar systemctl daemon-reload
executar systemctl enable nginx
executar systemctl restart nginx

# --- Conferência ---------------------------------------------------------------
sleep 1
if curl -fsS -m 5 http://127.0.0.1/health >/dev/null; then
  log OK "aplicacao respondendo em http://$IP_ESTATICO e http://127.0.0.1 (health ok)"
else
  log ERRO "aplicacao nao respondeu no /health"
  exit 1
fi

log INFO "=== ETAPA 2 concluida ==="
