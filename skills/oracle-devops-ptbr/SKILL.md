---
name: oracle-devops-ptbr
description: Estrutura Git e CI/CD para projetos Oracle/APEX/ORDS. ATIVE em estrutura de projeto Oracle no Git, commit de objetos do banco, script de deploy, GitHub Actions para Oracle, export APEX split via SQLcl, versionamento de módulos ORDS, GMUD naming (001_projeto_ddl_objeto.sql), deploy-db/deploy-apex/deploy-ords, branch strategy, .gitignore Oracle, rollback, ordem de dependências de objetos. Frases — "como estruturar meu projeto no Git", "script de deploy Oracle", "export do APEX para Git", "GitHub Actions ORDS", "versionar módulo ORDS", "deploy ordenado do banco", "nomenclatura GMUD". NAO ATIVE em código PL/SQL (oracle-plsql-ptbr), APEX pages (oracle-apex-ptbr), ORDS handlers (oracle-ords-ptbr), DBA operacional (oracle-dba-ptbr), tuning (oracle-tuning-ptbr). Templates em assets/.
metadata:
  version: "3.1.0"
  author: "Maxwell da Silva Oliveira"
  contact: "contato@msbrasil.inf.br"
  git: "https://github.com/maxwbh"
  organization: "M&S do Brasil LTDA"
  site: "https://msbrasil.inf.br"
  changelog: |
    v3.1.0: Fix — substituição de USER_* por ALL_* com SYS_CONTEXT(CURRENT_SCHEMA). oracle_devops_utils: DB_SCHEMA + ALTER SESSION SET CURRENT_SCHEMA automático. deploy_ords: DBA_ORDS_MODULES com fallback USER_ORDS_MODULES. Suporte a deploy via usuário DBA em schema alvo diferente.
    v3.0.0: Breaking — todos os scripts migrados para Python (oracledb Thin Mode). Novo oracle_devops_utils.py compartilhado. deploy_full/db/ords.py, export_db/ords/apex.py. Shell scripts viram thin wrappers. requirements-devops.txt atualizado.
    v2.3.0: Reescrita do apply-changelog em Python (oracledb Thin Mode + PyYAML). apply_changelog.py com argparse, dry-run, status, cores terminal, confirmacao prod. apply-changelog.sh vira wrapper fino. requirements-devops.txt. github-deploy.yml atualizado.
    v2.2.0: Sistema de changelog do banco — changelog.yml + db_changelog (Oracle) + apply-changelog.sh (checksum SHA-256, fail-fast, deteccao de drift). Assets: changelog_template.yml, create-changelog-table.sql, apply-changelog.sh.
    v2.1.0: Novo asset export-db.sh — extrai DDL completo do schema Oracle (DBMS_METADATA.GET_DDL) para estrutura db/ do Git. Packages separados em .pks e .pkb. Remove clausulas de storage/tablespace. Detecta objetos invalidos.
    v2.0.0: Skill criada como parte da família oracle-*-ptbr v2.0.0. Cobre estrutura Git, scripts de deploy (deploy-full/db/ords/apex), export APEX split, versionamento ORDS, GMUD naming, branch strategy, .gitignore Oracle, GitHub Actions CI/CD.
  tags:
    - "oracle"
    - "devops"
    - "cicd"
    - "git"
    - "github-actions"
    - "changelog"
    - "oracledb"
    - "python"
    - "deployment"
  category: "devops"
  language: "pt-BR"
  icon: "⚙️"
---

# oracle-devops-ptbr — v3.1.0

Estrutura Git, scripts de deploy e CI/CD para projetos Oracle 19c + APEX 24.2 + ORDS.

