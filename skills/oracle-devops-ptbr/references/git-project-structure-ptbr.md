# Estrutura Git para Projetos Oracle/APEX/ORDS

Referência completa para organizar projetos Oracle 19c + APEX 24.2 + ORDS no Git. Cobre estrutura de diretórios, convenções de nomenclatura de arquivos, ordem de deploy, estratégia de branches, versionamento de módulos ORDS, export split do APEX, GMUD naming e CI/CD com GitHub Actions.

---

## 1. Estrutura canônica do repositório

```
meu-projeto-apex/
├── README.md
├── CHANGELOG.md
├── LICENSE
├── .gitignore                          ← assets/gitignore-oracle.txt
│
├── db/                                 ← Objetos do banco de dados
│   ├── tables/                         ← DDL de tabelas (sem DML)
│   ├── views/                          ← Views e editioning views
│   ├── packages/                       ← Specs e bodies separados
│   │   ├── pkg_clientes.pks            ← .pks = package spec
│   │   └── pkg_clientes.pkb            ← .pkb = package body
│   ├── procedures/                     ← Procedures standalone
│   ├── functions/                      ← Functions standalone
│   ├── triggers/                       ← Compound triggers
│   ├── types/                          ← Object types e collections
│   ├── sequences/                      ← Sequences e identity columns
│   ├── synonyms/                       ← Sinônimos públicos e privados
│   ├── grants/                         ← Grants entre schemas
│   └── scripts/                        ← Scripts pontuais (patch, fix)
│       ├── 001_msbrasil_ddl_criar_tb_clientes.sql
│       └── 002_msbrasil_dml_carga_inicial.sql
│
├── apex/                               ← Aplicações APEX (export split)
│   ├── app_100/
│   │   ├── install.sql                 ← Entry point do deploy APEX
│   │   └── f100/                       ← Estrutura split (SQLcl/APEXExport)
│   │       ├── application/
│   │       │   ├── pages/
│   │       │   ├── shared_components/
│   │       │   └── ...
│   │       └── readable/               ← YAML legível (opcional, 24.2+)
│   └── app_114/
│       ├── install.sql
│       └── f114/
│
├── ords/                               ← Versionamento de módulos ORDS
│   ├── modules/                        ← Um diretório por módulo/versão
│   │   ├── clientes_v1/
│   │   │   ├── module.sql              ← ORDS.define_module(...)
│   │   │   ├── templates.sql           ← ORDS.define_template(...)
│   │   │   ├── handlers.sql            ← ORDS.define_handler(...)
│   │   │   └── privileges.sql          ← ORDS.define_privilege(...)
│   │   ├── clientes_v2/
│   │   │   ├── module.sql
│   │   │   ├── templates.sql
│   │   │   ├── handlers.sql
│   │   │   └── privileges.sql
│   │   └── relatorios_v1/
│   ├── security/                       ← Roles e OAuth global
│   │   ├── roles.sql
│   │   └── oauth_clients.sql
│   ├── privileges/
│   │   └── global_privileges.sql
│   └── scripts/                        ← Scripts shell ORDS
│       ├── export-ords.sh              ← assets/export-ords.sh
│       ├── deploy-ords.sh              ← assets/deploy-ords.sh
│       └── install-modules.sh
│
├── scripts/                            ← Scripts de orquestração
│   ├── deploy-full.sh                  ← assets/deploy-full.sh
│   ├── deploy-db.sh                    ← assets/deploy-db.sh
│   └── export-apex.sh                  ← assets/export-apex.sh
│
├── docs/                               ← Documentação
│   ├── arquitetura.md
│   ├── gmud/                           ← Documentação de mudanças (GMUD)
│   └── dicionario-dados.md
│
├── tests/                              ← Testes automatizados
│   ├── db/                             ← utPLSQL
│   └── api/                            ← Testes REST (Newman/Postman)
│
└── .github/
    └── workflows/
        └── deploy.yml                  ← assets/github-deploy.yml
```

---

## 2. Convenções de nomenclatura de arquivos

### Objetos do banco

| Tipo | Extensão | Exemplo |
|---|---|---|
| Package spec | `.pks` | `pkg_clientes.pks` |
| Package body | `.pkb` | `pkg_clientes.pkb` |
| Procedure | `.prc` | `prc_processar_pagamento.prc` |
| Function | `.fnc` | `fnc_calcular_desconto.fnc` |
| View | `.vw` | `vw_clientes_ativos.vw` |
| Trigger | `.trg` | `trg_clientes_audit.trg` |
| Table DDL | `.sql` | `tb_clientes.sql` |
| Type | `.typ` | `t_lista_ids.typ` |

