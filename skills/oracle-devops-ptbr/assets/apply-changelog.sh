#!/bin/bash
# apply-changelog.sh — Wrapper que chama apply_changelog.py
# M&S do Brasil LTDA — contato@msbrasil.inf.br
#
# Uso: ./scripts/apply-changelog.sh [dev|hom|prod] [--dry-run] [--status]
#
# Preferir chamar o Python diretamente quando possível:
#   python scripts/apply_changelog.py --env dev
#   python scripts/apply_changelog.py --env prod --dry-run
#   python scripts/apply_changelog.py --status
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Carregar .env se existir
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  set -a; source "${PROJECT_ROOT}/.env"; set +a
fi

# Verificar Python
if ! command -v python3 &>/dev/null; then
  echo "ERRO: python3 não encontrado no PATH."
  exit 1
fi

# Verificar dependências
if ! python3 -c "import oracledb, yaml" 2>/dev/null; then
  echo "Instalando dependências Python..."
  pip install -r "${SCRIPT_DIR}/requirements-devops.txt" \
              --break-system-packages --quiet
fi

# Montar argumentos extras (--dry-run, --status)
ARGS=()
for arg in "${@:2}"; do
  ARGS+=("$arg")
done

# Chamar Python
exec python3 "${SCRIPT_DIR}/apply_changelog.py" \
  --env "${ENVIRONMENT}" \
  --project-root "${PROJECT_ROOT}" \
  "${ARGS[@]}"
