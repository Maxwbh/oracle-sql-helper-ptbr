#!/usr/bin/env python3
"""
deploy_db.py — Deploy ordenado de objetos Oracle via oracledb
M&S do Brasil LTDA — contato@msbrasil.inf.br

Uso:
    python deploy_db.py [--env dev|hom|prod] [--tipo tables|packages|...]
    python deploy_db.py --env dev
    python deploy_db.py --env hom --tipo packages

Executa os objetos do banco na ordem correta de dependências:
    sequences → types → tables → views → grants → synonyms →
    package specs (.pks) → package bodies (.pkb) →
    procedures → functions → triggers → scripts pontuais (db/scripts/)
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
    executar_arquivo_sql, log, obter_config_db,
)

# ─── Mapeamento: tipo → (subdir, extensões) ───────────────────────────────────

TIPOS = {
    "sequences":  ("sequences",  [".sql"]),
    "types":      ("types",      [".typ", ".sql"]),
    "tables":     ("tables",     [".sql"]),
    "views":      ("views",      [".vw", ".sql"]),
    "grants":     ("grants",     [".sql"]),
    "synonyms":   ("synonyms",   [".sql"]),
    "procedures": ("procedures", [".prc", ".sql"]),
    "functions":  ("functions",  [".fnc", ".sql"]),
    "triggers":   ("triggers",   [".trg", ".sql"]),
}

# Ordem canônica de deploy (respeita dependências entre objetos)
ORDEM_DEPLOY = [
    "sequences", "types", "tables", "views",
    "grants", "synonyms",
    # packages tratados à parte (spec antes do body)
    "procedures", "functions", "triggers",
]


def deploy_diretorio(
    conn: oracledb.Connection,
    db_dir: Path,
    tipo: str,
) -> tuple[int, int]:
    """
    Executa todos os arquivos SQL de um subdiretório.
    Retorna (arquivos_ok, arquivos_erro).
    """
    subdir, extensoes = TIPOS[tipo]
    diretorio = db_dir / subdir

    if not diretorio.exists():
        log.info(f"  {DIM}db/{subdir}/ não encontrado — pulando{RESET}")
        return 0, 0

    arquivos = sorted(
        f for f in diretorio.iterdir()
        if f.is_file() and f.suffix.lower() in extensoes
    )

    if not arquivos:
        log.info(f"  {DIM}db/{subdir}/ vazio — pulando{RESET}")
        return 0, 0

    ok = erro = 0
    for arquivo in arquivos:
        try:
            n = executar_arquivo_sql(conn, arquivo)
            log.info(f"  {GREEN}✓{RESET} {arquivo.name} ({n} statement(s))")
            ok += 1
        except (RuntimeError, FileNotFoundError) as e:
            log.error(f"  {RED}✗ {arquivo.name}: {e}{RESET}")
            erro += 1

    return ok, erro


def deploy_packages(
    conn: oracledb.Connection,
    db_dir: Path,
) -> tuple[int, int]:
    """
    Deploya packages em duas passagens:
      1. Specs (.pks) — declara assinaturas públicas
      2. Bodies (.pkb) — implementa
    Specs primeiro é obrigatório (body depende de spec).
    """
    pkg_dir = db_dir / "packages"
    if not pkg_dir.exists():
        log.info(f"  {DIM}db/packages/ não encontrado — pulando{RESET}")
        return 0, 0

    ok = erro = 0

    for extensao, label in [(".pks", "Package specs"), (".pkb", "Package bodies")]:
        arquivos = sorted(pkg_dir.glob(f"*{extensao}"))
        if arquivos:
            log.info(f"  {CYAN}{label}:{RESET}")
        for arquivo in arquivos:
            try:
                n = executar_arquivo_sql(conn, arquivo)
                log.info(f"  {GREEN}  ✓{RESET} {arquivo.name} ({n} statement(s))")
                ok += 1
            except (RuntimeError, FileNotFoundError) as e:
                log.error(f"  {RED}  ✗ {arquivo.name}: {e}{RESET}")
                erro += 1

    return ok, erro


def deploy_scripts_pontuais(
    conn: oracledb.Connection,
    db_dir: Path,
) -> tuple[int, int]:
    """
    Executa scripts pontuais em db/scripts/ em ordem numérica (001_, 002_...).
    Padrão GMUD: NNN_projeto_tipo_objeto.sql
    """
    scripts_dir = db_dir / "scripts"
    if not scripts_dir.exists():
        return 0, 0

    # Apenas arquivos que seguem o padrão NNN_*.sql
    import re as _re
    arquivos = sorted(
        f for f in scripts_dir.iterdir()
        if f.is_file() and f.suffix == ".sql"
        and _re.match(r"^\d{3}_", f.name)
    )

    if not arquivos:
        return 0, 0

    log.info(f"  {CYAN}Scripts pontuais (db/scripts/):{RESET}")
    ok = erro = 0
    for arquivo in arquivos:
        try:
            n = executar_arquivo_sql(conn, arquivo)
            log.info(f"  {GREEN}  ✓{RESET} {arquivo.name} ({n} statement(s))")
            ok += 1
        except (RuntimeError, FileNotFoundError) as e:
            log.error(f"  {RED}  ✗ {arquivo.name}: {e}{RESET}")
            erro += 1

    return ok, erro


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Deploy ordenado de objetos Oracle (sequences→tables→packages→triggers)",
    )
    parser.add_argument("--env", default=os.environ.get("ENVIRONMENT", "dev"),
                        choices=["dev", "hom", "prod"])
    parser.add_argument("--tipo", default="all",
                        choices=["all"] + list(TIPOS.keys()) + ["packages", "scripts"])
    parser.add_argument("--project-root", type=Path,
                        default=Path(__file__).parent.parent)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = args.project_root.resolve()
    db_dir = root / "db"

    carregar_dotenv(root)

    banner("deploy_db.py — Deploy de objetos do banco", args.env, args.dry_run)

    if args.env == "prod":
        confirmar_producao(args.dry_run)

    if args.dry_run:
        log.info("DRY-RUN: listando arquivos que seriam executados...")
        for tipo, (subdir, exts) in TIPOS.items():
            d = db_dir / subdir
            if d.exists():
                files = [f for f in sorted(d.iterdir()) if f.suffix in exts]
                if files:
                    log.info(f"  db/{subdir}/: {len(files)} arquivo(s)")
        return

    conn = conectar()
    total_ok = total_erro = 0

    try:
        if args.tipo == "all":
            for tipo in ORDEM_DEPLOY:
                log.info(f"\n{SEP}")
                log.info(f"  {CYAN}{tipo.upper()}{RESET}")
                ok, erro = deploy_diretorio(conn, db_dir, tipo)
                total_ok += ok
                total_erro += erro

            log.info(f"\n{SEP}")
            log.info(f"  {CYAN}PACKAGES (spec → body){RESET}")
            ok, erro = deploy_packages(conn, db_dir)
            total_ok += ok
            total_erro += erro

            log.info(f"\n{SEP}")
            log.info(f"  {CYAN}SCRIPTS PONTUAIS{RESET}")
            ok, erro = deploy_scripts_pontuais(conn, db_dir)
            total_ok += ok
            total_erro += erro

        elif args.tipo == "packages":
            ok, erro = deploy_packages(conn, db_dir)
            total_ok, total_erro = ok, erro
        elif args.tipo == "scripts":
            ok, erro = deploy_scripts_pontuais(conn, db_dir)
            total_ok, total_erro = ok, erro
        else:
            ok, erro = deploy_diretorio(conn, db_dir, args.tipo)
            total_ok, total_erro = ok, erro

    finally:
        conn.close()

    log.info(f"\n{SEP2}")
    log.info(f"  {GREEN}✅ Sucesso : {total_ok} arquivo(s){RESET}")
    if total_erro:
        log.info(f"  {RED}❌ Erros   : {total_erro} arquivo(s){RESET}")
        sys.exit(1)
    log.info(SEP2)


if __name__ == "__main__":
    main()
