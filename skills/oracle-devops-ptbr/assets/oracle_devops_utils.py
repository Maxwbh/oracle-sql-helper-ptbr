"""
oracle_devops_utils.py — Utilitários compartilhados para scripts DevOps Oracle
M&S do Brasil LTDA — contato@msbrasil.inf.br

Importado por todos os scripts Python do projeto:
    from oracle_devops_utils import conectar, executar_arquivo_sql, log, ...
"""

from __future__ import annotations

import hashlib
import logging
import os
import re
import sys
from pathlib import Path
from typing import Optional

import oracledb

# ─── Logging ──────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("oracle_devops")

# ─── Cores para terminal ──────────────────────────────────────────────────────

_TTY = sys.stdout.isatty()
GREEN  = "\033[92m" if _TTY else ""
YELLOW = "\033[93m" if _TTY else ""
RED    = "\033[91m" if _TTY else ""
CYAN   = "\033[96m" if _TTY else ""
BOLD   = "\033[1m"  if _TTY else ""
RESET  = "\033[0m"  if _TTY else ""
DIM    = "\033[2m"  if _TTY else ""

SEP    = f"{DIM}{'─' * 55}{RESET}"
SEP2   = f"{BOLD}{'═' * 55}{RESET}"

# ─── Variáveis de ambiente ────────────────────────────────────────────────────

def carregar_dotenv(root: Path) -> None:
    """Carrega .env sem dependência de python-dotenv."""
    env_file = root / ".env"
    if not env_file.exists():
        return
    for linha in env_file.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, _, valor = linha.partition("=")
        os.environ.setdefault(chave.strip(), valor.strip().strip('"').strip("'"))


def obter_config_db() -> dict:
    """Lê configuração do banco das variáveis de ambiente. Falha com mensagem clara."""
    obrigatorios = ["DB_HOST", "DB_PORT", "DB_SERVICE", "DB_USER", "DB_PASS"]
    ausentes = [v for v in obrigatorios if not os.environ.get(v)]
    if ausentes:
        log.error(f"{RED}Variáveis não definidas: {', '.join(ausentes)}{RESET}")
        log.error("Configure .env ou exporte as variáveis antes de executar.")
        sys.exit(1)
    return {
        "host":     os.environ["DB_HOST"],
        "port":     int(os.environ.get("DB_PORT", "1521")),
        "service":  os.environ["DB_SERVICE"],
        "user":     os.environ["DB_USER"],
        "password": os.environ["DB_PASS"],
    }


# ─── Conexão Oracle ───────────────────────────────────────────────────────────

def conectar(cfg: Optional[dict] = None) -> oracledb.Connection:
    """
    Conecta ao Oracle usando Thin Mode (sem Oracle Client).
    Se cfg for None, lê de obter_config_db().

    Quando DB_SCHEMA != DB_USER (deploy em schema diferente do usuário de conexão),
    executa ALTER SESSION SET CURRENT_SCHEMA automaticamente após conectar.
    Isso garante que USER_* views e objetos sem prefixo de schema apontem
    para o schema correto, sem necessidade de prefixar cada DDL/DML.
    """
    cfg = cfg or obter_config_db()
    dsn = f"{cfg['host']}:{cfg['port']}/{cfg['service']}"
    schema = cfg.get("schema", cfg["user"])

    try:
        conn = oracledb.connect(user=cfg["user"], password=cfg["password"], dsn=dsn)
    except oracledb.DatabaseError as e:
        log.error(f"{RED}Falha na conexão Oracle: {e}{RESET}")
        sys.exit(1)

    # Mudar para o schema alvo se diferente do usuário de conexão
    if schema.upper() != cfg["user"].upper():
        try:
            with conn.cursor() as cur:
                cur.execute(f"ALTER SESSION SET CURRENT_SCHEMA = {schema.upper()}")
            log.info(f"Conectado: {CYAN}{cfg['user']}@{dsn}{RESET}  "
                     f"→ schema alvo: {CYAN}{schema.upper()}{RESET}")
        except oracledb.DatabaseError as e:
            log.error(f"{RED}Falha ao definir CURRENT_SCHEMA={schema.upper()}: {e}{RESET}")
            log.error("Verifique se o usuário tem CREATE SESSION no schema alvo.")
            conn.close()
            sys.exit(1)
    else:
        log.info(f"Conectado: {CYAN}{cfg['user']}@{dsn}{RESET}")

    return conn


def schema_efetivo(conn: oracledb.Connection) -> str:
    """Retorna o CURRENT_SCHEMA efetivo da sessão (após ALTER SESSION, se aplicado)."""
    with conn.cursor() as cur:
        cur.execute("SELECT SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') FROM dual")
        return cur.fetchone()[0]


# ─── Parser de arquivo SQL Oracle ─────────────────────────────────────────────

