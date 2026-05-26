# APEX Data Dictionary — Estrutura, Nomenclatura e Compatibilidade

Referência para consulta e uso correto das views do dicionário do Oracle APEX. Cobre hierarquia de prefixos, nomenclatura de colunas, disponibilidade por versão (19 a 26.1), impacto de edição Oracle, queries práticas de auditoria e fontes confiáveis para atualização.

---

## 1. Como funciona o dicionário APEX

### Schema versionado

Cada versão do APEX instala seu próprio schema. As views públicas são sinônimos apontando para o schema ativo.

```sql
-- Descobrir o schema APEX instalado
SELECT schema, version FROM apex_release;
-- Exemplo de retorno: APEX_240200 / 24.2.0

-- Listar todas as views do dicionário APEX no schema ativo
SELECT view_name, comments
  FROM dba_views
 WHERE owner = 'APEX_240200'    -- substitua pelo schema ativo
   AND view_name LIKE 'APEX%'
 ORDER BY view_name;
```

O mesmo resultado via sinônimo público (sem especificar schema):

```sql
-- Equivalente — via APEX_DICTIONARY (ponto de entrada oficial)
SELECT apex_view_name, comments
  FROM apex_dictionary
 WHERE column_id = 0   -- column_id = 0 = linha da view, não coluna
 ORDER BY apex_view_name;
```

### APEX_DICTIONARY — o meta-dicionário

`APEX_DICTIONARY` documenta todas as views do APEX, incluindo colunas e relações pai-filho. É o equivalente ao `DICTIONARY` do banco Oracle.

```sql
-- Colunas de uma view específica
SELECT column_name, comments, type_name
  FROM apex_dictionary
 WHERE apex_view_name = 'APEX_APPLICATION_PAGES'
   AND column_id > 0
 ORDER BY column_id;

-- Hierarquia de views (árvore pai-filho via APEX_DICTIONARY)
SELECT LPAD(' ', (LEVEL - 1) * 2) || apex_view_name AS hierarquia, comments
  FROM (
    SELECT 'ROOT' apex_view_name, NULL comments, NULL parent_view FROM dual
    UNION ALL
    SELECT apex_view_name, comments, NVL(parent_view, 'ROOT')
      FROM apex_dictionary WHERE column_id = 0
  )
 CONNECT BY PRIOR apex_view_name = parent_view
 START WITH parent_view IS NULL
 ORDER SIBLINGS BY apex_view_name;
```

### Escopo de visibilidade: workspace vs instância

| Prefixo | Escopo | Quem acessa |
|---|---|---|
| `APEX_APPLICATION_*` | Workspace corrente | Developer, DBA |
| `APEX_APPL_*` | Workspace corrente | Developer (componentes específicos) |
| `APEX_WORKSPACE_*` | Workspace corrente | Developer, Admin workspace |
| `APEX_INSTANCE_*` | Toda a instância APEX | Admin de instância (ADMIN) |
| `APEX_PATCHES` | Toda a instância | DBA |
| `WWV_FLOW_*` | Interno (sem suporte) | Não usar — muda entre versões sem aviso |

---

## 2. Hierarquia de prefixos

```
APEX_INSTANCE_*          ← Configuração global da instância (admin only)
       │
APEX_WORKSPACE_*         ← Monitoramento e configuração do workspace
       │
APEX_APPLICATIONS        ← Aplicações do workspace
       │
APEX_APPLICATION_PAGES   ← Páginas da aplicação
       │
APEX_APPLICATION_PAGE_REGIONS    ← Regiões por página
APEX_APPLICATION_PAGE_ITEMS      ← Items por página
APEX_APPLICATION_PAGE_PROCESS    ← Processos por página
APEX_APPLICATION_PAGE_VAL        ← Validações por página
APEX_APPLICATION_PAGE_DA         ← Dynamic Actions por página
       │
APEX_APPL_*              ← Componentes de nível aplicação (ACL, AI, Workflow)
```

### Quando usar cada prefixo

| Objetivo | View recomendada |
|---|---|
| Inventário de aplicações | `APEX_APPLICATIONS` |
| Auditoria de páginas | `APEX_APPLICATION_PAGES` |
| Auditoria de segurança (items, autenticação) | `APEX_APPLICATION_PAGES` + `APEX_APPLICATION_PAGE_ITEMS` |
| Monitoramento de uso em tempo real | `APEX_WORKSPACE_ACTIVITY_LOG` / `APEX_ACTIVITY_LOG` |
| Configuração da instância | `APEX_INSTANCE_PARAMETERS` |
| Controle de acesso (ACL) | `APEX_APPL_ACL_USERS` (24.1+) |
| Workflows e Tasks | `APEX_APPL_TASKS`, `APEX_APPL_TASK_PARAMS` (22+) |
| Configuração de AI | `APEX_APPL_AI_CONFIGS` (24.1+) |

