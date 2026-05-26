# ORDS Data Dictionary — Estrutura, Nomenclatura e Compatibilidade

Referência para consulta e uso correto das views do dicionário do Oracle REST Data Services (ORDS). Cobre hierarquia `USER_ORDS_*` / `DBA_ORDS_*`, schema interno `ORDS_METADATA`, nomenclatura de colunas, mapa por categoria, evolução de versões (18.x a 25.x), impacto de edição Oracle, queries práticas de auditoria e fontes confiáveis.

---

## 1. Como funciona o dicionário ORDS

### Schema interno: ORDS_METADATA

ORDS armazena toda sua configuração (módulos, templates, handlers, roles, OAuth clients, JWT profiles) em tabelas internas no schema `ORDS_METADATA`. **Nunca consulte as tabelas base diretamente** — estrutura interna muda entre versões sem aviso.

```sql
-- Versão ORDS instalada e schema de metadados
SELECT *
  FROM ords_metadata.ords_version;

-- Alternativa via REST (endpoint _/db-api/stable/metadata-catalog/)
-- ou via ORDS_EXPORT
SELECT ORDS_EXPORT.export_schema(
         p_include_modules      => FALSE,
         p_include_privileges   => FALSE,
         p_include_roles        => FALSE,
         p_include_oauth        => FALSE,
         p_include_rest_objects => FALSE,
         p_include_jwt_profiles => FALSE,
         p_include_enable_schema => TRUE,
         p_export_date           => TRUE
       ) AS ddl_export
  FROM dual;
```

### USER_ORDS_* vs DBA_ORDS_*

| Prefixo | Escopo | Quem acessa | Disponível desde |
|---|---|---|---|
| `USER_ORDS_*` | Schema corrente | Qualquer usuário com REST habilitado | Todas as versões |
| `DBA_ORDS_*` | Todos os schemas da instância | Role `ORDS_ADMINISTRATOR` obrigatória | **ORDS 24.4** |

```sql
-- Listar todas as USER_ORDS_* disponíveis
SELECT object_name
  FROM all_objects
 WHERE object_name LIKE 'USER_ORDS%'
   AND object_type = 'VIEW'
 ORDER BY object_name;

-- Listar todas as DBA_ORDS_* disponíveis (ORDS 24.4+)
SELECT object_name
  FROM all_objects
 WHERE object_name LIKE 'DBA_ORDS%'
   AND object_type = 'VIEW'
 ORDER BY object_name;
```

### Relação com as APIs PL/SQL

Cada view corresponde diretamente aos objetos criados pelas APIs `ORDS.*`:

| API PL/SQL | View de leitura |
|---|---|
| `ORDS.enable_schema(...)` | `USER_ORDS_SCHEMAS` |
| `ORDS.define_module(...)` | `USER_ORDS_MODULES` |
| `ORDS.define_template(...)` | `USER_ORDS_TEMPLATES` |
| `USER_ORDS.define_handler(...)` | `USER_ORDS_HANDLERS` |
| `ORDS.define_parameter(...)` | `USER_ORDS_PARAMETERS` |
| `ORDS.create_role(...)` | `USER_ORDS_ROLES` |
| `ORDS.define_privilege(...)` | `USER_ORDS_PRIVILEGES` |
| `ORDS_SECURITY.create_client(...)` *(24.4+)* | `USER_ORDS_CLIENTS` |
| `ORDS.enable_object(...)` *(AutoREST)* | `USER_ORDS_ENABLED_OBJECTS` |

---

## 2. Hierarquia de objetos ORDS e suas views

