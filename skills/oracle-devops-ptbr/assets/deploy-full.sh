#!/bin/bash
# deploy-full.sh — Wrapper que chama deploy_full.py
# M&S do Brasil LTDA — contato@msbrasil.inf.br
# Usar diretamente: python scripts/deploy_full.py --env [dev|hom|prod]
set -euo pipefail
ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
[[ -f "${PROJECT_ROOT}/.env" ]] && { set -a; source "${PROJECT_ROOT}/.env"; set +a; }
command -v python3 &>/dev/null || { echo "ERRO: python3 não encontrado"; exit 1; }
python3 -c "import oracledb, yaml" 2>/dev/null || pip install -r "${SCRIPT_DIR}/requirements-devops.txt" --break-system-packages --quiet
exec python3 "${SCRIPT_DIR}/deploy_full.py" --env "${ENVIRONMENT}" --project-root "${PROJECT_ROOT}" "${@:2}"