---

## 3. Nomenclatura interna de colunas APEX

### Identificadores

| Coluna | Tipo | Significado |
|---|---|---|
| `APPLICATION_ID` | NUMBER | ID numérico único da aplicação no workspace |
| `PAGE_ID` | NUMBER | ID da página (único dentro da aplicação) |
| `REGION_ID` | NUMBER | ID interno da região |
| `ITEM_ID` | NUMBER | ID interno do item |
| `WORKSPACE_ID` | NUMBER | ID numérico do workspace (interno) |
| `WORKSPACE` | VARCHAR2 | Nome do workspace (legível) |

### Static ID vs Name vs Alias

| Coluna | Uso |
|---|---|
| `APPLICATION_ALIAS` | Alias amigável da aplicação (usado em URLs friendly) |
| `PAGE_ALIAS` | Alias da página para URL friendly |
| `STATIC_ID` | ID estático de região/item para JavaScript (`apex.region('static_id')`) |
| `ITEM_NAME` | Nome do item (ex: `P10_CPF`) — referenciado em PL/SQL como `:P10_CPF` |
| `REGION_NAME` | Nome exibível da região |
| `NAME` | Nome interno do componente (depende do objeto) |

### Padrão de nomenclatura de items

```
P{PAGE_ID}_{NOME_NEGOCIO}

Exemplos:
  P10_CPF          → item CPF na página 10
  P0_APP_USER      → item global (página 0)
  P100_STATUS      → item status na página 100
```

### Flags booleanos APEX

APEX usa `VARCHAR2` para booleanos. Padrões comuns:

| Valor `YES` / `NO` | Valor `Y` / `N` |
|---|---|
| `IS_HIDDEN` | `AUTHORIZATION_REQUIRED` |
| `IS_REQUIRED` | `VALUE_PROTECTED` |
| `CACHING_ENABLED` | `STOP_AND_SHOW_FIRST_ERROR` |

### Tipos de região (`REGION_TYPE_PLUGIN_NAME`)

| Valor | Tipo |
|---|---|
| `NATIVE_IR` | Interactive Report |
| `NATIVE_IG` | Interactive Grid |
| `NATIVE_REPORT` | Classic Report |
| `NATIVE_FORM` | Form (single-row) |
| `NATIVE_CHART` | Chart (JET-based) |
| `NATIVE_FACETED_SEARCH` | Faceted Search |
| `NATIVE_SMART_FILTERS` | Smart Filters |
| `NATIVE_MAP_REGION` | Map Region |
| `NATIVE_CARDS` | Cards Region |
| `NATIVE_CALENDAR` | Calendar |
| `NATIVE_WORKFLOW_DIAGRAM` | Workflow Diagram (22+) |
| `PLUGIN_{NOME}` | Plugin customizado |

---

## 4. Mapa por categoria — views mais importantes

### Aplicação

| View | Cobre | Colunas-chave |
|---|---|---|
| `APEX_APPLICATIONS` | Definição das aplicações | `APPLICATION_ID`, `APPLICATION_ALIAS`, `APPLICATION_NAME`, `AUTHENTICATION_SCHEME`, `LOGGING`, `STATUS`, `OWNER`, `VERSION` |
| `APEX_APPLICATION_BUILD_OPTIONS` | Build options (feature flags de deploy) | `APPLICATION_ID`, `BUILD_OPTION_NAME`, `STATUS`, `ON_OR_OFF_SWITCH` |
| `APEX_APPLICATION_THEMES` | Temas ativos | `APPLICATION_ID`, `THEME_NUMBER`, `THEME_NAME`, `UI_TYPE_NAME` |
| `APEX_APPLICATION_SUBSTITUTIONS` | Substituições globais (`&APP_VERSION.`) | `APPLICATION_ID`, `SUBSTITUTION_STRING`, `SUBSTITUTION_VALUE` |
| `APEX_APPLICATION_GROUPS` | Grupos de aplicações | `APPLICATION_ID`, `GROUP_NAME` |

### Páginas

| View | Cobre | Colunas-chave |
|---|---|---|
| `APEX_APPLICATION_PAGES` | Metadados de todas as páginas | `APPLICATION_ID`, `PAGE_ID`, `PAGE_NAME`, `PAGE_MODE` (`Normal`/`Modal Dialog`), `PAGE_ACCESS_PROTECTION`, `AUTHORIZATION_SCHEME`, `PAGE_ALIAS`, `PAGE_TEMPLATE` |
| `APEX_APPLICATION_PAGE_GROUPS` | Grupos de páginas | `APPLICATION_ID`, `PAGE_GROUP` |