```
USER_ORDS_SCHEMAS              ← Schema habilitado para REST
       │
USER_ORDS_MODULES              ← Módulo (grupo de endpoints)
       │
USER_ORDS_TEMPLATES            ← Template (URI pattern: /recurso/:id)
       │
USER_ORDS_HANDLERS             ← Handler (método HTTP: GET/POST/PUT/DELETE)
       │
USER_ORDS_PARAMETERS           ← Parâmetros do handler

USER_ORDS_ROLES                ← Roles de autorização
USER_ORDS_PRIVILEGES           ← Privileges (ligam patterns a roles)
USER_ORDS_PRIVILEGE_ROLES      ← Roles atribuídas a cada privilege
USER_ORDS_PRIVILEGE_MODULES    ← Módulos protegidos por cada privilege
USER_ORDS_PRIVILEGE_MAPPINGS   ← Mapeamento de URIs para privileges

USER_ORDS_CLIENTS              ← OAuth2 clients (ORDS_SECURITY 24.4+)
USER_ORDS_CLIENT_PRIVILEGES    ← Privileges de cada client
USER_ORDS_CLIENT_ROLES         ← Roles de cada client

USER_ORDS_ENABLED_OBJECTS      ← Tabelas/views com AutoREST habilitado
USER_ORDS_OBJECTS              ← Objetos REST-enabled
USER_ORDS_OBJ_MEMBERS          ← Colunas dos objetos REST-enabled

USER_ORDS_JWT_PROFILE          ← JWT Profiles configurados
USER_ORDS_PROPERTIES           ← Propriedades customizadas do schema
USER_ORDS_SERVICES             ← Serviços ORDS (view combinada)
USER_ORDS_APPROVALS            ← Approvals para OAuth implicit flow
USER_ORDS_PENDING_APPROVALS    ← Approvals pendentes
USER_ORDS_PREDISPATCH_TASKS    ← Pre-dispatch tasks configuradas
```

---

## 3. Nomenclatura interna de colunas

### Identificadores

| Coluna | Tipo | Significado |
|---|---|---|
| `ID` | NUMBER | Identificador interno único (use como FK entre views) |
| `MODULE_ID` | NUMBER | FK para `USER_ORDS_MODULES.ID` |
| `TEMPLATE_ID` | NUMBER | FK para `USER_ORDS_TEMPLATES.ID` |
| `PARSING_SCHEMA` | VARCHAR2 | Schema Oracle que executa o handler |
| `NAME` | VARCHAR2 | Nome do módulo/role/privilege |
| `PATTERN` | VARCHAR2 | Schema URL pattern (`api`, `v1`) |
| `URI_PREFIX` | VARCHAR2 | Base path do módulo (`/recurso/v1/`) |
| `URI_TEMPLATE` | VARCHAR2 | Pattern do template (`:id`, `/acao`) |

### Status e flags

| Coluna | Valores | Significado |
|---|---|---|
| `STATUS` | `PUBLISHED` / `NOT_PUBLISHED` | Módulo visível externamente |
| `AUTO_REST_AUTH` | `ENABLED` / `DISABLED` | AutoREST exige autenticação |
| `TYPE` | `BASE_PATH` / `BASE_URL` | Tipo de mapeamento do schema |
| `METHOD` | `GET` `POST` `PUT` `DELETE` `PATCH` | Método HTTP do handler |
| `SOURCE_TYPE` | ver tabela abaixo | Tipo de implementação do handler |

### Source types dos handlers

| SOURCE_TYPE | Significado |
|---|---|
| `plsql/block` | Bloco PL/SQL completo |
| `collection/query` | SELECT → JSON collection automático |
| `collection/item` | SELECT → 1 item JSON |
| `collection/feed` | SELECT → feed ORDS padrão com links |
| `media/blob` | BLOB → binário (imagens, PDFs) |
| `csv/query` | SELECT → CSV |
| `mle/javascript` | Função JavaScript (MLE — Oracle 21c+, ORDS 24.1.1+) |

### Parâmetros dos handlers

| Coluna em USER_ORDS_PARAMETERS | Significado |
|---|---|
| `NAME` | Nome do parâmetro (`:id`, `:status`) |
| `PARAM_TYPE` | `PATH` / `QUERY` / `HEADER` / `BODY` / `RESPONSE` |
| `HANDLER_ID` | FK para `USER_ORDS_HANDLERS.ID` |
| `ACCESS_METHOD` | `IN` / `OUT` / `INOUT` |
| `SOURCE_TYPE` | `URI` / `HEADER` / `BODY` / `RESPONSE` |

---

## 4. Mapa por categoria — views mais importantes

### Schemas habilitados

```sql
-- Schemas com REST habilitado e seus patterns de URL
SELECT id, parsing_schema, type, pattern, status, auto_rest_auth
  FROM user_ords_schemas
 ORDER BY parsing_schema;
```

| Coluna | Valores típicos |
|---|---|
| `TYPE` | `BASE_PATH` (path relativo) / `BASE_URL` (URL completa) |
| `PATTERN` | Ex: `api`, `v1`, `public` — aparece como `/ords/api/` |
| `STATUS` | `ENABLED` / `DISABLED` |
| `AUTO_REST_AUTH` | `ENABLED` = AutoREST exige auth |