### Scripts de deploy (GMUD)

Padrão: `{sequencia}_{projeto}_{tipo}_{objeto}.sql`

```
001_msbrasil_ddl_tb_clientes.sql          ← CREATE TABLE
002_msbrasil_ddl_pk_clientes.sql          ← PRIMARY KEY
003_msbrasil_ddl_fk_clientes_cidades.sql  ← FOREIGN KEY
004_msbrasil_ddl_idx_clientes_cpf.sql     ← CREATE INDEX
005_msbrasil_dml_carga_tipo_cliente.sql   ← INSERT de domínio
006_msbrasil_pkg_clientes.sql             ← CREATE OR REPLACE PACKAGE
007_msbrasil_page_54_cadastro_v1.sql      ← Script APEX (se necessário)
```

Tipos de prefixo:
- `ddl` — CREATE, ALTER, DROP
- `dml` — INSERT, UPDATE, DELETE (domínio/carga)
- `pkg` — Package spec + body
- `prc` / `fnc` / `trg` / `vw` — objetos individuais
- `page` — Script pontual de APEX page
- `fix` — Hotfix de produção

---

## 3. Extensões de arquivo Oracle no Git

Configure o `.gitattributes` para tratamento correto de encoding:

```gitattributes
# .gitattributes
*.sql   text eol=lf encoding=utf-8
*.pks   text eol=lf encoding=utf-8
*.pkb   text eol=lf encoding=utf-8
*.prc   text eol=lf encoding=utf-8
*.fnc   text eol=lf encoding=utf-8
*.vw    text eol=lf encoding=utf-8
*.trg   text eol=lf encoding=utf-8
*.sh    text eol=lf
*.yml   text eol=lf
*.md    text eol=lf encoding=utf-8
*.json  text eol=lf
```

---

## 4. Ordem de deploy — dependências entre objetos

A ordem importa. Violar a ordem gera objetos inválidos.

```
1.  SEQUENCES / TYPES simples (sem dependência)
2.  TABLES (DDL)
3.  CONSTRAINTS (PK, UK, CHECK — antes de FK)
4.  FOREIGN KEYS (depois de todas as tabelas existirem)
5.  INDEXES
6.  GRANTS (entre schemas)
7.  SYNONYMS
8.  VIEWS simples (baseadas em tabelas)
9.  PACKAGE SPECS (.pks) — declara tipos e assinaturas
10. PACKAGE BODIES (.pkb) — implementa (depende das specs)
11. PROCEDURES e FUNCTIONS standalone
12. TRIGGERS (depende de tabelas e packages)
13. EDITIONING VIEWS (EBR — se aplicável)
14. MATERIALIZED VIEWS (por último — refresh pode ser lento)
15. APEX (import após todos os objetos de banco existirem)
16. ORDS modules (após APEX e banco)
```

Implementado em `assets/deploy-db.sh`.

---

## 5. Estratégia de branches

```
main            ← produção — protegida, só merge via PR
│
├── hom         ← homologação — deploy automático via CI/CD
│
└── develop     ← desenvolvimento — integração contínua
    │
    ├── feature/PKG-123-novos-endpoints-clientes
    ├── feature/PKG-124-relatorio-inadimplencia
    └── fix/BUG-45-calculo-juros
```

### Fluxo de trabalho

```
1. Criar branch feature/fix a partir de develop
2. Desenvolver e testar localmente
3. PR para develop → deploy automático em dev
4. Aprovação → merge em develop
5. PR develop → hom → deploy automático em hom
6. Aprovação de negócio → PR hom → main
7. Deploy em produção (manual ou agendado)
8. Tag de versão: git tag -a v1.2.3 -m "Release 1.2.3"
```

### Proteções recomendadas (GitHub)

- `main`: require PR, require 2 approvals, no force push, no direct push
- `hom`: require PR, require 1 approval
- `develop`: allow direct push para committers

---

## 6. Export APEX — modo split (recomendado)

O export split gera um arquivo por componente APEX, viabilizando diff granular no Git.

### Via SQLcl (recomendado para CI/CD)

```bash
# Export split completo
sql /nolog << EOF
connect ${DB_USER}/${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_SERVICE}
apex export -applicationid 100 -split -expOriginalIds -dir apex/app_100
exit
EOF
```

### Via APEX Export (linha de comando Java)

```bash
java -jar /opt/oracle/apex/utilities/oracle/apex/APEXExport.jar \
  -db ${DB_HOST}:${DB_PORT}:${DB_SERVICE} \
  -user ${DB_USER} -password ${DB_PASS} \
  -applicationid 100 -split
```