Valores de `PAGE_ACCESS_PROTECTION`:

| Valor | Significado |
|---|---|
| `Unrestricted` | Qualquer um acessa — **risco de segurança** |
| `Arguments Must Have Checksum` | Parâmetros precisam de checksum |
| `No Arguments Allowed` | Sem argumentos na URL |
| `Page Is Public` | Página pública explícita |

### Regiões

| View | Cobre | Colunas-chave |
|---|---|---|
| `APEX_APPLICATION_PAGE_REGIONS` | Todas as regiões | `APPLICATION_ID`, `PAGE_ID`, `REGION_NAME`, `REGION_TYPE_PLUGIN_NAME`, `SOURCE`, `AUTHORIZATION_SCHEME`, `STATIC_ID` |
| `APEX_APPLICATION_PAGE_IR` | Interactive Reports | `APPLICATION_ID`, `PAGE_ID`, `REGION_ID`, `PAGINATION_TYPE`, `ROWS_PER_PAGE` |
| `APEX_APPLICATION_PAGE_IR_COL` | Colunas dos IRs | `APPLICATION_ID`, `PAGE_ID`, `REGION_ID`, `COLUMN_ALIAS`, `COLUMN_TYPE`, `COLUMN_LABEL`, `IS_SORTABLE`, `IS_HIDDEN` |
| `APEX_APPLICATION_PAGE_IG` | Interactive Grids | `APPLICATION_ID`, `PAGE_ID`, `REGION_ID`, `EDIT_ENABLED` |
| `APEX_APPLICATION_PAGE_IG_COL` | Colunas dos IGs | `APPLICATION_ID`, `PAGE_ID`, `REGION_ID`, `COLUMN_NAME`, `IS_PRIMARY_KEY`, `COLUMN_TYPE` |
| `APEX_APPLICATION_PAGE_RPT` | Classic Reports | `APPLICATION_ID`, `PAGE_ID`, `REGION_ID`, `PAGINATION_TYPE` |

### Items

| View | Cobre | Colunas-chave |
|---|---|---|
| `APEX_APPLICATION_PAGE_ITEMS` | Todos os items | `APPLICATION_ID`, `PAGE_ID`, `ITEM_NAME`, `DISPLAY_AS`, `IS_REQUIRED`, `VALUE_PROTECTED`, `AUTHORIZATION_SCHEME`, `ITEM_DEFAULT`, `ITEM_SOURCE` |
| `APEX_APPLICATION_ITEMS` | Items globais (Application Items) | `APPLICATION_ID`, `ITEM_NAME`, `ITEM_SCOPE` |

Tipos comuns em `DISPLAY_AS`:

| Valor | Tipo de item |
|---|---|
| `NATIVE_TEXT_FIELD` | Text Field |
| `NATIVE_SELECT_LIST` | Select List |
| `NATIVE_POPUP_LOV` | Popup LOV |
| `NATIVE_DATE_PICKER_APEX` | Date Picker (APEX nativo) |
| `NATIVE_HIDDEN` | Hidden |
| `NATIVE_DISPLAY_ONLY` | Display Only |
| `NATIVE_SWITCH` | Switch (boolean) |
| `NATIVE_FILE` | File Browser |
| `NATIVE_SELECT_ONE` | Select One (24.1+) |
| `NATIVE_SELECT_MANY` | Select Many (24.1+) |

### Processos, Validações e Computações

| View | Cobre | Colunas-chave |
|---|---|---|
| `APEX_APPLICATION_PAGE_PROC` | Page Processes | `APPLICATION_ID`, `PAGE_ID`, `PROCESS_NAME`, `PROCESS_TYPE`, `PROCESS_POINT`, `AUTHORIZATION_SCHEME`, `PROCESS_SEQUENCE` |
| `APEX_APPLICATION_PAGE_VAL` | Validações | `APPLICATION_ID`, `PAGE_ID`, `VALIDATION_NAME`, `VALIDATION_TYPE`, `ASSOCIATED_ITEM`, `ERROR_MESSAGE` |
| `APEX_APPLICATION_PAGE_COMP` | Computações | `APPLICATION_ID`, `PAGE_ID`, `ITEM_NAME`, `COMPUTATION_TYPE`, `COMPUTATION_POINT` |
| `APEX_APPLICATION_PROCESS` | Application Processes (globais) | `APPLICATION_ID`, `PROCESS_NAME`, `PROCESS_TYPE`, `PROCESS_POINT` |
| `APEX_APPLICATION_COMPUTATIONS` | Application Computations (globais) | `APPLICATION_ID`, `ITEM_NAME`, `COMPUTATION_TYPE` |

### Dynamic Actions

