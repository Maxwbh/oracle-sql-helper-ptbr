#!/usr/bin/env python3
"""
deploy_ords.py — Deploy de módulos ORDS via oracledb
M&S do Brasil LTDA — contato@msbrasil.inf.br

Uso:
    python deploy_ords.py [--env dev|hom|prod] [--modulo nome_modulo]
    python deploy_ords.py --env dev
    python deploy_ords.py --env hom --modulo clientes_v2

Ordem de execução:
    1. ords/security/roles.sql
    2. ords/security/oauth_clients.sql
    3. ords/privileges/global_privileges.sql
    4. ords/modules/**/module.sql → templates.sql → handlers.sql → privileges.sql
    5. Verificação pós-deploy via DBA_ORDS_MODULES (24.4+) ou USER_ORDS_MODULES
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import oracledb

sys.path.insert(0, str(Path(__file__).parent))
from oracle_devops_utils import (
    GREEN, YELLOW, RED, CYAN, BOLD, RESET, DIM, SEP, SEP2,
    banner, carregar_dotenv, conectar, confirmar_producao,
    executar_arquivo_sql, log,
)

# Ordem canônica de execução dentro de cada módulo
PARTES_MODULO = ["module", "templates", "handlers", "privileges"]


def deploy_arquivo_opcional(
    conn: oracledb.Connection,
    arquivo: Path,
    label: str,
) -> bool:
    """Executa um arquivo SQL se existir. Retorna True se executado."""
    if not arquivo.exists():
        log.info(f"  {DIM}{label} não encontrado — pulando{RESET}")
        return False
    try:
        n = executar_arquivo_sql(conn, arquivo)
        log.info(f"  {GREEN}✓{RESET} {label} ({n} statement(s))")
        return True
    except RuntimeError as e:
        log.error(f"  {RED}✗ {label}: {e}{RESET}")
        raise


def deploy_modulo(
    conn: oracledb.Connection,
    modulo_dir: Path,
) -> None:
    """Executa as 4 partes de um módulo ORDS na ordem correta."""
    for parte in PARTES_MODULO:
        arquivo = modulo_dir / f"{parte}.sql"
        deploy_arquivo_opcional(conn, arquivo, f"{modulo_dir.name}/{parte}.sql")


def verificar_modulos(conn: oracledb.Connection) -> None:
    """
    Exibe os módulos ORDS publicados no schema alvo após o deploy.

    Usa USER_ORDS_MODULES que, após ALTER SESSION SET CURRENT_SCHEMA executado
    por conectar(), aponta para o schema alvo (não o usuário de conexão).

    Fallback para DBA_ORDS_MODULES (ORDS 24.4+) se disponível e o schema
    efetivo diferir do usuário conectado — garante visibilidade em qualquer
    configuração.
    """
    from oracle_devops_utils import schema_efetivo

    schema = schema_efetivo(conn)
    log.info(f"\n{SEP}")
    log.info(f"  {CYAN}Módulos ORDS publicados — schema: {schema}{RESET}")

    with conn.cursor() as cur:
        # Tenta DBA_ORDS_MODULES primeiro (ORDS 24.4+ — visão cross-schema)
        # Fallback para USER_ORDS_MODULES (funciona após ALTER SESSION SET CURRENT_SCHEMA)
        try:
            cur.execute("""
                SELECT name, uri_prefix, status, items_per_page
                  FROM dba_ords_modules
                 WHERE schema = :1
                 ORDER BY name
            """, [schema])
            fonte = "DBA_ORDS_MODULES"
        except oracledb.DatabaseError:
            cur.execute("""
                SELECT name, uri_prefix, status, items_per_page
                  FROM user_ords_modules
                 ORDER BY name
            """)
            fonte = "USER_ORDS_MODULES (CURRENT_SCHEMA)"

        rows = cur.fetchall()

    log.info(f"  {DIM}Fonte: {fonte}{RESET}")

    if not rows:
        log.info(f"  {YELLOW}Nenhum módulo encontrado no schema {schema}.{RESET}")
        return

    for nome, prefixo, status, items in rows:
        cor = GREEN if status == "PUBLISHED" else YELLOW
        log.info(
            f"  {cor}{'●' if status == 'PUBLISHED' else '○'}{RESET} "
            f"{nome:<30} {prefixo:<25} {cor}{status}{RESET}"
        )


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Deploy de módulos ORDS (security → privileges → modules)",
    )
    parser.add_argument("--env", default=os.environ.get("ENVIRONMENT", "dev"),
                        choices=["dev", "hom", "prod"])
    parser.add_argument("--modulo", default=None,
                        help="Deploya apenas este módulo (nome do diretório)")
    parser.add_argument("--project-root", type=Path,
                        default=Path(__file__).parent.parent)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = args.project_root.resolve()
    ords_dir = root / "ords"

    carregar_dotenv(root)
    banner("deploy_ords.py — Deploy de módulos ORDS", args.env, args.dry_run)

    if args.env == "prod":
        confirmar_producao(args.dry_run)

    if args.dry_run:
        log.info("DRY-RUN: listando o que seria executado...")
        for parte in ["security/roles.sql", "security/oauth_clients.sql",
                      "privileges/global_privileges.sql"]:
            if (ords_dir / parte).exists():
                log.info(f"  ords/{parte}")
        for d in sorted((ords_dir / "modules").iterdir()):
            if d.is_dir():
                log.info(f"  Módulo: {d.name}")
        return

    conn = conectar()

    try:
        # 1. Segurança global
        log.info(f"\n{SEP}")
        log.info(f"  {CYAN}SEGURANÇA GLOBAL{RESET}")
        for arquivo_rel in ["security/roles.sql", "security/oauth_clients.sql"]:
            deploy_arquivo_opcional(conn, ords_dir / arquivo_rel, arquivo_rel)

        # 2. Privileges globais
        log.info(f"\n{SEP}")
        log.info(f"  {CYAN}PRIVILEGES GLOBAIS{RESET}")
        priv_dir = ords_dir / "privileges"
        if priv_dir.exists():
            for arquivo in sorted(priv_dir.glob("*.sql")):
                deploy_arquivo_opcional(conn, arquivo, f"privileges/{arquivo.name}")

        # 3. Módulos
        log.info(f"\n{SEP}")
        log.info(f"  {CYAN}MÓDULOS ORDS{RESET}")
        modules_dir = ords_dir / "modules"

        if not modules_dir.exists():
            log.warning(f"  {YELLOW}ords/modules/ não encontrado.{RESET}")
        else:
            modulos = sorted(
                d for d in modules_dir.iterdir()
                if d.is_dir() and (args.modulo is None or d.name == args.modulo)
            )

            if args.modulo and not modulos:
                log.error(f"{RED}Módulo não encontrado: {args.modulo}{RESET}")
                sys.exit(1)

            for modulo_dir in modulos:
                log.info(f"\n  {BOLD}→ {modulo_dir.name}{RESET}")
                deploy_modulo(conn, modulo_dir)

        # 4. Verificação pós-deploy
        verificar_modulos(conn)

    finally:
        conn.close()

    log.info(f"\n{SEP2}")
    log.info(f"  {GREEN}✅ Deploy ORDS concluído{RESET}")
    log.info(SEP2)


if __name__ == "__main__":
    main()