### O que commitar do export APEX

```
apex/app_100/
├── install.sql          ← commitar — entry point
└── f100/
    ├── application/
    │   ├── pages/
    │   │   ├── page_00000.sql   ← commitar
    │   │   ├── page_00001.sql   ← commitar
    │   │   └── ...
    │   ├── shared_components/
    │   │   ├── authentication_schemes/
    │   │   ├── authorization_schemes/
    │   │   ├── lists_of_values/
    │   │   └── ...
    │   └── set_environment.sql  ← commitar
    └── readable/        ← commitar se usando 24.2+ com readable format
```

**Não commitar:** arquivos de export monolítico (`f100.sql`) — gera diff inutilizável.

---

## 7. Versionamento de módulos ORDS no Git

Cada módulo ORDS ganha um diretório próprio. A versão faz parte do nome.

```
ords/modules/clientes_v1/
├── module.sql       ← ORDS.define_module (p_module_name => 'clientes.v1')
├── templates.sql    ← ORDS.define_template para cada URI pattern
├── handlers.sql     ← ORDS.define_handler GET/POST/PUT/DELETE
└── privileges.sql   ← ORDS.define_privilege + ORDS_SECURITY
```

### Fluxo de versionamento ORDS

```
Nova versão de API:
1. Criar diretório clientes_v2/
2. Copiar clientes_v1/ como base
3. Alterar p_module_name => 'clientes.v2' e p_base_path => '/clientes/v2/'
4. Manter clientes_v1/ publicado (retrocompatibilidade)
5. Após sunset de v1: despublicar (p_status => 'NOT_PUBLISHED')

Deprecação:
- Adicionar header Deprecation: true nos handlers v1
- Documentar sunset em docs/api-versioning.md
```

### Export automático via ORDS_EXPORT

```sql
-- Gera script PL/SQL completo do schema ORDS
DECLARE
  l_ddl CLOB;
BEGIN
  l_ddl := ORDS_EXPORT.export_schema(
              p_include_modules      => TRUE,
              p_include_privileges   => TRUE,
              p_include_roles        => TRUE,
              p_include_oauth        => TRUE,
              p_include_rest_objects => TRUE,
              p_include_jwt_profiles => TRUE,
              p_include_enable_schema => TRUE,
              p_export_date          => TRUE
            );
  -- Salvar em arquivo via UTL_FILE ou direcionar para spool
  DBMS_OUTPUT.put_line(SUBSTR(l_ddl, 1, 32767));
END;
/
```

---

## 8. Configuração de environments

Use variáveis de ambiente por stage — nunca credenciais em código.

### .env.example (commitar — sem valores reais)

```bash
# Banco de dados
DB_HOST=localhost
DB_PORT=1521
DB_SERVICE=ORCL
DB_USER=ms_app
DB_PASS=

# APEX
APEX_WORKSPACE=MS_BRASIL
APEX_APP_ID=100

# ORDS
ORDS_URL=https://servidor/ords
ORDS_SCHEMA=ms_app

# Ambiente (dev | hom | prod)
ENVIRONMENT=dev
```

### .env (NÃO commitar — no .gitignore)

```bash
DB_HOST=meu-servidor-real.com
DB_PASS=senha_real_aqui
```

---

## 9. CI/CD — GitHub Actions

Veja `assets/github-deploy.yml` para o workflow completo. Resumo do fluxo:

```
Push para develop → Deploy em DEV
  └── Validação SQL (sintaxe)
  └── Deploy objetos DB (deploy-db.sh)
  └── Import APEX (SQLcl)
  └── Deploy ORDS modules (deploy-ords.sh)
  └── Smoke tests (curl nos endpoints ORDS)

Push para hom → Deploy em HOM
  └── Mesmo fluxo + testes de integração (Newman)

Push para main → Deploy em PROD (manual approval)
  └── Mesmo fluxo + aprovação humana obrigatória
  └── Tag automática de versão
```

---

## 10. Fontes e referências

```
# APEX Export (SQLcl)
https://docs.oracle.com/en/database/oracle/sql-developer-command-line/

# ORDS_EXPORT package
https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/25.4/orddg/ords_export-pl-sql-package-reference.html

# GitHub Actions com Oracle
https://github.com/oracle-actions/

# utPLSQL (testes unitários PL/SQL)
https://utplsql.org/

# Newman (testes API REST)
https://learning.postman.com/docs/collections/using-newman-cli/
```

## 12. Scripts Python — uso rápido

