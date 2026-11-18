#!/usr/bin/env bash
# Etapa 2 — Aplicação: instala o nginx, publica o portal CitizenTech e configura variáveis de ambiente.

source "$(dirname "$0")/lib.sh"
exigir_root
preparar_logs

log INFO "=== ETAPA 2: provisionamento da aplicacao web ==="

# --- Dependências -------------------------------------------------------------
aguardar_apt
instalar_pacotes nginx

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
chown -R www-data:www-data "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 755 {} \;
find "$APP_DIR" -type f -exec chmod 644 {} \;
log OK "aplicacao publicada em $APP_DIR"

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