| View | Cobre | Colunas-chave |
|---|---|---|
| `APEX_APPLICATION_PAGE_DA` | Dynamic Actions | `APPLICATION_ID`, `PAGE_ID`, `DYNAMIC_ACTION_NAME`, `EVENT`, `TRIGGERING_ELEMENT_TYPE`, `TRIGGERING_ELEMENT` |
| `APEX_APPLICATION_PAGE_DA_ACTS` | Ações de cada DA | `APPLICATION_ID`, `PAGE_ID`, `DYNAMIC_ACTION_NAME`, `ACTION`, `ACTION_SEQUENCE`, `FIRE_WHEN_EVENT_RESULT_IS` |

### Shared Components — LOVs, Autenticação, Autorização

| View | Cobre | Colunas-chave |
|---|---|---|
| `APEX_APPLICATION_LOVS` | Lists of Values | `APPLICATION_ID`, `LIST_OF_VALUES_NAME`, `LIST_OF_VALUES_TYPE` (`Static`/`Dynamic`) |
| `APEX_APPLICATION_LIST_ENTRIES` | Entradas de LOVs estáticos | `APPLICATION_ID`, `LIST_OF_VALUES_NAME`, `DISPLAY_VALUE`, `RETURN_VALUE` |
| `APEX_APPLICATION_AUTH` | Authentication Schemes | `APPLICATION_ID`, `AUTHENTICATION_NAME`, `AUTHENTICATION_SCHEME_TYPE` |
| `APEX_APPLICATION_AUTHORIZATION` | Authorization Schemes | `APPLICATION_ID`, `AUTHORIZATION_SCHEME_NAME`, `AUTHORIZATION_SCHEME_TYPE` |
| `APEX_APPLICATION_ALL_AUTH` | Todos os esquemas de auth (auth+authz) | `APPLICATION_ID`, `COMPONENT_NAME`, `AUTHORIZATION_SCHEME` |
| `APEX_APPLICATION_TEMPLATES` | Templates de página | `APPLICATION_ID`, `TEMPLATE_NAME`, `TEMPLATE_TYPE` |

### Navegação

| View | Cobre |
|---|---|
| `APEX_APPLICATION_LISTS` | Navigation Lists |
| `APEX_APPLICATION_LIST_ENTRIES` | Entradas de navigation lists |
| `APEX_APPLICATION_BREADCRUMBS` | Breadcrumbs |
| `APEX_APPLICATION_BC_ENTRIES` | Entradas dos breadcrumbs |
| `APEX_APPLICATION_MENUS` | Menus |
| `APEX_APPLICATION_TREES` | Navigation Trees |

### Workflows e Tasks (22+)

Introduzidos no APEX 22.1. Expandidos significativamente no 23.1, 23.2, 24.1, 24.2.

| View | Cobre | Disponível desde |
|---|---|---|
| `APEX_APPL_TASKS` | Definição de Human Tasks | 22.1 |
| `APEX_APPL_TASK_PARAMS` | Parâmetros de tasks | 22.1 |
| `APEX_APPL_TASK_PARTICIPANTS` | Participantes de tasks | 22.1 |
| `APEX_APPL_WORKFLOWS` | Definição de Workflows | 22.1 |
| `APEX_APPL_WORKFLOW_ACTIVITIES` | Atividades do workflow | 22.1 |
| `APEX_APPL_WORKFLOW_PARAMS` | Parâmetros de workflow | 22.1 |
| `APEX_APPL_WORKFLOW_VARIABLES` | Variáveis de workflow | 23.1 |
| `APEX_TASK_INSTANCES` | Instâncias em runtime | 22.1 |
| `APEX_WORKFLOW_INSTANCES` | Instâncias de workflow em runtime | 22.1 |

```sql
-- Listar workflows ativos em todas as aplicações do workspace
SELECT application_id, workflow_name, workflow_status
  FROM apex_appl_workflows
 ORDER BY application_id, workflow_name;

-- Instâncias de workflow em runtime por estado
SELECT state, COUNT(*) AS qtd
  FROM apex_workflow_instances
 GROUP BY state
 ORDER BY qtd DESC;
```

### AI e Generative AI (24.1+)

| View | Cobre | Disponível desde |
|---|---|---|
| `APEX_APPL_AI_CONFIGS` | Configurações de AI (AI Agent configs) | 24.1 |
| `APEX_APPL_AI_CONFIG_RAG_SRCS` | Fontes RAG (Retrieval-Augmented Generation) | 24.2 |
| `APEX_INSTANCE_AI_PROVIDERS` | AI providers configurados na instância | 24.1 |
| `APEX_WORKSPACE_VECTOR_PROVIDER` | Providers de vector search por workspace | 24.2 |

