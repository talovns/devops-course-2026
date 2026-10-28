#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# За один запуск открывается одно SSH-соединение (ограничение ufw limit): его использует rsync,
# проверка доступности идёт по HTTPS, а не по SSH.
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=5"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         echo "Использование: $0 [--dry-run]" >&2; exit 2 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: нет файла ${LOCAL_DIR}index.html, доставка не выполняется." >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения (в том числе в индексе)." >&2
    exit 1
fi

# 3. Синхронизация каталога ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}
RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "$SSH_CMD")
(( DRY_RUN )) && RSYNC_OPTS+=(--dry-run)
rsync "${RSYNC_OPTS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run: завершение с кодом 0 без проверки доступности
if (( DRY_RUN )); then
    echo "Пробный запуск: состояние сервера не изменено."
    exit 0
fi

# 5. Проверка доступности ${SITE_URL} (с проверкой сертификата, без -k)
if ! curl -fsS -o /dev/null --cacert "$CA_CERT" --max-time 10 "$SITE_URL/"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после доставки." >&2
    exit 1
fi

echo "Доставлено: $(git rev-parse --short HEAD)"
exit 0
