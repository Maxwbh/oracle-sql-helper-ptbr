#!/usr/bin/env python3
"""
apply_changelog.py — Aplica migrations pendentes do db/changelog.yml
M&S do Brasil LTDA — contato@msbrasil.inf.br

Uso:
    python apply_changelog.py [--env dev|hom|prod] [--dry-run] [--status]

Exemplos:
    python apply_changelog.py --env dev
    python apply_changelog.py --env prod --dry-run    # simula sem aplicar
    python apply_changelog.py --status                 # mostra estado atual
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

import yaml

# Importar utilitários compartilhados
sys.path.insert(0, str(Path(__file__).parent))
from oracle_devops_utils import (
    GREEN, YELLOW, RED, CYAN, BOLD, RESET, DIM, SEP2,
    banner, carregar_dotenv, checksum_sha256, conectar,
    confirmar_producao, executar_arquivo_sql, log,
    obter_config_db, split_oracle_sql,
)

import oracledb


# ─── Estruturas de dados ──────────────────────────────────────────────────────

@dataclass
class Migration:
    id: str
    arquivo: str
    tipo: str
    descricao: str


@dataclass
class ResultadoMigration:
    migration: Migration
    status: str          # APLICADA | PULADA | ERRO | DRY_RUN
    checksum: str = ""
    duracao_ms: int = 0
    erro: str = ""


# ─── Tabela de controle ───────────────────────────────────────────────────────

DDL_CHANGELOG_TABLE = """
BEGIN
  DECLARE l_n NUMBER;
  BEGIN
    -- Usa ALL_TABLES com CURRENT_SCHEMA para funcionar quando
    -- o usuário de conexão é diferente do schema alvo (DB_SCHEMA != DB_USER).
    -- ALTER SESSION SET CURRENT_SCHEMA já foi executado em conectar().
    SELECT COUNT(*) INTO l_n
      FROM all_tables
     WHERE table_name = 'DB_CHANGELOG'
       AND owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
    IF l_n = 0 THEN
      EXECUTE IMMEDIATE '
        CREATE TABLE db_changelog (
          id           VARCHAR2(20)   NOT NULL,
          descricao    VARCHAR2(500)  NOT NULL,
          arquivo      VARCHAR2(500)  NOT NULL,
          tipo         VARCHAR2(10)   NOT NULL,
          checksum     VARCHAR2(64)   NOT NULL,
          aplicado_em  DATE           DEFAULT SYSDATE NOT NULL,
          aplicado_por VARCHAR2(100)  DEFAULT USER    NOT NULL,
          duracao_ms   NUMBER,
          ambiente     VARCHAR2(10),
          CONSTRAINT pk_db_changelog PRIMARY KEY (id)
        )';
    END IF;
  END;