**Nota 26.1:** `apex_appl_ai_configs` e `apex_appl_ai_config_rag_srcs` foram renomeadas/reestruturadas em 26.1. Scripts que as consultam diretamente devem ser validados após upgrade.

### ACL e Segurança de Aplicação

| View | Cobre | Disponível desde |
|---|---|---|
| `APEX_APPL_ACL_USERS` | Usuários e roles na ACL da aplicação | 18.1 |
| `APEX_APPL_ACL_ROLES` | Roles definidas | 18.1 |
| `APEX_APPL_ACL_USER_ROLES` | Mapeamento usuário-role | 18.1 |

**Nota 24.2:** `APEX_APPL_ACL_USERS` passou a ter `INSTEAD OF TRIGGER` — é possível editar roles via `UPDATE` diretamente na view, o que facilita scripts de manutenção.

```sql
-- Usuários e suas roles em uma aplicação
SELECT u.user_name, r.role_name, u.is_active
  FROM apex_appl_acl_users u
  JOIN apex_appl_acl_user_roles ur ON u.user_name = ur.user_name
                                  AND u.application_id = ur.application_id
  JOIN apex_appl_acl_roles r ON ur.role_id = r.role_id
 WHERE u.application_id = :APP_ID
 ORDER BY u.user_name;
```

### JSON Sources (24.2+)

| View | Cobre |
|---|---|
| `APEX_APPL_JSON_SOURCES` | JSON Sources definidas na aplicação |
| `APEX_APPL_JSON_SOURCE_COLS` | Colunas (data profile) do JSON Source |

```sql
-- JSON Sources disponíveis por aplicação
SELECT application_id, json_source_name, json_source_type
  FROM apex_appl_json_sources
 ORDER BY application_id, json_source_name;
```

### Monitoramento e Auditoria do Workspace

| View | Cobre | Colunas-chave |
|---|---|---|
| `APEX_ACTIVITY_LOG` | Log de atividade do workspace (corrente) | `TIME_STAMP`, `APPLICATION_ID`, `PAGE_ID`, `ELAPSED_TIME`, `USER_NAME`, `IP_ADDRESS`, `SQLERRM` |
| `APEX_WORKSPACE_ACTIVITY_LOG` | Equivalente — às vezes usado como sinônimo | Igual acima |
| `APEX_WORKSPACE_SESSIONS` | Sessões ativas no workspace | `APPLICATION_ID`, `USER_NAME`, `SESSION_ID`, `CREATED_ON`, `LAST_REQUEST_TIMESTAMP` |
| `APEX_WORKSPACE_APEX_USERS` | Usuários do workspace APEX (App Builder) | `USER_NAME`, `IS_DEVELOPER`, `IS_WORKSPACE_ADMIN`, `ACCOUNT_LOCKED` |
| `APEX_WORKSPACE_FILES` | Arquivos carregados no workspace | `FILE_NAME`, `FILE_TYPE`, `FILE_SIZE`, `CREATED_BY`, `CREATED_ON` |
| `APEX_WORKSPACE_SQL_SCRIPTS` | Scripts SQL salvos no SQL Workshop | `SCRIPT_NAME`, `OWNER`, `CREATED_ON` |
| `APEX_WORKSPACE_SCHEMAS` | Schemas associados ao workspace | `WORKSPACE`, `SCHEMA` |
| `APEX_WORKSPACE_DEVELOPERS` | Developers registrados | `USER_NAME`, `EMAIL`, `CREATED_ON`, `LAST_LOGIN` |

### Configuração da Instância APEX

| View | Cobre |
|---|---|
| `APEX_INSTANCE_PARAMETERS` | Parâmetros globais da instância (max sessions, feature flags) |
| `APEX_WORKSPACES` | Todos os workspaces da instância |
| `APEX_PATCHES` | Patches APEX aplicados |
| `APEX_RELEASE` | Versão APEX instalada |

```sql
-- Versão APEX e schema
SELECT version, schema, api_compatibility FROM apex_release;

-- Parâmetros de instância relevantes
SELECT parameter_name, parameter_value
  FROM apex_instance_parameters
 WHERE parameter_name IN (
   'MAX_SESSION_IDLE_SEC',
   'MAX_SESSION_LENGTH_SEC',
   'MAXIMUM_SIMULTANEOUS_REQUESTS',
   'WORKSPACE_PROVISION_MAX_SCHEMAS'
 );

-- Listar workspaces
SELECT workspace, workspace_display_name, schemas_provisioned, allow_rest
  FROM apex_workspaces
 ORDER BY workspace;
```

---

## 5. Queries práticas de auditoria

### Auditoria de segurança — páginas sem controle de acesso