Todos os scripts usam `oracle_devops_utils.py` como base compartilhada (conexão, SQL execution, logging).

```bash
# Instalar dependências (uma vez)
pip install -r scripts/requirements-devops.txt

# Deploy completo
python scripts/deploy_full.py --env dev
python scripts/deploy_full.py --env prod --dry-run  # simular

# Só banco (changelog)
python scripts/apply_changelog.py --env hom
python scripts/apply_changelog.py --status           # ver estado

# Só ORDS
python scripts/deploy_ords.py --env dev
python scripts/deploy_ords.py --env dev --modulo clientes_v2

# Exportar DDL atual do banco → Git
python scripts/export_db.py --schema ms_app
python scripts/export_db.py --tipo packages          # só packages

# Exportar APEX → split
python scripts/export_apex.py --app-id 100

# Exportar schema ORDS
python scripts/export_ords.py --schema ms_app
```

### Dependências entre scripts

```
oracle_devops_utils.py
    ↑ importado por todos os demais scripts
    │
    ├── apply_changelog.py  ← usa: conectar, executar_arquivo_sql, checksum_sha256
    ├── deploy_db.py        ← usa: conectar, executar_arquivo_sql
    ├── deploy_ords.py      ← usa: conectar, executar_arquivo_sql
    ├── export_db.py        ← usa: conectar (DBMS_METADATA via oracledb)
    ├── export_ords.py      ← usa: conectar (ORDS_EXPORT via oracledb)
    └── deploy_full.py      ← usa: conectar + chama outros via subprocess
```

### Conexão: oracledb Thin Mode

Todos os scripts usam **oracledb Thin Mode** — sem Oracle Client instalado.

```python
import oracledb
conn = oracledb.connect(user="ms_app", password="...", dsn="host:1521/service")
```

Funciona em: Linux, macOS, Windows, GitHub Actions (ubuntu-latest) — sem Oracle Instant Client.

### Schema alvo vs usuário de conexão (DB_SCHEMA)

Quando o **usuário de conexão** é diferente do **schema de deploy** (ex: DBA conecta como `admin_user` mas deploya em `ms_app`), defina `DB_SCHEMA`:

```bash
# .env
DB_USER=admin_user   # conecta como este usuário
DB_PASS=senha_admin
DB_SCHEMA=ms_app     # deploya neste schema
```

O `oracle_devops_utils.py` executa automaticamente `ALTER SESSION SET CURRENT_SCHEMA = MS_APP` após conectar. Isso garante que:
- `USER_*` views apontem para `ms_app` (não `admin_user`)
- DDL sem prefixo de schema (`CREATE TABLE ...`) cria em `ms_app`
- `ORDS.define_module(...)` registra no schema correto

Se `DB_SCHEMA` não for definido, o deploy ocorre no próprio schema de `DB_USER`.


---

## Linkagem interna

- Objetos do banco (`db/`) → `oracle-plsql-ptbr`
- APEX export e import → `oracle-apex-ptbr`
- ORDS modules e export → `oracle-ords-ptbr`
- Nomenclatura de código → `oracle-trivadis-ptbr`
- Performance de deploy → `oracle-tuning-ptbr`
- DBA durante deploy → `oracle-dba-ptbr`

---

## 11. Sistema de Changelog do banco — migrations rastreadas

### Conceito

Similar ao Flyway/Liquibase, mas nativo Oracle + shell. Cada alteração no banco é um arquivo SQL rastreado por `db/changelog.yml` e controlado pela tabela `db_changelog`.

```
db/
├── changelog.yml              ← MESTRE — lista ordenada de todas as migrations
│                                 (copiar de assets/changelog_template.yml)
├── tables/
│   ├── tb_clientes.sql        ← DDL atual (atualizado pelo export-db.sh)
│   └── alter/                 ← Alterações incrementais após criação
│       ├── 001_add_col_email.sql
│       └── 002_add_col_telefone.sql
├── sequences/
│   └── alter/
│       └── 001_increment_seq_clientes.sql
└── data/                      ← DML de patch e dados de domínio
    ├── 001_carga_tipos_cliente.sql
    └── 002_update_descricao_tipo_gov.sql
```

### Tabela de controle — db_changelog

Criada automaticamente pelo `apply-changelog.sh` na primeira execução:

