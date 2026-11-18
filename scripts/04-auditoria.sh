#!/usr/bin/env bash
# Etapa 4 — Auditoria: auditd vigia mudanças nas configurações, na aplicação e no monitor.

source "$(dirname "$0")/lib.sh"
exigir_root
preparar_logs

log INFO "=== ETAPA 4: auditoria ==="

aguardar_apt
instalar_pacotes auditd

cat > /etc/audit/rules.d/citizentech.rules <<'EOF'
# Gerado por scripts/04-auditoria.sh
# Quem alterou configurações, a aplicação ou o monitor (consulte com: sudo ausearch -k <chave> -i)
-w /etc/citizentech/ -p wa -k citizentech-config
-w /etc/nginx/ -p wa -k citizentech-nginx
-w /var/www/citizentech/ -p wa -k citizentech-app
-w /usr/local/bin/citizentech-monitor.sh -p wa -k citizentech-monitor
-w /etc/systemd/system/citizentech-monitor.service -p wa -k citizentech-monitor
-w /etc/netplan/ -p wa -k citizentech-rede
EOF

executar systemctl enable auditd
executar systemctl restart auditd
executar augenrules --load
log OK "regras de auditoria carregadas: $(auditctl -l | grep -c citizentech) regras citizentech"

log INFO "=== ETAPA 4 concluida ==="