### Módulos, Templates e Handlers

```sql
-- Inventário completo: módulo → template → handler → source
SELECT
    m.name           AS modulo,
    m.uri_prefix     AS base_path,
    m.status         AS status_modulo,
    t.uri_template   AS template,
    h.method         AS metodo_http,
    h.source_type    AS tipo_source,
    SUBSTR(h.source, 1, 100) AS source_preview
  FROM user_ords_modules   m
  JOIN user_ords_templates t ON t.module_id   = m.id
  JOIN user_ords_handlers  h ON h.template_id = t.id
 ORDER BY m.name, t.uri_template, h.method;
```

**Colunas-chave de USER_ORDS_MODULES:**

| Coluna | Significado |
|---|---|
| `NAME` | Nome do módulo (ex: `contratos.v1`) |
| `URI_PREFIX` | Path base (`/contratos/v1/`) |
| `ITEMS_PER_PAGE` | Paginação padrão (default: 25) |
| `STATUS` | `PUBLISHED` / `NOT_PUBLISHED` |
| `ORIGINS_ALLOWED` | Domínios CORS permitidos |
| `COMMENTS` | Documentação do módulo |

**Colunas-chave de USER_ORDS_TEMPLATES:**

| Coluna | Significado |
|---|---|
| `URI_TEMPLATE` | Pattern (`:id`, `/acao`, `/sub/:sub_id`) |
| `PRIORITY` | Prioridade de roteamento (menor = maior prioridade) |
| `ETAG_TYPE` | `HASH` / `NONE` / `QUERY` — cache ETag |
| `ETAG_QUERY` | Query para gerar ETag customizado |
| `MODULE_ID` | FK para módulo pai |

**Colunas-chave de USER_ORDS_HANDLERS:**

| Coluna | Significado |
|---|---|
| `METHOD` | `GET` / `POST` / `PUT` / `DELETE` / `PATCH` |
| `SOURCE_TYPE` | Tipo de implementação (ver seção 3) |
| `SOURCE` | Código PL/SQL ou SQL do handler |
| `ITEMS_PER_PAGE` | Override de paginação do handler (0 = sem paginação) |
| `MIMES_ALLOWED` | MIME types aceitos (ex: `application/json`) |
| `TEMPLATE_ID` | FK para template pai |

### Segurança — Roles e Privileges

```sql
-- Roles definidas no schema
SELECT name, comments
  FROM user_ords_roles
 ORDER BY name;

-- Privileges e seus patterns protegidos
SELECT p.name, p.label, p.description, pm.pattern
  FROM user_ords_privileges p
  JOIN user_ords_privilege_mappings pm ON pm.privilege_id = p.id
 ORDER BY p.name, pm.pattern;

-- Roles atribuídas a cada privilege
SELECT p.name AS privilege, r.name AS role
  FROM user_ords_privileges p
  JOIN user_ords_privilege_roles pr ON pr.privilege_id = p.id
  JOIN user_ords_roles r ON r.id = pr.role_id
 ORDER BY p.name;

-- Módulos protegidos por privilege
SELECT p.name AS privilege, m.name AS modulo
  FROM user_ords_privileges p
  JOIN user_ords_privilege_modules pm ON pm.privilege_id = p.id
  JOIN user_ords_modules m ON m.id = pm.module_id
 ORDER BY p.name;
```

### OAuth 2.0 Clients

**ATENÇÃO — depreciação crítica em ORDS 24.4:**

| Pacote | Status | Substituído por |
|---|---|---|
| `OAUTH` | ⛔ Depreciado em 24.4, **removido em ORDS 25.3** | `ORDS_SECURITY` |
| `OAUTH_ADMIN` | ⛔ Depreciado em 24.4, **removido em ORDS 25.3** | `ORDS_SECURITY_ADMIN` |

```sql
-- Clients OAuth cadastrados
SELECT c.name, c.grant_type, c.status, c.description,
       cr.name AS role_atribuida
  FROM user_ords_clients c
  LEFT JOIN user_ords_client_roles cr ON cr.client_id = c.id
 ORDER BY c.name;

-- Privileges de cada client
SELECT c.name AS client, p.name AS privilege
  FROM user_ords_clients c
  JOIN user_ords_client_privileges cp ON cp.client_id = c.id
  JOIN user_ords_privileges p ON p.id = cp.privilege_id
 ORDER BY c.name;
```