```sql
CREATE TABLE db_changelog (
  id             VARCHAR2(20)   NOT NULL,   -- ex: DB-001
  descricao      VARCHAR2(500)  NOT NULL,
  arquivo        VARCHAR2(500)  NOT NULL,   -- relativo a db/
  tipo           VARCHAR2(10)   NOT NULL,   -- ddl | dml | fix
  checksum       VARCHAR2(64)   NOT NULL,   -- SHA-256 do arquivo
  aplicado_em    DATE           DEFAULT SYSDATE NOT NULL,
  aplicado_por   VARCHAR2(100)  DEFAULT USER NOT NULL,
  duracao_ms     NUMBER,
  ambiente       VARCHAR2(10),              -- dev | hom | prod
  CONSTRAINT pk_db_changelog PRIMARY KEY (id)
);
```

Consultas úteis:

```sql
-- Histórico completo de migrations aplicadas
SELECT id, tipo, descricao, TO_CHAR(aplicado_em, 'DD/MM/YYYY HH24:MI') AS quando,
       aplicado_por, duracao_ms || 'ms' AS duracao, ambiente
  FROM db_changelog
 ORDER BY aplicado_em;

-- Migrations aplicadas em prod mas não em hom (drift de ambiente)
SELECT id, descricao FROM db_changelog WHERE ambiente = 'prod'
MINUS
SELECT id, descricao FROM db_changelog WHERE ambiente = 'hom';

-- Última migration aplicada
SELECT id, descricao, aplicado_em, ambiente
  FROM db_changelog
 ORDER BY aplicado_em DESC
 FETCH FIRST 1 ROW ONLY;
```

### Formato do changelog.yml

```yaml
migrations:

  - id: "DB-001"               # permanente — nunca alterar
    arquivo: "tables/tb_clientes.sql"
    tipo: "ddl"                # ddl | dml | fix
    descricao: "Criar tabela tb_clientes"

  - id: "DB-007"
    arquivo: "tables/alter/001_tb_clientes_add_col_email.sql"
    tipo: "ddl"
    descricao: "tb_clientes — adicionar coluna email"

  - id: "DB-010"
    arquivo: "data/002_update_tipo_cliente.sql"
    tipo: "dml"
    descricao: "Corrigir descrição tipo GOV"
```

**Regras invioláveis:**
- Entradas existentes são **imutáveis** — nunca altere id, arquivo, tipo ou descricao após aplicação
- Sempre adicione **no final** — a ordem é a ordem de execução
- O arquivo referenciado é **imutável** após aplicação — alterar o arquivo quebra a verificação de checksum
- Para corrigir algo já aplicado: **crie uma nova migration**

### Workflow completo de alteração

```bash
# 1. Criar o script de alteração
cat > db/tables/alter/003_tb_clientes_add_col_cpf.sql << SQL
-- alter/003_tb_clientes_add_col_cpf.sql
-- DB-011 — Adicionar coluna cpf em tb_clientes
ALTER TABLE tb_clientes ADD (cpf VARCHAR2(14));
CREATE UNIQUE INDEX idx_clientes_cpf ON tb_clientes (cpf);
SQL

# 2. Adicionar no changelog.yml (no final)
cat >> db/changelog.yml << YAML
  - id: "DB-011"
    arquivo: "tables/alter/003_tb_clientes_add_col_cpf.sql"
    tipo: "ddl"
    descricao: "tb_clientes — adicionar coluna cpf com índice único"
YAML

# 3. Commitar os dois arquivos juntos
git add db/tables/alter/003_tb_clientes_add_col_cpf.sql db/changelog.yml
git commit -m "db(DB-011): tb_clientes add col cpf"

# 4. CI/CD (ou manual) aplica no ambiente
./scripts/apply-changelog.sh dev

# 5. Atualizar o DDL atual após aplicação
./scripts/export-db.sh ms_app tables
git add db/tables/tb_clientes.sql
git commit -m "db: atualiza DDL tb_clientes após DB-011"
```

### Comportamento do apply-changelog.sh

| Situação | Ação |
|---|---|
| Migration não aplicada | Executa o script, registra em `db_changelog` |
| Migration aplicada, checksum OK | Pula silenciosamente |
| Migration aplicada, checksum diferente | **ERRO** — arquivo foi alterado após aplicação |
| Arquivo referenciado não existe | **ERRO** — interrompe deploy |
| Erro na execução do script | **ERRO** — interrompe deploy, migrations seguintes não executadas |

### Integração com deploy-full.sh

`apply-changelog.sh` substitui `deploy-db.sh` em deploys incrementais (CI/CD).
`deploy-db.sh` continua útil para setup inicial do zero (novo ambiente).

```bash
# deploy-full.sh pode chamar apply-changelog em vez de deploy-db:
./scripts/apply-changelog.sh "${ENVIRONMENT}"
```