END;
"""


def garantir_tabela_changelog(conn: oracledb.Connection) -> None:
    """Cria db_changelog se não existir. Idempotente."""
    with conn.cursor() as cur:
        cur.execute(DDL_CHANGELOG_TABLE)
    conn.commit()


# ─── Parser do changelog.yml ──────────────────────────────────────────────────

def ler_changelog(changelog_path: Path) -> list[Migration]:
    """Lê e valida o changelog.yml, retornando lista ordenada de migrations."""
    if not changelog_path.exists():
        log.error(f"{RED}Não encontrado: {changelog_path}{RESET}")
        log.error("Copie assets/changelog_template.yml para db/changelog.yml")
        sys.exit(1)

    with changelog_path.open(encoding="utf-8") as f:
        dados = yaml.safe_load(f)

    if not dados or "migrations" not in dados:
        log.error(f"{RED}changelog.yml não contém a chave 'migrations'{RESET}")
        sys.exit(1)

    migrations: list[Migration] = []
    ids_vistos: set[str] = set()

    for i, entry in enumerate(dados["migrations"], start=1):
        for campo in ("id", "arquivo", "tipo", "descricao"):
            if campo not in entry:
                log.error(f"{RED}Migration #{i} sem campo obrigatório: '{campo}'{RESET}")
                sys.exit(1)

        mid = str(entry["id"]).strip()
        if mid in ids_vistos:
            log.error(f"{RED}ID duplicado no changelog.yml: '{mid}'{RESET}")
            sys.exit(1)
        ids_vistos.add(mid)

        tipo = str(entry["tipo"]).lower().strip()
        if tipo not in ("ddl", "dml", "fix"):
            log.error(f"{RED}Migration {mid}: tipo '{tipo}' inválido. Use: ddl | dml | fix{RESET}")
            sys.exit(1)

        migrations.append(Migration(
            id=mid,
            arquivo=str(entry["arquivo"]).strip(),
            tipo=tipo,
            descricao=str(entry["descricao"]).strip(),
        ))

    return migrations


# ─── Operações no db_changelog ────────────────────────────────────────────────

def buscar_checksum_aplicado(conn: oracledb.Connection, migration_id: str) -> Optional[str]:
    """Retorna checksum gravado no banco para o id, ou None se não aplicado."""
    with conn.cursor() as cur:
        cur.execute("SELECT checksum FROM db_changelog WHERE id = :1", [migration_id])
        row = cur.fetchone()
        return row[0] if row else None


def registrar_migration(
    conn: oracledb.Connection,
    migration: Migration,
    checksum: str,
    duracao_ms: int,
    ambiente: str,
) -> None:
    """Insere o registro de aplicação em db_changelog."""
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO db_changelog
                 (id, descricao, arquivo, tipo, checksum,
                  aplicado_em, aplicado_por, duracao_ms, ambiente)
               VALUES (:1, :2, :3, :4, :5, SYSDATE, USER, :6, :7)""",
            [migration.id, migration.descricao, migration.arquivo,
             migration.tipo, checksum, duracao_ms, ambiente],
        )
    conn.commit()


# ─── Processamento de migration ───────────────────────────────────────────────

def processar_migration(
    conn: oracledb.Connection,
    migration: Migration,
    db_dir: Path,
    ambiente: str,
    dry_run: bool,
) -> ResultadoMigration:
    """Processa uma migration individual. Retorna o resultado."""
    arquivo = db_dir / migration.arquivo

    if not arquivo.exists():
        return ResultadoMigration(
            migration=migration, status="ERRO",
            erro=f"Arquivo não encontrado: db/{migration.arquivo}",
        )

    checksum_atual = checksum_sha256(arquivo)
    checksum_db = buscar_checksum_aplicado(conn, migration.id)

    if checksum_db is not None:
        if checksum_db == checksum_atual:
            return ResultadoMigration(migration=migration, status="PULADA",
                                      checksum=checksum_atual)
        return ResultadoMigration(
            migration=migration, status="ERRO", checksum=checksum_atual,
            erro=(f"INTEGRIDADE: arquivo alterado após aplicação.\n"
                  f"  Banco   : {checksum_db[:16]}...\n"
                  f"  Arquivo : {checksum_atual[:16]}...\n"
                  f"  Crie uma nova migration para corrigir."),
        )

    if dry_run:
        return ResultadoMigration(migration=migration, status="DRY_RUN",
                                  checksum=checksum_atual)

    inicio = time.monotonic()
    try:
        executar_arquivo_sql(conn, arquivo)
    except (RuntimeError, FileNotFoundError) as e:
        return ResultadoMigration(migration=migration, status="ERRO",
                                  checksum=checksum_atual, erro=str(e))

    duracao_ms = int((time.monotonic() - inicio) * 1000)
    registrar_migration(conn, migration, checksum_atual, duracao_ms, ambiente)

    return ResultadoMigration(migration=migration, status="APLICADA",
                              checksum=checksum_atual, duracao_ms=duracao_ms)


# ─── Exibição de status ───────────────────────────────────────────────────────

