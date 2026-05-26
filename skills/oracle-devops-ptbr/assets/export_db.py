#!/usr/bin/env python3
"""
export_db.py — Extrai DDL do schema Oracle para estrutura db/ no Git
M&S do Brasil LTDA — contato@msbrasil.inf.br

Uso:
    python export_db.py [--schema ms_app] [--tipo all|tables|packages|...]
    python export_db.py                     # schema corrente, todos os tipos
    python export_db.py --schema ms_app     # schema específico
    python export_db.py --tipo tables       # apenas tabelas
    python export_db.py --tipo packages     # apenas packages (spec + body)

Tipos: all | tables | views | packages | procedures | functions |
       triggers | types | sequences | synonyms
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

import oracledb

sys.path.insert(0, str(Path(__file__).parent))
from oracle_devops_utils import (
    GREEN, YELLOW, RED, CYAN, BOLD, RESET, DIM, SEP, SEP2,
    banner, carregar_dotenv, conectar, log,
)

# ─── Mapeamento: tipo Oracle → (subdir, extensão) ────────────────────────────

MAPA_TIPOS: dict[str, tuple[str, str]] = {
    "TABLE":        ("tables",     "sql"),
    "VIEW":         ("views",      "vw"),
    "PROCEDURE":    ("procedures", "prc"),
    "FUNCTION":     ("functions",  "fnc"),
    "TRIGGER":      ("triggers",   "trg"),
    "TYPE":         ("types",      "typ"),
    "SEQUENCE":     ("sequences",  "sql"),
    "SYNONYM":      ("synonyms",   "sql"),
    # PACKAGE tratado à parte
}

CABECALHO_TEMPLATE = """\
-- {nome_arquivo}.{extensao}
-- Tipo   : {tipo}
-- Schema : {schema}
-- Exportado em: {data}
-- export_db.py — M&S do Brasil LTDA — contato@msbrasil.inf.br
-- ATENÇÃO: Arquivo gerado automaticamente.
--          Altere no banco e execute export_db.py para sincronizar.
-- {'─' * 60}

