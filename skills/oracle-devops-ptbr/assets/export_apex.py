#!/usr/bin/env python3
"""
export_apex.py — Export split de aplicação APEX via SQLcl (subprocess)
M&S do Brasil LTDA — contato@msbrasil.inf.br

Uso:
    python export_apex.py [--app-id 100] [--workspace MS_BRASIL]
    python export_apex.py --app-id 100
    python export_apex.py --app-id 114 --workspace MEU_WORKSPACE

Pré-requisitos:
    - SQLcl 23.x+ no PATH (comando: sql)
    - Acesso ao banco com o schema onde o APEX está instalado

O export split permite diff granular no Git (um arquivo por componente APEX).
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import textwrap
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from oracle_devops_utils import (
    GREEN, YELLOW, RED, CYAN, BOLD, RESET, DIM, SEP2,
    banner, carregar_dotenv, log,
)


def verificar_sqlcl() -> str:
    """Verifica se SQLcl está disponível e retorna o caminho."""
    for candidato in ["sql", "sqlcl"]:
        caminho = shutil.which(candidato)
        if caminho:
            return caminho
    log.error(f"{RED}SQLcl não encontrado no PATH.{RESET}")
    log.error("Instale SQLcl: https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/")
    sys.exit(1)


def montar_script_sqlcl(
    db_conn: str,
    workspace: str,
    app_id: int,
    destino_dir: Path,
) -> str:
    """Monta o script SQLcl para export split."""
    return textwrap.dedent(f"""\
        WHENEVER SQLERROR EXIT SQL.SQLCODE

        connect {db_conn}

        apex set workspace {workspace}

        apex export \\
          -applicationid {app_id} \\
          -split \\
          -expOriginalIds \\
          -expACLAssignments \\
          -expComponentComments \\
          -expSupportingObjects Y \\
          -dir {destino_dir}

        exit
    """)


def gerar_install_sql(apex_dir: Path, app_id: int, workspace: str) -> None:
    """Gera o install.sql se não existir."""
    install = apex_dir / "install.sql"
    if install.exists():
        log.info(f"  {DIM}install.sql já existe — mantendo{RESET}")
        return

    conteudo = textwrap.dedent(f"""\
        -- install.sql — Entry point de import do APEX App {app_id}
        -- Gerado por export_apex.py — M&S do Brasil LTDA
        -- {'─' * 60}

        DEFINE APP_ID      = {app_id}
        DEFINE WORKSPACE   = {workspace}

        DECLARE
          l_wid NUMBER;
        BEGIN
          SELECT workspace_id INTO l_wid
            FROM apex_workspaces
           WHERE workspace = '&WORKSPACE.';
          APEX_UTIL.set_workspace(p_workspace => '&WORKSPACE.');
          DBMS_OUTPUT.put_line('Workspace: ' || '&WORKSPACE.');
        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Workspace não encontrado: &WORKSPACE.');
        END;
        /

        @f{app_id}/application/set_environment.sql

        PROMPT
        PROMPT APEX App {app_id} importado com sucesso.
        PROMPT
    """)
    install.write_text(conteudo, encoding="utf-8")
    log.info(f"  {GREEN}✓{RESET} install.sql gerado")


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export split de aplicação APEX via SQLcl",
    )
    parser.add_argument(
        "--app-id",
        type=int,
        default=int(os.environ.get("APEX_APP_ID", "100")),
    )
    parser.add_argument(
        "--workspace",
        default=os.environ.get("APEX_WORKSPACE", "MS_BRASIL"),
    )
    parser.add_argument("--project-root", type=Path,
                        default=Path(__file__).parent.parent)
    args = parser.parse_args()

    root = args.project_root.resolve()
    carregar_dotenv(root)

    # Configuração de banco
    db_user = os.environ.get("DB_USER", "")
    db_pass = os.environ.get("DB_PASS", "")
    db_host = os.environ.get("DB_HOST", "")
    db_port = os.environ.get("DB_PORT", "1521")
    db_svc  = os.environ.get("DB_SERVICE", "")

    for var, val in [("DB_USER", db_user), ("DB_PASS", db_pass),
                     ("DB_HOST", db_host), ("DB_SERVICE", db_svc)]:
        if not val:
            log.error(f"{RED}{var} não definido{RESET}")
            sys.exit(1)

    db_conn = f"{db_user}/{db_pass}@{db_host}:{db_port}/{db_svc}"

    apex_dir = root / "apex" / f"app_{args.app_id}"
    sqlcl = verificar_sqlcl()

    banner("export_apex.py — Export split APEX", "local")
    log.info(f"  App ID    : {CYAN}{args.app_id}{RESET}")
    log.info(f"  Workspace : {CYAN}{args.workspace}{RESET}")
    log.info(f"  Destino   : {apex_dir}")
    log.info("")

    # Backup do export anterior
    export_atual = apex_dir / f"f{args.app_id}"
    if export_atual.exists():
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = apex_dir / f"f{args.app_id}_backup_{ts}"
        shutil.move(str(export_atual), str(backup))
        log.info(f"  Backup criado: {backup.name}")

    apex_dir.mkdir(parents=True, exist_ok=True)

    # Montar e executar script SQLcl
    script = montar_script_sqlcl(db_conn, args.workspace, args.app_id, apex_dir)
    log.info("Executando SQLcl export...")

    resultado = subprocess.run(
        [sqlcl, "/nolog"],
        input=script,
        capture_output=True,
        text=True,
        timeout=300,
    )

    if resultado.returncode != 0:
        log.error(f"{RED}SQLcl falhou (exit {resultado.returncode}):{RESET}")
        log.error(resultado.stderr[-2000:] if resultado.stderr else "(sem stderr)")
        sys.exit(resultado.returncode)

    # Gerar install.sql
    log.info("")
    gerar_install_sql(apex_dir, args.app_id, args.workspace)

    # Contar arquivos exportados
    f_dir = apex_dir / f"f{args.app_id}"
    total_sql = len(list(f_dir.rglob("*.sql"))) if f_dir.exists() else 0
    paginas = len(list((f_dir / "application" / "pages").glob("*.sql"))) \
              if (f_dir / "application" / "pages").exists() else 0

    log.info(f"\n{SEP2}")
    log.info(f"  {GREEN}✅ Export concluído{RESET}")
    log.info(f"     Páginas exportadas : {paginas}")
    log.info(f"     Total arquivos SQL : {total_sql}")
    log.info(SEP2)
    log.info("")
    log.info("Próximos passos:")
    log.info(f"  git add apex/app_{args.app_id}/")
    log.info(f"  git commit -m 'apex: export split app {args.app_id} — {datetime.now().strftime(\"%Y-%m-%d\")}'")


if __name__ == "__main__":
    main()