def exibir_status(conn: oracledb.Connection, migrations: list[Migration]) -> None:
    """Exibe tabela de estado de todas as migrations."""
    log.info(f"\n{BOLD}Status das migrations:{RESET}")
    log.info("─" * 72)

    with conn.cursor() as cur:
        cur.execute("SELECT id, aplicado_em, ambiente, duracao_ms "
                    "FROM db_changelog ORDER BY aplicado_em")
        aplicadas = {row[0]: row for row in cur.fetchall()}

    pendentes = 0
    for m in migrations:
        if m.id in aplicadas:
            _, quando, amb, dur = aplicadas[m.id]
            quando_str = quando.strftime("%d/%m/%Y %H:%M") if quando else "—"
            log.info(f"  {GREEN}✅ {m.id:<10}{RESET} "
                     f"{m.descricao[:45]:<45} {quando_str}  [{amb or '—'}]  {dur or 0}ms")
        else:
            log.info(f"  {YELLOW}⏳ {m.id:<10}{RESET} {m.descricao[:45]:<45} PENDENTE")
            pendentes += 1

    log.info("─" * 72)
    log.info(f"  Total: {len(migrations)} | Aplicadas: {len(aplicadas)} | "
             f"{YELLOW}Pendentes: {pendentes}{RESET}\n")


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Aplica migrations Oracle do db/changelog.yml via oracledb",
    )
    parser.add_argument("--env", default=os.environ.get("ENVIRONMENT", "dev"),
                        choices=["dev", "hom", "prod"])
    parser.add_argument("--dry-run", action="store_true",
                        help="Simula sem aplicar migrations")
    parser.add_argument("--status", action="store_true",
                        help="Exibe estado atual das migrations e sai")
    parser.add_argument("--project-root", type=Path,
                        default=Path(__file__).parent.parent)
    args = parser.parse_args()

    root = args.project_root.resolve()
    db_dir = root / "db"
    changelog_path = db_dir / "changelog.yml"

    carregar_dotenv(root)

    banner("apply_changelog.py — Migrations do banco", args.env, args.dry_run)

    if args.env == "prod":
        confirmar_producao(args.dry_run)

    conn = conectar()

    try:
        garantir_tabela_changelog(conn)
        migrations = ler_changelog(changelog_path)
        log.info(f"  {len(migrations)} migrations em changelog.yml")

        if args.status:
            exibir_status(conn, migrations)
            return

        log.info(f"\n{'─' * 55}")

        resultados: list[ResultadoMigration] = []
        falhou = False

        for migration in migrations:
            log.info(f"  {migration.id} — {migration.descricao}")
            resultado = processar_migration(
                conn, migration, db_dir, args.env, args.dry_run)
            resultados.append(resultado)

            if resultado.status == "APLICADA":
                log.info(f"  {GREEN}✅ Aplicada{RESET} em {resultado.duracao_ms}ms  "
                         f"[{resultado.checksum[:12]}...]")
            elif resultado.status == "PULADA":
                log.info(f"  {YELLOW}⏭  Já aplicada — pulando{RESET}")
            elif resultado.status == "DRY_RUN":
                log.info(f"  {CYAN}🔍 DRY-RUN — seria aplicada{RESET}  "
                         f"[{resultado.checksum[:12]}...]")
            elif resultado.status == "ERRO":
                log.error(f"  {RED}❌ ERRO: {resultado.erro}{RESET}")
                log.error(f"  {RED}⛔ Deploy interrompido.{RESET}")
                falhou = True
                break

            log.info("")

        # Relatório final
        aplicadas = sum(1 for r in resultados if r.status == "APLICADA")
        puladas   = sum(1 for r in resultados if r.status == "PULADA")
        dry_runs  = sum(1 for r in resultados if r.status == "DRY_RUN")
        erros     = sum(1 for r in resultados if r.status == "ERRO")

        log.info(SEP2)
        log.info(f"  {GREEN}✅ Aplicadas : {aplicadas}{RESET}")
        log.info(f"  {YELLOW}⏭  Puladas   : {puladas}{RESET}")
        if dry_runs:
            log.info(f"  {CYAN}🔍 Dry-run  : {dry_runs}{RESET}")
        if erros:
            log.info(f"  {RED}❌ Erros    : {erros}{RESET}")
        log.info(SEP2)

        if aplicadas > 0 and not args.dry_run:
            log.info("\nPróximo passo: sincronizar DDL no Git:")
            log.info("  python scripts/export_db.py --schema $DB_USER")

        if falhou:
            sys.exit(1)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