Valores de `GRANT_TYPE`:

| Valor | Fluxo OAuth |
|---|---|
| `client_credentials` | Server-to-server (sem usuário) |
| `authorization_code` | Usuário autentica (com redirect) |
| `implicit` | Browser-only (depreciado no OAuth 2.1) |
| `password` | Resource Owner Password (descontinuado) |

### AutoREST — objetos REST-enabled

AutoREST habilita tabelas e views para REST sem código PL/SQL. Usa `ORDS.enable_object()`.

```sql
-- Objetos com AutoREST habilitado
SELECT object_name, object_type, object_alias,
       auto_rest_auth, enable_dml
  FROM user_ords_enabled_objects
 ORDER BY object_name;

-- Colunas expostas por cada objeto AutoREST
SELECT o.object_name, m.column_name, m.column_type,
       m.access_control_allow_null
  FROM user_ords_enabled_objects o
  JOIN user_ords_obj_members m ON m.object_id = o.object_id
 ORDER BY o.object_name, m.column_name;
```

**Colunas-chave de USER_ORDS_ENABLED_OBJECTS:**

| Coluna | Significado |
|---|---|
| `OBJECT_ALIAS` | Alias na URL (`/ords/api/alias/`) — default: nome da tabela em minúsculas |
| `AUTO_REST_AUTH` | `ENABLED` = requer autenticação para todos os métodos |
| `ENABLE_DML` | `TRUE` = POST/PUT/DELETE habilitados (além do GET) |
| `OBJECT_TYPE` | `TABLE` / `VIEW` / `PROCEDURE` / `FUNCTION` |

### JWT Profiles (23.x+)

```sql
-- JWT Profiles configurados no schema
SELECT profile_name, issuer, jwt_claim_key, jwt_claim_value
  FROM user_ords_jwt_profile
 ORDER BY profile_name;
```

### Pre-Authenticated Requests — PAR (24.4+)

PAR permite criar URIs temporárias com autenticação embutida, sem expor credenciais OAuth.

```sql
-- PAR tokens ativos (via ORDS_PAR package)
-- Não há view USER_ORDS_* diretamente; gerencie via ORDS_PAR API:
-- ORDS_PAR.define_for_handler(...)
-- ORDS_PAR.revoke(...)

-- Verificar endpoints com PAR via USER_ORDS_HANDLERS
SELECT h.method, t.uri_template, h.source_type
  FROM user_ords_handlers h
  JOIN user_ords_templates t ON t.id = h.template_id
 WHERE h.source_type = 'par/token'
 ORDER BY t.uri_template;
```

### Propriedades customizadas

```sql
-- Propriedades ORDS configuradas no schema (ex: timezone, max_page_size)
SELECT name, value
  FROM user_ords_properties
 ORDER BY name;
```

---

## 5. DBA_ORDS_* — visão cross-schema (ORDS 24.4+)

Mesma estrutura das `USER_ORDS_*`, mas com coluna adicional `SCHEMA` identificando o schema proprietário. Requer role `ORDS_ADMINISTRATOR`.

```sql
-- Todos os módulos de todos os schemas
SELECT schema, name AS modulo, uri_prefix, status
  FROM dba_ords_modules
 ORDER BY schema, name;

-- Todos os handlers expostos na instância (inventário de endpoints)
SELECT
    s.schema,
    m.name       AS modulo,
    m.uri_prefix AS base_path,
    t.uri_template,
    h.method,
    h.source_type
  FROM dba_ords_schemas   s
  JOIN dba_ords_modules   m ON m.schema = s.schema
  JOIN dba_ords_templates t ON t.module_id = m.id
  JOIN dba_ords_handlers  h ON h.template_id = t.id
 ORDER BY s.schema, m.name, t.uri_template, h.method;

-- Schemas com AutoREST sem autenticação (risco de segurança)
SELECT schema, object_name, object_type, object_alias
  FROM dba_ords_enabled_objects
 WHERE auto_rest_auth = 'DISABLED'
 ORDER BY schema, object_name;
```

**Lista completa DBA_ORDS_* (adicionadas em ORDS 24.4):**