**Desenvolvido por:** Maxwell da Silva Oliveira — [M&S do Brasil LTDA](https://msbrasil.inf.br)

## Áreas cobertas

| Área | Reference | Assets |
|---|---|---|
| **Estrutura Git e Changelog** | `references/git-project-structure-ptbr.md` | `oracle_devops_utils.py`, `apply_changelog.py`, `deploy_full.py`, `deploy_db.py`, `deploy_ords.py`, `export_db.py`, `export_ords.py`, `export_apex.py` |
| **Templates e configuração** | — | `module_template.sql`, `changelog_template.yml`, `github-deploy.yml`, `gitignore-oracle.txt`, `requirements-devops.txt` |

## Quando ativar

- Estrutura de diretórios para projeto Oracle/APEX/ORDS no Git
- Nomenclatura de arquivos de deploy (padrão GMUD: `001_projeto_ddl_objeto.sql`)
- Scripts de deploy Python: `deploy_full.py` (orquestrador), `deploy_db.py`, `deploy_ords.py`
- Export APEX split via SQLcl (`apex export -split`)
- Export de módulos ORDS via `ORDS_EXPORT.export_schema()`
- Versionamento de módulos ORDS (`clientes_v1/`, `clientes_v2/`)
- Branch strategy (`main` / `hom` / `develop` / `feature/*`)
- GitHub Actions para Oracle/APEX/ORDS
- `.gitignore` para projetos Oracle
- `.gitattributes` (encoding UTF-8, LF)
- Ordem de deploy de objetos do banco (sequences → tables → packages → triggers)
- Gestão de environments (dev / hom / prod) sem credenciais em código
- Exportar DDL atual do banco para Git (baseline de projeto legado, sync após alteração direta)
- Changelog de banco: migrations ordenadas (changelog.yml + db_changelog), apply_changelog.py com --dry-run/--status, checksum SHA-256, detecção de drift entre ambientes

**Não usar** para: código PL/SQL (→ oracle-plsql-ptbr), APEX pages (→ oracle-apex-ptbr), ORDS handlers (→ oracle-ords-ptbr), DBA ops (→ oracle-dba-ptbr), tuning (→ oracle-tuning-ptbr).

## Estrutura canônica de projeto

```
meu-projeto-apex/
├── .gitignore            ← assets/gitignore-oracle.txt
├── db/
│   ├── tables/           ← DDL de tabelas
│   ├── views/
│   ├── packages/         ← .pks (spec) e .pkb (body) separados
│   ├── procedures/       ← .prc
│   ├── functions/        ← .fnc
│   ├── triggers/         ← .trg (sempre compound)
│   └── scripts/          ← 001_projeto_tipo_objeto.sql (GMUD)
├── apex/
│   └── app_100/
│       ├── install.sql   ← entry point
│       └── f100/         ← export split (SQLcl)
├── ords/
│   ├── modules/
│   │   ├── clientes_v1/  ← module.sql + templates.sql +
│   │   └── clientes_v2/     handlers.sql + privileges.sql
│   ├── security/
│   └── scripts/          ← (wrappers shell — chamam os .py)
├── scripts/
│   ├── deploy_full.py    ← orquestrador (changelog → apex → ords)
│   ├── deploy_db.py      ← deploy objetos banco em ordem
│   ├── deploy_ords.py    ← deploy módulos ORDS
│   ├── apply_changelog.py← migrations do changelog.yml
│   ├── export_db.py      ← extrai DDL do banco → db/
│   ├── export_apex.py    ← export split APEX via SQLcl
│   ├── export_ords.py    ← export schema ORDS
│   ├── oracle_devops_utils.py  ← módulo compartilhado
│   └── requirements-devops.txt
└── .github/workflows/
    └── deploy.yml        ← assets/github-deploy.yml
```

## Padrão GMUD — nomenclatura de scripts

```
{sequencia}_{projeto}_{tipo}_{objeto}.sql

001_msbrasil_ddl_tb_clientes.sql
002_msbrasil_ddl_pk_clientes.sql
003_msbrasil_pkg_clientes.sql
004_msbrasil_page_54_cadastro_v1.sql
```

Tipos: `ddl` `dml` `pkg` `prc` `fnc` `trg` `vw` `page` `fix`

## Ordem de deploy de objetos do banco

```
sequences → types → tables → constraints → FK → indexes →
grants → synonyms → views → package specs (.pks) →
package bodies (.pkb) → procedures → functions → triggers →
APEX → ORDS
```

Implementado em `assets/deploy_db.py`.

## Assets disponíveis

| Arquivo | Tipo | Descrição |
|---|---|---|
| **Módulo compartilhado** | | |
| `oracle_devops_utils.py` | Python | `conectar()`, `executar_arquivo_sql()`, `split_oracle_sql()`, `checksum_sha256()`, cores, banner |
| **Scripts Python — uso direto** | | |
| `apply_changelog.py` | Python | Lê `db/changelog.yml`, aplica migrations via oracledb. CLI: `--env`, `--dry-run`, `--status` |
| `deploy_full.py` | Python | Orquestrador: changelog → APEX → ORDS. Suporta `--skip-db/apex/ords` |
| `deploy_db.py` | Python | Deploy ordenado: sequences → types → tables → package specs → bodies → triggers |
| `deploy_ords.py` | Python | Deploy ORDS: security → privileges → módulos. Verifica `USER_ORDS_MODULES` pós-deploy |
| `export_db.py` | Python | Extrai DDL via `DBMS_METADATA.GET_DDL()` → `db/` (.pks/.pkb/.vw/.trg...) |
| `export_ords.py` | Python | Export via `ORDS_EXPORT.export_schema()` — lê CLOB nativo via oracledb |
| `export_apex.py` | Python | Export split APEX via SQLcl subprocess — backup automático, gera `install.sql` |
| **Wrappers shell (compatibilidade CI/CD)** | | |
| `apply-changelog.sh` | Shell | `exec python3 apply_changelog.py "$@"` |
| `deploy-full.sh` | Shell | `exec python3 deploy_full.py "$@"` |
| `deploy-db.sh` | Shell | `exec python3 deploy_db.py "$@"` |
| `deploy-ords.sh` | Shell | `exec python3 deploy_ords.py "$@"` |
| `export-db.sh` | Shell | `exec python3 export_db.py "$@"` |
| `export-apex.sh` | Shell | `exec python3 export_apex.py "$@"` |
| `export-ords.sh` | Shell | `exec python3 export_ords.py "$@"` |
| **Configuração e templates** | | |
| `requirements-devops.txt` | Config | `oracledb>=2.0.0`, `PyYAML>=6.0.0` |
| `changelog_template.yml` | Template | Copiar para `db/changelog.yml` do projeto |
| `create-changelog-table.sql` | SQL | DDL idempotente da tabela `db_changelog` |
| `module_template.sql` | SQL | Template completo de módulo ORDS (module + templates + handlers + privileges) |
| `gitignore-oracle.txt` | Config | Copiar como `.gitignore` na raiz do projeto |
| `github-deploy.yml` | CI/CD | Workflow GitHub Actions — branch → ambiente, aprovação prod, smoke tests |

## Referências cruzadas

| Precisa de | Skill |
|---|---|
| Código PL/SQL nos packages de `db/packages/` | **oracle-plsql-ptbr** |
| Nomenclatura Trivadis no código | **oracle-trivadis-ptbr** |
| Handlers e módulos em `ords/modules/` | **oracle-ords-ptbr** |
| Pages e components em `apex/` | **oracle-apex-ptbr** |
| DBA ops durante deploy | **oracle-dba-ptbr** |
| Query lenta pós-deploy | **oracle-tuning-ptbr** |