```sql
-- Páginas sem authorization scheme (exceto página de login e home)
SELECT application_id, page_id, page_name, page_access_protection
  FROM apex_application_pages
 WHERE application_id = :APP_ID
   AND authorization_scheme IS NULL
   AND page_id NOT IN (0, 9999)   -- 0 = global, 9999 = login
 ORDER BY page_id;

-- Páginas com acesso irrestrito (sem checksum obrigatório)
SELECT application_id, page_id, page_name
  FROM apex_application_pages
 WHERE application_id = :APP_ID
   AND page_access_protection = 'Unrestricted'
 ORDER BY page_id;
```

### Auditoria de segurança — items sem proteção

```sql
-- Items hidden sem VALUE_PROTECTED (risco mass assignment)
SELECT application_id, page_id, item_name, display_as
  FROM apex_application_page_items
 WHERE application_id = :APP_ID
   AND display_as = 'NATIVE_HIDDEN'
   AND value_protected = 'N'
 ORDER BY page_id, item_name;
```

### Auditoria de paginação em IRs

```sql
-- IRs sem paginação "of Z" (usuário não sabe o total)
SELECT r.application_id, r.page_id, r.region_name, ir.pagination_type
  FROM apex_application_page_regions r
  JOIN apex_application_page_ir ir
    ON r.application_id = ir.application_id
   AND r.page_id = ir.page_id
   AND r.region_id = ir.region_id
 WHERE r.application_id = :APP_ID
   AND ir.pagination_type NOT LIKE '%Z%'
 ORDER BY r.page_id;
```

### Monitoramento de uso — top páginas lentas

```sql
-- Top 20 páginas por tempo médio (últimas 24h)
SELECT application_id, page_id,
       COUNT(*) AS acessos,
       ROUND(AVG(elapsed_time), 3) AS avg_seg,
       ROUND(MAX(elapsed_time), 3) AS max_seg,
       SUM(CASE WHEN sqlerrm IS NOT NULL THEN 1 ELSE 0 END) AS erros
  FROM apex_activity_log
 WHERE time_stamp > SYSDATE - 1
   AND application_id = :APP_ID
 GROUP BY application_id, page_id
 ORDER BY avg_seg DESC
 FETCH FIRST 20 ROWS ONLY;
```

### Inventário completo de componentes por aplicação

```sql
-- Contagem de componentes por tipo
SELECT 'Páginas'          AS tipo, COUNT(*) AS qtd FROM apex_application_pages       WHERE application_id = :APP_ID UNION ALL
SELECT 'Regiões'          AS tipo, COUNT(*) AS qtd FROM apex_application_page_regions WHERE application_id = :APP_ID UNION ALL
SELECT 'Items'            AS tipo, COUNT(*) AS qtd FROM apex_application_page_items   WHERE application_id = :APP_ID UNION ALL
SELECT 'Processos'        AS tipo, COUNT(*) AS qtd FROM apex_application_page_proc    WHERE application_id = :APP_ID UNION ALL
SELECT 'Validações'       AS tipo, COUNT(*) AS qtd FROM apex_application_page_val     WHERE application_id = :APP_ID UNION ALL
SELECT 'Dynamic Actions'  AS tipo, COUNT(*) AS qtd FROM apex_application_page_da      WHERE application_id = :APP_ID UNION ALL
SELECT 'IRs'              AS tipo, COUNT(*) AS qtd FROM apex_application_page_ir       WHERE application_id = :APP_ID UNION ALL
SELECT 'IGs'              AS tipo, COUNT(*) AS qtd FROM apex_application_page_ig       WHERE application_id = :APP_ID
ORDER BY 1;
```

---

## 6. Evolução por versão — APEX 19 a 26.1

### APEX 19.x / 20.x

**Views disponíveis (base estável):**
- `APEX_APPLICATIONS`, `APEX_APPLICATION_PAGES`, `APEX_APPLICATION_PAGE_REGIONS`
- `APEX_APPLICATION_PAGE_ITEMS`, `APEX_APPLICATION_PAGE_PROC`
- `APEX_APPLICATION_PAGE_IR`, `APEX_APPLICATION_PAGE_RPT`
- `APEX_WORKSPACE_ACTIVITY_LOG`, `APEX_WORKSPACE_SESSIONS`
- `APEX_APPL_ACL_USERS`, `APEX_APPL_ACL_ROLES` (ACL desde 18.1)

**Notas:** Sem Workflow, sem AI, sem Interactive Grid views separadas de IR.

---

### APEX 21.x

**Introduzido:**
- `APEX_APPLICATION_PAGE_IG` e `APEX_APPLICATION_PAGE_IG_COL` — views dedicadas para Interactive Grid
- `APEX_APPLICATION_PAGE_DA_ACTS` — ações de Dynamic Actions separadas
- Suporte a `NATIVE_CARDS`, `NATIVE_MAP_REGION` em `REGION_TYPE_PLUGIN_NAME`