```
DBA_ORDS_APPROVALS          DBA_ORDS_PRIVILEGE_MAPPINGS
DBA_ORDS_CLIENTS            DBA_ORDS_PRIVILEGE_MODULES
DBA_ORDS_CLIENT_PRIVILEGES  DBA_ORDS_PRIVILEGE_ROLES
DBA_ORDS_CLIENT_ROLES       DBA_ORDS_PROPERTIES
DBA_ORDS_ENABLED_OBJECTS    DBA_ORDS_ROLES
DBA_ORDS_HANDLERS           DBA_ORDS_SCHEMAS
DBA_ORDS_JWT_PROFILE        DBA_ORDS_SERVICES
DBA_ORDS_MODULES            DBA_ORDS_TEMPLATES
DBA_ORDS_OBJECTS            
DBA_ORDS_OBJ_MEMBERS        
DBA_ORDS_PARAMETERS         
DBA_ORDS_PENDING_APPROVALS  
DBA_ORDS_PREDISPATCH_TASKS  
DBA_ORDS_PRIVILEGES         
```

---

## 6. Queries práticas de auditoria

### Endpoints sem autenticação

```sql
-- Handlers em módulos publicados sem privilege mapeado
SELECT m.name AS modulo, t.uri_template, h.method
  FROM user_ords_modules   m
  JOIN user_ords_templates t ON t.module_id   = m.id
  JOIN user_ords_handlers  h ON h.template_id = t.id
 WHERE m.status = 'PUBLISHED'
   AND NOT EXISTS (
     SELECT 1
       FROM user_ords_privilege_modules pm
      WHERE pm.module_id = m.id
   )
 ORDER BY m.name, t.uri_template, h.method;
```

### AutoREST exposto sem autenticação

```sql
SELECT object_name, object_type, object_alias, enable_dml
  FROM user_ords_enabled_objects
 WHERE auto_rest_auth = 'DISABLED'
   AND enable_dml = 'TRUE'   -- DML sem auth = crítico
 ORDER BY object_name;
```

### Inventário de clients OAuth com seus privileges

```sql
SELECT
    c.name          AS client,
    c.grant_type,
    c.status,
    p.name          AS privilege,
    pm.pattern      AS uri_protegido
  FROM user_ords_clients c
  JOIN user_ords_client_privileges cp ON cp.client_id   = c.id
  JOIN user_ords_privileges        p  ON p.id           = cp.privilege_id
  JOIN user_ords_privilege_mappings pm ON pm.privilege_id = p.id
 ORDER BY c.name, p.name;
```

### Handlers com source type PL/SQL (auditoria de código)

```sql
-- Lista handlers PL/SQL com preview do código (para revisão de segurança)
SELECT
    m.name       AS modulo,
    t.uri_template,
    h.method,
    SUBSTR(h.source, 1, 200) AS codigo_preview
  FROM user_ords_modules   m
  JOIN user_ords_templates t ON t.module_id   = m.id
  JOIN user_ords_handlers  h ON h.template_id = t.id
 WHERE h.source_type = 'plsql/block'
   AND UPPER(h.source) LIKE '%EXECUTE IMMEDIATE%'  -- SQL dinâmico — revisar
 ORDER BY m.name;
```

### Export de configuração para deploy / backup

```sql
-- Gera script PL/SQL completo do schema para migration/CI-CD
DECLARE
  l_ddl CLOB;
BEGIN
  l_ddl := ORDS_EXPORT.export_schema(
              p_include_modules       => TRUE,
              p_include_privileges    => TRUE,
              p_include_roles         => TRUE,
              p_include_oauth         => TRUE,
              p_include_rest_objects  => TRUE,
              p_include_jwt_profiles  => TRUE,
              p_include_enable_schema => TRUE,
              p_export_date           => TRUE
            );
  -- Gravar em arquivo, tabela de controle de versão, ou enviar via UTL_HTTP
  DBMS_OUTPUT.put_line(SUBSTR(l_ddl, 1, 32767));
END;
/
```

---

## 7. Evolução por versão — ORDS 18.x a 25.x

### ORDS 18.x / 19.x / 20.x / 21.x