def split_oracle_sql(conteudo: str) -> list[str]:
    """
    Divide um arquivo SQL Oracle em statements individuais executáveis.

    Suporta:
    - SQL terminado com ;
    - Blocos PL/SQL terminados com / em linha própria
    - Comentários -- e /* */
    - BEGIN/DECLARE/CREATE OR REPLACE PACKAGE|PROCEDURE|FUNCTION|TRIGGER|TYPE
    """
    # Remover comentários de bloco
    conteudo = re.sub(r"/\*.*?\*/", "", conteudo, flags=re.DOTALL)

    PLSQL_INICIO = re.compile(
        r"^\s*(BEGIN|DECLARE"
        r"|CREATE\s+OR\s+REPLACE\s+(PACKAGE|PROCEDURE|FUNCTION|TRIGGER|TYPE)"
        r"|CREATE\s+(PACKAGE|PROCEDURE|FUNCTION|TRIGGER|TYPE))\b",
        re.IGNORECASE,
    )

    statements: list[str] = []
    buffer: list[str] = []
    em_plsql = False

    for linha in conteudo.splitlines():
        stripped = linha.strip()

        if stripped.startswith("--"):
            continue

        if PLSQL_INICIO.match(stripped):
            em_plsql = True

        # Terminador PL/SQL: / sozinho na linha
        if stripped == "/":
            stmt = "\n".join(buffer).strip().rstrip(";")
            if stmt:
                statements.append(stmt)
            buffer.clear()
            em_plsql = False
            continue

        # SQL puro terminado com ;
        if not em_plsql and stripped.endswith(";"):
            buffer.append(linha)
            stmt = "\n".join(buffer).strip().rstrip(";")
            if stmt:
                statements.append(stmt)
            buffer.clear()
            continue

        buffer.append(linha)

    # Capturar último statement sem terminador
    if buffer:
        stmt = "\n".join(buffer).strip().rstrip(";")
        if stmt:
            statements.append(stmt)

    return [s for s in statements if s.strip()]


# ─── Execução de arquivo SQL ──────────────────────────────────────────────────

def executar_arquivo_sql(
    conn: oracledb.Connection,
    arquivo: Path,
    *,
    autocommit: bool = True,
    verbose: bool = False,
) -> int:
    """
    Executa todos os statements de um arquivo SQL Oracle.
    Retorna o número de statements executados.
    Faz rollback e lança RuntimeError em caso de erro.
    """
    if not arquivo.exists():
        raise FileNotFoundError(f"Arquivo SQL não encontrado: {arquivo}")

    conteudo = arquivo.read_text(encoding="utf-8")
    statements = split_oracle_sql(conteudo)

    if not statements:
        if verbose:
            log.warning(f"  {YELLOW}Nenhum statement em {arquivo.name}{RESET}")
        return 0

    with conn.cursor() as cur:
        for i, stmt in enumerate(statements, start=1):
            if verbose:
                preview = stmt.splitlines()[0][:80]
                log.info(f"    [{i}/{len(statements)}] {DIM}{preview}...{RESET}")
            try:
                cur.execute(stmt)
            except oracledb.DatabaseError as e:
                conn.rollback()
                preview = stmt[:300].replace("\n", " ")
                raise RuntimeError(
                    f"Erro Oracle ao executar statement {i}/{len(statements)}:\n"
                    f"  {preview}\n"
                    f"  Erro: {e}"
                ) from e

    if autocommit:
        conn.commit()

    return len(statements)


# ─── Utilitários ──────────────────────────────────────────────────────────────

def checksum_sha256(arquivo: Path) -> str:
    """Calcula SHA-256 do arquivo."""
    sha = hashlib.sha256()
    sha.update(arquivo.read_bytes())
    return sha.hexdigest()


def confirmar_producao(dry_run: bool = False) -> None:
    """Exige confirmação explícita antes de deploy em produção."""
    if dry_run:
        return
    log.info(f"\n{RED}{BOLD}⚠  DEPLOY EM PRODUÇÃO{RESET}")
    confirmacao = input("  Digite 'CONFIRMO PROD' para continuar: ").strip()
    if confirmacao != "CONFIRMO PROD":
        log.info("Deploy cancelado.")
        sys.exit(0)
    log.info("")


def banner(titulo: str, ambiente: str, dry_run: bool = False) -> None:
    """Exibe banner padronizado no início de cada script."""
    log.info(SEP2)
    log.info(f"{BOLD}  {titulo}{RESET}")
    log.info(f"{BOLD}  M&S do Brasil LTDA — contato@msbrasil.inf.br{RESET}")
    log.info(SEP2)
    log.info(f"  Ambiente : {CYAN}{ambiente}{RESET}")
    if dry_run:
        log.info(f"  {YELLOW}MODO DRY-RUN — sem alterações reais{RESET}")
    log.info("")
