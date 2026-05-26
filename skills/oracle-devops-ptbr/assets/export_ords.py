#!/usr/bin/env python3
"""
export_ords.py — Export do schema ORDS via oracledb + ORDS_EXPORT.export_schema()
M&S do Brasil LTDA — contato@msbrasil.inf.br

Uso:
    python export_ords.py [--schema ms_app] [--saida ords/export.sql]
    python export_ords.py
    python export_ords.py --schema outro_schema --saida /tmp/backup.sql
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

import oracledb

sys.path.insert(0, str(Path(__file__).parent))
from oracle_devops_utils import (
    GREEN, YELLOW, RED, CYAN, BOLD, RESET, SEP2,
    banner, carregar_dotenv, conectar, log,
)


def exportar_schema_ords(
    conn: oracledb.Connection,
    schema: str,
) -> str:
    """
    Chama ORDS_EXPORT.export_schema() e retorna o DDL como string.
    Usa oracledb para ler o CLOB retornado.
    """
    with conn.cursor() as cur:
        # Definir variável de saída CLOB
        clob_var = cur.var(oracledb.DB_TYPE_CLOB)

        cur.execute(
            """
            BEGIN
              :ddl := ORDS_EXPORT.export_schema(
                p_include_modules       => TRUE,
                p_include_privileges    => TRUE,
                p_include_roles         => TRUE,
                p_include_oauth         => TRUE,
                p_include_rest_objects  => TRUE,
                p_include_jwt_profiles  => TRUE,
                p_include_enable_schema => TRUE,
                p_export_date           => TRUE
              );
            END;
            """,
            ddl=clob_var,
        )

        clob = clob_var.getvalue()
        if clob is None:
            return ""

        # Ler o CLOB completo (oracledb retorna LOB object)
        return clob.read() if hasattr(clob, "read") else str(clob)


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Exporta configuração ORDS do schema via ORDS_EXPORT",
    )
    parser.add_argument(
        "--schema",
        default=os.environ.get("DB_USER", ""),
        help="Schema Oracle a exportar (default: DB_USER)",
    )
    parser.add_argument(
        "--saida",
        type=Path,
        default=None,
        help="Arquivo de saída (default: ords/export_{schema}_{timestamp}.sql)",
    )
    parser.add_argument("--project-root", type=Path,
                        default=Path(__file__).parent.parent)
    args = parser.parse_args()

    root = args.project_root.resolve()
    carregar_dotenv(root)

    schema = args.schema or os.environ.get("DB_USER", "")
    if not schema:
        log.error(f"{RED}Schema não informado. Use --schema ou defina DB_USER.{RESET}")
        sys.exit(1)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    saida = args.saida or (root / "ords" / f"export_{schema.lower()}_{timestamp}.sql")
    saida.parent.mkdir(parents=True, exist_ok=True)

    banner("export_ords.py — Export do schema ORDS", "local")
    log.info(f"  Schema : {CYAN}{schema.upper()}{RESET}")
    log.info(f"  Saída  : {saida}")
    log.info("")

    conn = conectar()

    try:
        log.info("Executando ORDS_EXPORT.export_schema()...")
        ddl = exportar_schema_ords(conn, schema)

        if not ddl.strip():
            log.warning(f"{YELLOW}Export vazio — schema sem configuração ORDS?{RESET}")
            sys.exit(0)

        # Escrever arquivo com cabeçalho
        cabecalho = (
            f"-- Export ORDS — schema {schema.upper()}\n"
            f"-- Gerado em: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"-- por export_ords.py — M&S do Brasil LTDA\n"
            f"-- {'─' * 60}\n\n"
        )

        saida.write_text(cabecalho + ddl, encoding="utf-8")

        tamanho_kb = saida.stat().st_size / 1024
        log.info(f"\n{GREEN}✅ Export gerado: {saida} ({tamanho_kb:.1f} KB){RESET}")

    finally:
        conn.close()

    log.info("")
    log.info("Próximos passos:")
    log.info(f"  git add ords/")
    log.info(f"  git commit -m 'ords: export schema {schema.upper()} — {datetime.now().strftime('%Y-%m-%d')}'")


if __name__ == "__main__":
    main()