**Base estável disponível:**
- `USER_ORDS_SCHEMAS`, `USER_ORDS_MODULES`, `USER_ORDS_TEMPLATES`, `USER_ORDS_HANDLERS`
- `USER_ORDS_PARAMETERS`, `USER_ORDS_ROLES`, `USER_ORDS_PRIVILEGES`
- `USER_ORDS_PRIVILEGE_MAPPINGS`, `USER_ORDS_PRIVILEGE_MODULES`, `USER_ORDS_PRIVILEGE_ROLES`
- `USER_ORDS_CLIENTS`, `USER_ORDS_CLIENT_PRIVILEGES`, `USER_ORDS_CLIENT_ROLES`
- `USER_ORDS_ENABLED_OBJECTS`, `USER_ORDS_OBJECTS`, `USER_ORDS_OBJ_MEMBERS`
- Gestão OAuth: `OAUTH` e `OAUTH_ADMIN` packages (ainda válidos)

---

### ORDS 22.x / 23.x

**Introduzido:**
- `USER_ORDS_JWT_PROFILE` — JWT Profiles declarativos por schema
- `USER_ORDS_PROPERTIES` — propriedades customizadas do schema
- `USER_ORDS_APPROVALS`, `USER_ORDS_PENDING_APPROVALS` — aprovações OAuth
- `USER_ORDS_PREDISPATCH_TASKS` — pre-dispatch tasks

---

### ORDS 24.1 (Abril 2024)

**Novidades que impactam o dicionário:**
- Suporte a `mle/javascript` como `SOURCE_TYPE` em handlers (Oracle 21c+ com MLE)
- Bind implícito `:body_json` — parseia body JSON automaticamente
- Metadata Caching habilitado por padrão (1 segundo) — impacto em latência de leitura de views
- AutoREST para JSON-Relational Duality Views (Oracle 23ai)

---

### ORDS 24.4 (Dezembro 2024) — mudança crítica de segurança

**Novas views `DBA_ORDS_*` (lista completa na seção 5)**

**Novo pacote `ORDS_PAR`** — Pre-Authenticated Requests:
- Cria URIs temporárias com autenticação embutida
- `ORDS_PAR.define_for_handler(p_module_name, p_pattern, p_method, p_duration)`
- `ORDS_PAR.revoke(p_par_id)`

**Depreciação do OAUTH / OAUTH_ADMIN:**

| Pacote antigo | Substituição em 24.4 | Removido em |
|---|---|---|
| `OAUTH.create_client(...)` | `ORDS_SECURITY.create_client(...)` | ORDS 25.3 |
| `OAUTH.grant_client_role(...)` | `ORDS_SECURITY.grant_client_role(...)` | ORDS 25.3 |
| `OAUTH_ADMIN.revoke_client_token(...)` | `ORDS_SECURITY_ADMIN.revoke_client_token(...)` | ORDS 25.3 |

**Ação requerida:** Qualquer código que use `OAUTH.*` ou `OAUTH_ADMIN.*` precisou ser migrado antes de ORDS 25.3 (outubro 2025). Em instalações ORDS 25.3+, essas chamadas resultam em erro.

---

### ORDS 25.1 / 25.2 (2025)

**Introduzido:**
- JWT Profiles configuráveis no nível de pool de conexão (não apenas schema)
- `USER_ORDS_JWT_PROFILE` expandido com atributos de pool-level JWT
- Novo comando CLI: `ords config --db-pool [pool] verify`
- Acesso log de ORDS Standalone atualizado com `app_id` e `page_id` APEX

---

### ORDS 25.4 (atual)

**Notas:**
- `ORDS_EXPORT.export_schema()` corrigido para incluir parâmetro `p_mle_env_name` na saída
- Comportamento de redirecionamento URL stricto (herdado de 24.4) mantido

---

## 8. Impacto Oracle Edition nas features ORDS

ORDS não é uma feature de licença Oracle — é uma aplicação separada. Porém algumas features do banco que ORDS expõe dependem de edição:

| Feature ORDS / View | SE2 | EE | Observação |
|---|:---:|:---:|---|
| `USER_ORDS_*` / `DBA_ORDS_*` | ✅ | ✅ | Views ORDS, sem relação com edição |
| AutoREST em tabelas/views | ✅ | ✅ | Sem restrição de edição |
| AutoREST em JSON Duality Views | ❌ | ✅ (23ai+) | Requer Oracle 23ai/26ai EE |
| Handler `mle/javascript` | ❌ | ✅ (21c+) | MLE é feature EE (21c+) |
| AutoREST com Partitioning | ❌ | ✅ | Partitioning é opção EE |
| `source_type_media` (BLOB) | ✅ | ✅ | Sem restrição |
| RAC — pool de conexões ORDS | ✅ | ✅ | ORDS balanceia nativamente com RAC |
| CDB/PDB — ORDS por PDB | ✅ (21c+ 3 PDBs) | ✅ | ORDS pode ser instalado por PDB |
| ORDS com Data Guard (standby) | ✅ (read-only GET) | ✅ | GET em standby lê; DML falha sem Active DG |