"""


def configurar_metadata(cur: oracledb.Cursor) -> None:
    """Configura DBMS_METADATA para DDL limpo: sem storage, sem schema prefix."""
    cur.execute("""
        BEGIN
          DBMS_METADATA.set_transform_param(
            DBMS_METADATA.session_transform, 'STORAGE',           FALSE);
          DBMS_METADATA.set_transform_param(
            DBMS_METADATA.session_transform, 'TABLESPACE',         FALSE);
          DBMS_METADATA.set_transform_param(
            DBMS_METADATA.session_transform, 'SEGMENT_ATTRIBUTES', FALSE);
          DBMS_METADATA.set_transform_param(
            DBMS_METADATA.session_transform, 'EMIT_SCHEMA',        FALSE);
          DBMS_METADATA.set_transform_param(
            DBMS_METADATA.session_transform, 'SQLTERMINATOR',      TRUE);
          DBMS_METADATA.set_transform_param(
            DBMS_METADATA.session_transform, 'PRETTY',             TRUE);
        END;
    """)


def listar_objetos(
    cur: oracledb.Cursor,
    schema: str,
    oracle_type: str,
) -> list[str]:
    """Retorna nomes dos objetos válidos do tipo no schema."""
    cur.execute(
        """
        SELECT object_name
          FROM all_objects
         WHERE owner       = :schema
           AND object_type = :tipo
           AND status      = 'VALID'
           AND object_name NOT LIKE 'BIN$%'
           AND object_name NOT LIKE 'SYS_%'
         ORDER BY object_name
        """,
        schema=schema.upper(),
        tipo=oracle_type,
    )
    return [row[0] for row in cur.fetchall()]


def obter_ddl(
    cur: oracledb.Cursor,
    oracle_type: str,
    nome: str,
    schema: str,
) -> Optional[str]:
    """Chama DBMS_METADATA.GET_DDL e retorna o DDL como string."""
    try:
        cur.execute(
            "SELECT DBMS_METADATA.get_ddl(:tipo, :nome, :schema) FROM dual",
            tipo=oracle_type,
            nome=nome,
            schema=schema.upper(),
        )
        row = cur.fetchone()
        if not row or row[0] is None:
            return None
        lob = row[0]
        return lob.read() if hasattr(lob, "read") else str(lob)
    except oracledb.DatabaseError:
        return None


def escrever_arquivo(
    destino: Path,
    ddl: str,
    nome_arquivo: str,
    extensao: str,
    tipo: str,
    schema: str,
) -> None:
    """Escreve o arquivo DDL com cabeçalho padronizado."""
    destino.parent.mkdir(parents=True, exist_ok=True)
    cabecalho = CABECALHO_TEMPLATE.format(
        nome_arquivo=nome_arquivo,
        extensao=extensao,
        tipo=tipo,
        schema=schema.upper(),
        data=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    )
    destino.write_text(cabecalho + ddl.strip() + "\n", encoding="utf-8")


def exportar_tipo(
    conn: oracledb.Connection,
    db_dir: Path,
    oracle_type: str,
    schema: str,
) -> tuple[int, int]:
    """Exporta todos os objetos de um tipo. Retorna (exportados, erros)."""
    subdir, extensao = MAPA_TIPOS[oracle_type]
    destino_dir = db_dir / subdir
    destino_dir.mkdir(parents=True, exist_ok=True)

    with conn.cursor() as cur:
        configurar_metadata(cur)
        objetos = listar_objetos(cur, schema, oracle_type)

        if not objetos:
            log.info(f"  {DIM}Nenhum {oracle_type} encontrado{RESET}")
            return 0, 0

        exportados = erros = 0
        for nome in objetos:
            nome_arquivo = nome.lower()
            arquivo = destino_dir / f"{nome_arquivo}.{extensao}"

            ddl = obter_ddl(cur, oracle_type, nome, schema)
            if not ddl:
                log.warning(f"  {YELLOW}⚠ Sem DDL: {nome}{RESET}")
                erros += 1
                continue

            escrever_arquivo(arquivo, ddl, nome_arquivo, extensao, oracle_type, schema)
            log.info(f"  {GREEN}✓{RESET} {nome_arquivo}.{extensao}")
            exportados += 1

    return exportados, erros


def exportar_packages(
    conn: oracledb.Connection,
    db_dir: Path,
    schema: str,
) -> tuple[int, int]:
    """
    Exporta packages em duas passagens:
    - spec → .pks (CREATE OR REPLACE PACKAGE)
    - body → .pkb (CREATE OR REPLACE PACKAGE BODY)
    """
    destino_dir = db_dir / "packages"
    destino_dir.mkdir(parents=True, exist_ok=True)

    with conn.cursor() as cur:
        configurar_metadata(cur)
        # Listar nomes únicos (objeto aparece como PACKAGE e PACKAGE BODY)
        cur.execute(
            """
            SELECT DISTINCT object_name
              FROM all_objects
             WHERE owner       = :schema
               AND object_type IN ('PACKAGE', 'PACKAGE BODY')
               AND object_name NOT LIKE 'BIN$%'
             ORDER BY object_name
            """,
            schema=schema.upper(),
        )
        nomes = [row[0] for row in cur.fetchall()]

    exportados = erros = 0

    for oracle_type, extensao, label in [
        ("PACKAGE",      "pks", "spec"),
        ("PACKAGE BODY", "pkb", "body"),
    ]:
        if nomes:
            log.info(f"  {CYAN}Package {label}s:{RESET}")

        with conn.cursor() as cur:
            configurar_metadata(cur)
            for nome in nomes:
                nome_arquivo = nome.lower()
                arquivo = destino_dir / f"{nome_arquivo}.{extensao}"
                ddl = obter_ddl(cur, oracle_type, nome, schema)
                if not ddl:
                    if oracle_type == "PACKAGE BODY":
                        # Body pode não existir (package sem implementação)
                        log.info(f"  {DIM}  {nome_arquivo}.{extensao} — sem body{RESET}")
                    else:
                        log.warning(f"  {YELLOW}  ⚠ Sem DDL: {nome} ({label}){RESET}")
                        erros += 1
                    continue
                escrever_arquivo(arquivo, ddl, nome_arquivo, extensao, oracle_type, schema)
                log.info(f"  {GREEN}  ✓{RESET} {nome_arquivo}.{extensao}")
                exportados += 1

    return exportados, erros


def detectar_invalidos(conn: oracledb.Connection, schema: str) -> list[str]:
    """Retorna lista de objetos INVALID no schema."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT object_type || ' ' || object_name
              FROM all_objects
             WHERE owner  = :schema
               AND status = 'INVALID'
               AND object_name NOT LIKE 'BIN$%'
             ORDER BY object_type, object_name
            """,
            schema=schema.upper(),
        )
        return [row[0] for row in cur.fetchall()]


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

TIPOS_DISPONIVEIS = ["all", "tables", "views", "packages", "procedures",
                     "functions", "triggers", "types", "sequences", "synonyms"]

MAPA_TIPO_CLI: dict[str, list[str]] = {
    "tables":     ["TABLE"],
    "views":      ["VIEW"],
    "procedures": ["PROCEDURE"],
    "functions":  ["FUNCTION"],
    "triggers":   ["TRIGGER"],
    "types":      ["TYPE"],
    "sequences":  ["SEQUENCE"],
    "synonyms":   ["SYNONYM"],
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extrai DDL do schema Oracle para estrutura db/ no Git",
    )
    parser.add_argument("--schema", default=os.environ.get("DB_USER", ""))
    parser.add_argument("--tipo", default="all", choices=TIPOS_DISPONIVEIS)
    parser.add_argument("--project-root", type=Path,
                        default=Path(__file__).parent.parent)
    args = parser.parse_args()

    root = args.project_root.resolve()
    db_dir = root / "db"

    carregar_dotenv(root)

    schema = args.schema or os.environ.get("DB_USER", "")
    if not schema:
        log.error(f"{RED}Schema não informado. Use --schema ou defina DB_USER.{RESET}")
        sys.exit(1)

    banner("export_db.py — Extração de DDL para Git", "local")
    log.info(f"  Schema : {CYAN}{schema.upper()}{RESET}")
    log.info(f"  Tipo   : {args.tipo}")
    log.info(f"  Destino: {db_dir}")
    log.info("")

    conn = conectar()
    total_ok = total_erro = 0

    try:
        if args.tipo == "all":
            for oracle_type in MAPA_TIPOS:
                if oracle_type in ("TABLE", "VIEW", "PROCEDURE", "FUNCTION",
                                   "TRIGGER", "TYPE", "SEQUENCE", "SYNONYM"):
                    label = MAPA_TIPOS[oracle_type][0]
                    log.info(f"\n{SEP}\n  {CYAN}{oracle_type}S{RESET}")
                    ok, erro = exportar_tipo(conn, db_dir, oracle_type, schema)
                    total_ok += ok; total_erro += erro

            log.info(f"\n{SEP}\n  {CYAN}PACKAGES (spec + body){RESET}")
            ok, erro = exportar_packages(conn, db_dir, schema)
            total_ok += ok; total_erro += erro

        elif args.tipo == "packages":
            ok, erro = exportar_packages(conn, db_dir, schema)
            total_ok, total_erro = ok, erro
        else:
            for oracle_type in MAPA_TIPO_CLI[args.tipo]:
                ok, erro = exportar_tipo(conn, db_dir, oracle_type, schema)
                total_ok += ok; total_erro += erro

        # Detectar objetos inválidos
        invalidos = detectar_invalidos(conn, schema)
        if invalidos:
            log.info(f"\n{YELLOW}⚠  Objetos INVÁLIDOS (não exportados):{RESET}")
            for obj in invalidos:
                log.info(f"   - {obj}")
            log.info(f"   Recompile antes de exportar → oracle-dba-ptbr")

    finally:
        conn.close()

    log.info(f"\n{SEP2}")
    log.info(f"  {GREEN}✅ Exportados : {total_ok}{RESET}")
    if total_erro:
        log.info(f"  {RED}❌ Erros      : {total_erro}{RESET}")
    log.info(SEP2)
    log.info("")
    log.info("Próximos passos:")
    log.info(f"  git add db/")
    log.info(f"  git commit -m 'db: export DDL {schema.upper()} — {datetime.now().strftime('%Y-%m-%d')}'")


if __name__ == "__main__":
    main()