---

### APEX 22.x

**Introduzido: Workflows e Tasks**
- `APEX_APPL_TASKS`, `APEX_APPL_TASK_PARAMS`, `APEX_APPL_TASK_PARTICIPANTS`
- `APEX_APPL_WORKFLOWS`, `APEX_APPL_WORKFLOW_ACTIVITIES`, `APEX_APPL_WORKFLOW_PARAMS`
- `APEX_TASK_INSTANCES`, `APEX_WORKFLOW_INSTANCES` (views de runtime)

**Outros:**
- `NATIVE_WORKFLOW_DIAGRAM` em `REGION_TYPE_PLUGIN_NAME`
- `APEX_APPLICATION_PAGE_COMP` expandido com novos `COMPUTATION_POINT`

---

### APEX 23.1

**Introduzido:**
- `APEX_APPL_WORKFLOW_VARIABLES` — variáveis de workflow
- Expansão de `APEX_WORKFLOW_INSTANCES`: novos campos de rastreio e estado
- `APEX_APPLICATION_PAGE_IR` — nova coluna `PAGINATION_TYPE` com mais opções

---

### APEX 23.2

**Introduzido:**
- Component Groups → `APEX_APPLICATION_COMP_GROUPS`
- Working Copies → `APEX_APPL_WORKING_COPIES`
- Expansão de views de Workflow para incluir rastreio de instâncias
- `NATIVE_SMART_FILTERS` disponível em `REGION_TYPE_PLUGIN_NAME`
- `NATIVE_SELECT_ONE`, `NATIVE_SELECT_MANY` em `DISPLAY_AS` de items

---

### APEX 24.1

**Introduzido: Generative AI**
- `APEX_APPL_AI_CONFIGS` — configurações de AI Agents
- `APEX_INSTANCE_AI_PROVIDERS` — providers de AI da instância

**Outros:**
- `NATIVE_SELECT_ONE` e `NATIVE_SELECT_MANY` consolidados
- Builder Extensions → workspaces que fazem `GRANT READ` expõem seus metadados nas views APEX_DICTIONARY de outros workspaces
- `APEX_APP_OBJECT_DEPENDENCY` — API para dependências de objetos (preview)

---

### APEX 24.2 (versão LTS atual — foco da skill)

**Introduzido: JSON Sources**
- `APEX_APPL_JSON_SOURCES` — JSON Sources component
- `APEX_APPL_JSON_SOURCE_COLS` — colunas do Data Profile

**Introduzido: AI expandido**
- `APEX_APPL_AI_CONFIG_RAG_SRCS` — fontes RAG para AI
- `APEX_WORKSPACE_VECTOR_PROVIDER` — providers de vector search

**Breaking change importante:**
- Views de atributos de plug-ins de item foram reestruturadas em 24.2. Scripts que consultavam atributos de plug-ins via views antigas precisam ser atualizados. Verificar Release Notes antes de upgrade.

**`APEX_APPL_ACL_USERS` com INSTEAD OF trigger:**
- Possível editar roles via UPDATE na view (sem procedure separada)

**Workflow:**
- Parâmetros e variáveis passaram a suportar `CLOB`
- Copy Workflow entre aplicações

---

### APEX 26.1 (preview — não usar em produção ainda)

**APEXlang:** nova linguagem declarativa de especificação de aplicações — impacto futuro em como aplicações são definidas e exportadas.

**Breaking changes documentados:**
- `APEX_APPL_AI_CONFIGS` e `APEX_APPL_AI_CONFIG_RAG_SRCS`: atributo `p_config_static_id` depreciado — migrar para `p_agent_static_id`
- Import de página única entre versões diferentes **não é mais suportado** — imports só funcionam entre instâncias 26.1
- Renomeação de atributos de colunas de plug-ins — scripts que consultam essas views devem ser validados

---

## 7. Impacto Oracle Edition nas views APEX

APEX roda em SE2 e EE, mas há limitações que afetam features e views:

| Feature / View | SE2 | EE | Observação |
|---|:---:|:---:|---|
| Todas as `APEX_APPLICATION_*` | ✅ | ✅ | Sem diferença |
| `APEX_WORKSPACE_ACTIVITY_LOG` | ✅ | ✅ | Sem diferença |
| Workflows e Tasks | ✅ | ✅ | Feature APEX, independe de EE |
| AI (APEX_AI API) | ✅ | ✅ | Depende de AI provider externo, não EE |
| Vector Search (24.2) | ❌ | ✅ (23ai+) | Requer Oracle Database 23ai/26ai EE |
| JSON Duality Views como source | ❌ | ✅ (23ai+) | Requer Oracle Database 23ai/26ai |
| `APEX_APPL_JSON_SOURCES` (Duality) | ❌ | ✅ (23ai+) | Views existem, mas fonte Duality indisponível em SE2 |
| Result Cache para regions | ❌ | ✅ | Result Cache é feature EE |
| Múltiplos PDBs com APEX | ❌ até 20c | ✅ | SE2 21c+: até 3 PDBs |
| ORDS como gateway APEX | ✅ | ✅ | Sem diferença |

