# Changelog

Histórico completo de versões do repositório `oracle-sql-helper-ptbr`.  
Formato: [Semantic Versioning](https://semver.org/) — `MAJOR.MINOR.PATCH`

---

## [3.1.0] — 2026-05-26

### oracle-devops-ptbr v3.1.0

**Fix arquitetural — suporte a deploy via DBA em schema diferente**

Problema: scripts usavam `USER_*` views que só enxergam o schema do usuário conectado, causando falha silenciosa quando `DB_USER != DB_SCHEMA` (ex: DBA conectado deployando em `ms_app`).

**Correções:**

- `oracle_devops_utils.py`
  - Nova variável `DB_SCHEMA` no config — schema alvo do deploy (opcional, default: `DB_USER`)
  - `conectar()`: executa `ALTER SESSION SET CURRENT_SCHEMA = DB_SCHEMA` automaticamente quando `DB_SCHEMA != DB_USER`
  - Nova função `schema_efetivo(conn)` — retorna `SYS_CONTEXT('USERENV','CURRENT_SCHEMA')`

- `apply_changelog.py` + `create-changelog-table.sql`
  - `USER_TABLES` → `ALL_TABLES WHERE owner = SYS_CONTEXT('USERENV','CURRENT_SCHEMA')`
  - Funciona independentemente de qual usuário está conectado

- `deploy_ords.py`
  - Verificação pós-deploy: tenta `DBA_ORDS_MODULES WHERE schema = :schema` (ORDS 24.4+)
  - Fallback para `USER_ORDS_MODULES` (funciona após `ALTER SESSION SET CURRENT_SCHEMA`)

- `references/git-project-structure-ptbr.md`
  - Documentação de `DB_SCHEMA` no `.env.example`
  - Seção "Schema alvo vs usuário de conexão"

---

## [3.0.0] — 2026-05-26

### oracle-devops-ptbr v3.0.0 — Breaking

**Migração completa para Python + oracledb Thin Mode**

Todos os scripts shell foram migrados para Python. Os `.sh` viram thin wrappers (`exec python3 script.py "$@"`).

**Novo módulo compartilhado:**
- `oracle_devops_utils.py` — `conectar()`, `executar_arquivo_sql()`, `split_oracle_sql()`, `checksum_sha256()`, `banner()`, cores, logging

**Scripts Python adicionados:**
- `deploy_full.py` — orquestrador: changelog → APEX → ORDS (com `--skip-db/apex/ords`)
- `deploy_db.py` — deploy ordenado: sequences → types → tables → package specs → bodies → triggers
- `deploy_ords.py` — security → privileges → módulos (verifica `USER_ORDS_MODULES` pós-deploy)
- `export_db.py` — `DBMS_METADATA.GET_DDL()` → estrutura `db/` com extensões `.pks/.pkb/.vw/.trg`
- `export_ords.py` — `ORDS_EXPORT.export_schema()` como CLOB nativo via oracledb
- `export_apex.py` — export split APEX via SQLcl subprocess + backup automático + `install.sql`

**`apply_changelog.py` refatorado:**
- Remove duplicações com `oracle_devops_utils`
- Importa todas as funções compartilhadas do utils

**`github-deploy.yml` atualizado:**
- Etapa ORDS usa `deploy_ords.py`
- Smoke test inclui `apply_changelog.py --status`

---

## [2.3.0] — 2026-05-26

### oracle-devops-ptbr v2.3.0

- `apply_changelog.py` — implementação Python completa com `oracledb` + `PyYAML`
  - CLI: `--env`, `--dry-run`, `--status`, `--project-root`
  - Checksum SHA-256 via `hashlib` (sem dependência de `sha256sum`)
  - Confirmação `"CONFIRMO PROD"` para ambiente de produção
  - Cores no terminal (desativadas automaticamente em CI sem TTY)
  - Detecção de integridade (arquivo alterado após aplicação)
- `apply-changelog.sh` → thin wrapper que chama o Python
- `requirements-devops.txt` — `oracledb>=2.0.0`, `PyYAML>=6.0.0`
- `github-deploy.yml` — etapa banco usa `apply_changelog.py`

---

## [2.2.0] — 2026-05-26

### oracle-devops-ptbr v2.2.0

**Sistema de Changelog do banco**

- `changelog_template.yml` — template para `db/changelog.yml`; regras, tipos (`ddl|dml|fix`), exemplos
- `create-changelog-table.sql` — DDL idempotente de `db_changelog` com `checksum`, `duracao_ms`, `ambiente`
- `apply-changelog.sh` — lê `changelog.yml`, aplica via SQLcl, registra com SHA-256, fail-fast, detecção de drift
- `references/git-project-structure-ptbr.md` — seção 11: sistema de changelog, tabela de comportamentos, workflow completo

---

## [2.1.0] — 2026-05-26

### oracle-devops-ptbr v2.1.0

- `export-db.sh` — extrai DDL completo do schema via `DBMS_METADATA.GET_DDL()`
  - Packages separados em `.pks` (spec) e `.pkb` (body)
  - Remove cláusulas de storage/tablespace
  - Detecta objetos INVÁLIDOS e avisa
  - Suporte a tipo específico: `--tipo tables|packages|...`

---

## [2.0.0] — 2026-05-26

### Breaking — Divisão em 7 Skills Especializadas

O monolítico `oracle-sql-helper-ptbr` v1.6.0 foi dividido em 6 skills (`oracle-plsql-ptbr`, `oracle-apex-ptbr`, `oracle-ords-ptbr`, `oracle-dba-ptbr`, `oracle-tuning-ptbr`, `oracle-trivadis-ptbr`), mais a nova skill `oracle-devops-ptbr`.

**Ação necessária:** desinstalar `oracle-sql-helper-ptbr` e instalar as 7 novas skills.

### oracle-devops-ptbr v2.0.0 — nova skill

- Estrutura canônica de projeto Oracle/APEX/ORDS no Git (`db/`, `apex/`, `ords/`, `scripts/`)
- Padrão GMUD para nomenclatura de scripts (`001_projeto_ddl_objeto.sql`)
- `deploy-full.sh` — orquestrador com confirmação obrigatória para prod
- `deploy-db.sh` — deploy ordenado de objetos do banco
- `deploy-ords.sh` — security → privileges → módulos
- `export-apex.sh` — export split via SQLcl com backup automático
- `export-ords.sh` — export via `ORDS_EXPORT.export_schema()`
- `module_template.sql` — template ORDS completo (module + templates + handlers GET/POST/DELETE + privileges)
- `github-deploy.yml` — workflow CI/CD com aprovação obrigatória para `main`
- `gitignore-oracle.txt` — `.gitignore` para projetos Oracle

### oracle-plsql-ptbr v2.0.0
PL/SQL 19c + Trivadis 4.4 + EBR + LOBs + Logger + compound triggers.  
9 templates SQL. 1 reference. Referência cruzada para `oracle-trivadis-ptbr`.

### oracle-apex-ptbr v2.0.0
APEX 24.2 development + Data Dictionary completo (`APEX_APPLICATION_*`, `APEX_WORKSPACE_*`, `APEX_APPL_*`).  
6 templates SQL. 2 references (patterns + data dictionary).

### oracle-ords-ptbr v2.0.0
ORDS REST services + Data Dictionary (`USER_ORDS_*`, `DBA_ORDS_*`).  
2 templates SQL. 2 references. Alerta depreciação `OAUTH → ORDS_SECURITY`.

### oracle-dba-ptbr v2.0.0
DBA operacional + Oracle Data Dictionary (`V$`, `GV$`, `DBA_*`, `CDB_*`, `DBA_HIST_*`).  
3 templates SQL. 2 references. Alerta licença Diagnostics Pack.

### oracle-tuning-ptbr v2.0.0
Performance tuning — explain plan, AWR/ASH em tempo real, index strategy.  
2 templates SQL. 1 reference.

### oracle-trivadis-ptbr v2.0.0
Trivadis Guidelines 4.4 — checklist de revisão, prefixos, naming PT-BR.  
1 reference. Skill de revisão explícita (as demais aplicam Trivadis automaticamente).

---

## Histórico do monolítico oracle-sql-helper-ptbr

### [1.6.0]
- `ords-data-dictionary-ptbr.md` — `USER_ORDS_*`/`DBA_ORDS_*`, evolução 18.x→25.x, depreciação OAUTH

### [1.5.0]
- `apex-data-dictionary-ptbr.md` — hierarquia APEX_APPLICATION_*/APEX_APPL_*/APEX_WORKSPACE_*, versões 19→26.1

### [1.4.0]
- Remoção de clientes reais — autoria M&S do Brasil LTDA

### [1.3.0]
- `data-dictionary-ptbr.md` — hierarquia Oracle, matriz edição × tecnologia, evolução 11g→26ai

### [1.2.0]
- Scripts DBA estilo Tim Hall, Network ACL, APEX 24.2, Result Cache

### [1.1.0]
- Princípios #9, #10, #11 — triggers, compound trigger, EBR
- `ebr-editioning-views.md`

### [1.0.0]
- Lançamento: PL/SQL + APEX + ORDS + DBA + Performance — 11 princípios Trivadis, 23 assets SQL
