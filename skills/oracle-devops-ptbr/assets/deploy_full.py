#!/usr/bin/env python3
"""
deploy_full.py — Orquestrador de deploy completo: DB → APEX → ORDS
M&S do Brasil LTDA — contato@msbrasil.inf.br

Uso:
    python deploy_full.py [--env dev|hom|prod] [--dry-run] [--skip-apex] [--skip-ords]
    python deploy_full.py --env dev
    python deploy_full.py --env prod --dry-run

Ordem de execução:
    1. apply_changelog.py  (migrations pendentes do banco)
    2. export_apex.py / import APEX (se apex/app_{ID}/install.sql existir)
    3. deploy_ords.py      (módulos ORDS)
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from oracle_devops_utils import (
    GREEN, YELLOW, RED, CYAN, BOLD, RESET, DIM, SEP, SEP2,
    banner, carregar_dotenv, conectar, confirmar_producao,
    executar_arquivo_sql, log,
)


def rodar_script(
    script: str,
    args_extras: list[str],
    descricao: str,
) -> bool:
    """Executa outro script Python como subprocess. Retorna True se OK."""
    scripts_dir = Path(__file__).parent
    script_path = scripts_dir / script

    if not script_path.exists():
        log.error(f"{RED}{script} não encontrado em {scripts_dir}{RESET}")
        return False

    cmd = [sys.executable, str(script_path)] + args_extras
    log.info(f"  {CYAN}→ {' '.join(cmd[2:])}{RESET}")

    inicio = time.monotonic()
    resultado = subprocess.run(cmd, text=True)
    duracao = time.monotonic() - inicio

    if resultado.returncode == 0:
        log.info(f"  {GREEN}✓ {descricao} ({duracao:.1f}s){RESET}")
        return True
    else:
        log.error(f"  {RED}✗ {descricao} falhou (exit {resultado.returncode}){RESET}")
        return False


def importar_apex(
    conn,
    install_sql: Path,
    env: str,
    dry_run: bool,
) -> bool:
    """Importa aplicação APEX via install.sql usando oracledb."""
    if not install_sql.exists():
        log.info(f"  {DIM}install.sql não encontrado — pulando APEX{RESET}")
        return True

    if dry_run:
        log.info(f"  {CYAN}DRY-RUN: importaria {install_sql}{RESET}")
        return True

    try:
        n = executar_arquivo_sql(conn, install_sql)
        log.info(f"  {GREEN}✓ APEX importado ({n} statement(s)){RESET}")
        return True
    except RuntimeError as e:
        log.error(f"  {RED}✗ Erro no import APEX: {e}{RESET}")
        return False


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Deploy completo Oracle: changelog → APEX → ORDS",
    )
    parser.add_argument("--env", default=os.environ.get("ENVIRONMENT", "dev"),
                        choices=["dev", "hom", "prod"])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-db",   action="store_true", help="Pula changelog do banco")
    parser.add_argument("--skip-apex", action="store_true", help="Pula import APEX")
    parser.add_argument("--skip-ords", action="store_true", help="Pula deploy ORDS")
    parser.add_argument("--app-id", type=int,
                        default=int(os.environ.get("APEX_APP_ID", "100")))
    parser.add_argument("--project-root", type=Path,
                        default=Path(__file__).parent.parent)
    args = parser.parse_args()

    root = args.project_root.resolve()
    carregar_dotenv(root)

    banner("deploy_full.py — Deploy completo Oracle/APEX/ORDS", args.env, args.dry_run)

    if args.env == "prod":
        confirmar_producao(args.dry_run)

    args_comuns = [
        "--env", args.env,
        "--project-root", str(root),
    ] + (["--dry-run"] if args.dry_run else [])

    inicio_total = time.monotonic()
    etapas_ok: list[tuple[str, bool]] = []

    # ── Etapa 1: Changelog do banco ───────────────────────────────────────────
    log.info(f"\n{SEP}")
    log.info(f"  {BOLD}ETAPA 1/3 — Changelog do banco{RESET}")

    if args.skip_db:
        log.info(f"  {YELLOW}⏭  Pulado (--skip-db){RESET}")
        etapas_ok.append(("Banco (changelog)", True))
    else:
        ok = rodar_script("apply_changelog.py", args_comuns, "apply_changelog")
        etapas_ok.append(("Banco (changelog)", ok))
        if not ok:
            log.error(f"\n{RED}⛔ Etapa 1 falhou — deploy interrompido.{RESET}")
            sys.exit(1)

    # ── Etapa 2: APEX ─────────────────────────────────────────────────────────
    log.info(f"\n{SEP}")
    log.info(f"  {BOLD}ETAPA 2/3 — Import APEX (App {args.app_id}){RESET}")

    if args.skip_apex:
        log.info(f"  {YELLOW}⏭  Pulado (--skip-apex){RESET}")
        etapas_ok.append(("APEX", True))
    else:
        install_sql = root / "apex" / f"app_{args.app_id}" / "install.sql"

        if not args.dry_run:
            conn = conectar()
            try:
                ok = importar_apex(conn, install_sql, args.env, args.dry_run)
            finally:
                conn.close()
        else:
            log.info(f"  {CYAN}DRY-RUN: verificando {install_sql}{RESET}")
            ok = True

        etapas_ok.append(("APEX", ok))
        if not ok:
            log.error(f"\n{RED}⛔ Etapa 2 falhou — deploy interrompido.{RESET}")
            sys.exit(1)

    # ── Etapa 3: ORDS ─────────────────────────────────────────────────────────
    log.info(f"\n{SEP}")
    log.info(f"  {BOLD}ETAPA 3/3 — Deploy ORDS{RESET}")

    if args.skip_ords:
        log.info(f"  {YELLOW}⏭  Pulado (--skip-ords){RESET}")
        etapas_ok.append(("ORDS", True))
    else:
        ok = rodar_script("deploy_ords.py", args_comuns, "deploy_ords")
        etapas_ok.append(("ORDS", ok))
        if not ok:
            log.error(f"\n{RED}⛔ Etapa 3 falhou.{RESET}")
            sys.exit(1)

    # ── Relatório ─────────────────────────────────────────────────────────────
    duracao_total = time.monotonic() - inicio_total

    log.info(f"\n{SEP2}")
    log.info(f"  {BOLD}DEPLOY {args.env.upper()} CONCLUÍDO — {duracao_total:.1f}s{RESET}")
    for etapa, ok in etapas_ok:
        icone = f"{GREEN}✅" if ok else f"{RED}❌"
        log.info(f"  {icone}  {etapa}{RESET}")
    log.info(SEP2)


if __name__ == "__main__":
    main()