### Como verificar features disponíveis na instância

```sql
-- Parâmetros de feature da instância APEX
SELECT parameter_name, parameter_value
  FROM apex_instance_parameters
 WHERE parameter_name LIKE '%ENABLE%'
    OR parameter_name LIKE '%ALLOW%'
 ORDER BY parameter_name;

-- Verificar se Vector Search está disponível (Oracle 23ai+)
SELECT value FROM v$option WHERE parameter = 'Oracle AI Vector Search';
-- YES = disponível

-- Verificar compatibilidade do banco com features AI APEX
SELECT version_full FROM v$instance;
```

---

## 8. Fontes confiáveis para atualização

### Hierarquia de confiabilidade

```
docs.oracle.com/en/database/oracle/apex/{VER}  ← Fonte primária oficial
         │
apex.oracle.com/en/platform/features           ← What's New oficial por versão
         │
connor-mcdonald.com                            ← Connor McDonald (Oracle ACE Director)
         │
oracle-base.com/articles/apex                  ← Tim Hall — artigos práticos APEX
         │
apex.world                                     ← Comunidade e plugins
```

### URLs por versão — padrão de navegação

```
# Documentação principal por versão (substituir {VER})
https://docs.oracle.com/en/database/oracle/apex/{VER}/htmdb/   ← App Builder Guide
https://docs.oracle.com/en/database/oracle/apex/{VER}/aeapi/   ← API Reference
https://docs.oracle.com/en/database/oracle/apex/{VER}/htmrn/   ← Release Notes

# Onde {VER} = 19.2 | 20.1 | 20.2 | 21.1 | 21.2 | 22.1 | 22.2 | 23.1 | 23.2 | 24.1 | 24.2 | 26.1

# Exemplos diretos
https://docs.oracle.com/en/database/oracle/apex/24.2/htmdb/changes-in-this-release.html
https://docs.oracle.com/en/database/oracle/apex/24.2/htmdb/accessing-apex-views.html

# What's New oficial por versão
https://apex.oracle.com/en/platform/features/whats-new-{VER_COMPACTA}/
# Exemplo: https://apex.oracle.com/en/platform/features/whats-new-242/
# Exemplo: https://apex.oracle.com/en/platform/features/whats-new-241/

# Release Notes de todas as versões
https://apex.oracle.com/en/learn/documentation/release-notes/
```

### Connor McDonald — APEX Data Dictionary (fevereiro 2025)

```
https://connor-mcdonald.com/2025/02/26/the-apex-data-dictionary/
```

Inclui script SQL que gera guia HTML navegável de todas as views do `APEX_240200` com hierarquia. **Referência prática essencial.**

### oracle-base.com — APEX por versão

```
https://oracle-base.com/articles/apex/articles-apex
```

Cobre instalação, upgrade, features por versão com exemplos reais.

### Consulta local — gerar próprio inventário de views

```sql
-- Gerar inventário HTML das views APEX (baseado em Connor McDonald)
SELECT  '<h2>' || apex_view_name || '</h2>' ||
        '<p>' || comments || '</p>' ||
        '<ul>' ||
        LISTAGG('<li><b>' || column_name || '</b> (' || type_name || '): ' || comments || '</li>', '')
                WITHIN GROUP (ORDER BY column_id) ||
        '</ul>'
  FROM apex_dictionary
 WHERE column_id > 0
 GROUP BY apex_view_name, comments
 ORDER BY apex_view_name;

-- Verificar views disponíveis na versão instalada
SELECT COUNT(*) AS total_views
  FROM apex_dictionary
 WHERE column_id = 0;

-- Comparar views entre versões (requer acesso a ambas as instâncias)
-- Em instância antiga:
SELECT apex_view_name FROM apex_dictionary WHERE column_id = 0;
-- Em instância nova:
SELECT apex_view_name FROM apex_dictionary WHERE column_id = 0;
-- Diferença = views novas
```

---

## Linkagem interna

- Para padrões de desenvolvimento APEX (Dynamic Actions, pagination, processes) → `references/apex-patterns.md`
- Para views Oracle do banco (DBA_*, V$*, AWR) → `references/data-dictionary-ptbr.md`
- Para PL/SQL chamado por APEX processes → `references/plsql-trivadis-guidelines.md`
- Templates APEX prontos → `assets/apex_*.sql`