### Como verificar a versão ORDS instalada no banco

```sql
-- Versão do schema ORDS_METADATA
SELECT schema_version
  FROM ords_metadata.schema_version
 FETCH FIRST 1 ROW ONLY;

-- Alternativa via view pública (se disponível)
SELECT *
  FROM ords_metadata.ords_version;

-- Verificar privilégios de admin ORDS do usuário corrente
SELECT granted_role
  FROM session_roles
 WHERE granted_role IN ('ORDS_ADMINISTRATOR', 'ORDS_RUNTIME', 'REST_ADMINISTRATOR');
```

---

## 9. Fontes confiáveis para atualização

### Hierarquia de confiabilidade

```
oracle.com/tools/ords/ords-relnotes-{VER}.html  ← Release Notes oficial por versão
         │
docs.oracle.com/en/database/oracle/oracle-rest-data-services/{VER}/  ← Docs oficial
         │
oracle-base.com/articles/misc/oracle-rest-data-services-ords  ← Tim Hall
         │
followthecoffee.com                             ← Jeff Smith (Oracle Product Manager ORDS)
         │
thatjeffsmith.com                               ← Jeff Smith — queries e dicas ORDS
```

### URLs por versão — padrão de navegação

```
# Release Notes (substituir {VER})
https://www.oracle.com/tools/ords/ords-relnotes-{VER}.html

# Exemplos diretos
https://www.oracle.com/tools/ords/ords-relnotes-24.4.html   ← DBA_ORDS_*, ORDS_PAR, depreciação OAUTH
https://www.oracle.com/tools/ords/ords-relnotes-25.2.html   ← JWT pool-level
https://www.oracle.com/tools/ords/ords-relnotes-25.4.html   ← ORDS_EXPORT fix MLE

# Documentação oficial por versão
https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/{VER}/orddg/

# Onde {VER} = 24.1 | 24.2 | 24.3 | 24.4 | 25.1 | 25.2 | 25.4

# Referência de packages PL/SQL (ORDS, ORDS_EXPORT, ORDS_SECURITY)
https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/25.4/orddg/ords-pl-sql-package-reference.html

# ORDS_EXPORT
https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/25.4/orddg/ords_export-pl-sql-package-reference.html
```

### Tim Hall — oracle-base.com

```
# Artigos ORDS
https://oracle-base.com/articles/misc/oracle-rest-data-services-ords

# Delete ORDS Metadata (com lista completa USER_ORDS_*)
https://oracle-base.com/articles/misc/oracle-rest-data-services-ords-delete-ords-metadata
```

### Jeff Smith — followthecoffee.com / thatjeffsmith.com

```
# ORDS 24.4 highlights (DBA_ORDS_*, ORDS_PAR, ORDS_SECURITY)
https://followthecoffee.com/ords-24-4-release-highlights/

# Queries no dicionário ORDS
https://www.thatjeffsmith.com/archive/2018/01/querying-the-oracle-rest-data-services-for-your-oracle-database/
```

### Query de autodescoberta local

```sql
-- Gerar inventário local de todas as views ORDS disponíveis com comentários
SELECT
    v.object_name AS view_name,
    tc.comments
  FROM all_objects v
  LEFT JOIN all_tab_comments tc ON tc.owner = v.owner
                               AND tc.table_name = v.object_name
 WHERE v.object_name LIKE 'USER_ORDS%'
   AND v.object_type = 'VIEW'
 ORDER BY v.object_name;
```

---

## Linkagem interna

- Para padrões de desenvolvimento (handlers, módulos, templates, OAuth) → `references/ords-rest-services.md`
- Para views Oracle do banco (DBA_*, V$*, AWR) → `references/data-dictionary-ptbr.md`
- Para views APEX (APEX_APPLICATION_*, APEX_WORKSPACE_*) → `references/apex-data-dictionary-ptbr.md`
- Templates ORDS prontos → `assets/ords_module.sql`, `assets/ords_handler.sql`
