# ORDS — RESTful Data Services

Padrões para Oracle REST Data Services (ORDS). Foco em estrutura modular usando `ORDS.define_module` / `define_template` / `define_handler`.

## Arquitetura básica

ORDS expõe banco Oracle como REST. Hierarquia:

```
Schema enable          → habilita schema para REST
  Module                → grupo lógico de endpoints (geralmente uma "API")
    Template            → URI pattern (com parâmetros)
      Handler           → método HTTP (GET, POST, PUT, DELETE)
```

Exemplo de URL:
```
https://server/ords/<schema-alias>/<module>/<template>/<params>

https://example.gov.br/ords/api/laudos/v1/laudo/12345
                          ^^^                       ^^^^^
                          schema-alias              path-parameter
                              ^^^^^^^               ^^^^^
                              module                template
```

## Habilitar schema (uma vez por schema)

```sql
BEGIN
  ORDS.enable_schema(
    p_enabled             => TRUE,
    p_schema              => 'MY_APP',
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'api',  -- aparece como /ords/api/
    p_auto_rest_auth      => FALSE   -- exige auth para AutoREST (recomendado)
  );
  COMMIT;
END;
/
```

## Definir módulo

```sql
BEGIN
  ORDS.define_module(
    p_module_name    => 'laudos.v1',
    p_base_path      => '/laudos/v1/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'API de Laudos — operações CRUD'
  );
  COMMIT;
END;
/
```

**Convenções:**
- **Versionamento no nome do módulo:** `laudos.v1`, `laudos.v2`
- **Versão também no path base:** `/laudos/v1/`
- Pagination padrão: 25 itens

## Definir template

Template é o URI pattern. Pode ter parâmetros:

```sql
BEGIN
  -- Template com parâmetro :id
  ORDS.define_template(
    p_module_name => 'laudos.v1',
    p_pattern     => 'laudo/:id',  -- URI: /laudos/v1/laudo/12345
    p_priority    => 0,
    p_etag_type   => 'HASH',       -- ETag automático para cache
    p_etag_query  => NULL
  );

  -- Template sem parâmetros (collection)
  ORDS.define_template(
    p_module_name => 'laudos.v1',
    p_pattern     => 'laudo',       -- URI: /laudos/v1/laudo
    p_priority    => 0
  );
  COMMIT;
END;
/
```

**Padrão de patterns (REST conventions):**
- **Collection:** `recurso` (GET lista, POST cria)
- **Item:** `recurso/:id` (GET detalha, PUT atualiza, DELETE remove)
- **Sub-resource:** `recurso/:id/sub-recurso` (GET lista filhos)
- **Custom action:** `recurso/:id/acao` (POST executa ação)

## Definir handler

Handler é o método HTTP + a lógica:

```sql
-- GET de laudo individual
BEGIN
  ORDS.define_handler(
    p_module_name    => 'laudos.v1',
    p_pattern        => 'laudo/:id',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_plsql,
    p_mimes_allowed  => 'application/json',
    p_source         => q'[
DECLARE
  l_status_code NUMBER := 200;
BEGIN
  SELECT id, numero, paciente, data_emissao, status
    INTO :id, :numero, :paciente, :data_emissao, :status
    FROM laudos
   WHERE id = :id;

  -- Headers
  OWA_UTIL.mime_header('application/json', FALSE);
  OWA_UTIL.status_line(l_status_code);
  OWA_UTIL.http_header_close;

  -- Body em JSON
  APEX_JSON.open_object;
  APEX_JSON.write('id', :id);
  APEX_JSON.write('numero', :numero);
  APEX_JSON.write('paciente', :paciente);
  APEX_JSON.write('data_emissao', :data_emissao);
  APEX_JSON.write('status', :status);
  APEX_JSON.close_object;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    OWA_UTIL.status_line(404);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Laudo não encontrado');
    APEX_JSON.close_object;
  WHEN OTHERS THEN
    OWA_UTIL.status_line(500);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );
  COMMIT;
END;
/
```

## Bind variables ORDS

ORDS injeta automaticamente:

| Bind | Origem |
|---|---|
| `:id`, `:nome` (qualquer) | Path parameters do template (`/laudo/:id`) |
| Query string | Para um `?status=A`, dentro do PL/SQL: `:status` |
| Body JSON | Para POST/PUT, parser automático com p_source_type=plsql/json |
| `:current_user` | Usuário ORDS autenticado |

## Source types disponíveis

| Source type | Quando usar |
|---|---|
| `ORDS.source_type_plsql` | Lógica PL/SQL completa (mais flexível) |
| `ORDS.source_type_collection_query` | SELECT que retorna JSON automaticamente |
| `ORDS.source_type_collection_item` | Item individual de uma collection |
| `ORDS.source_type_query_one_row` | SELECT que retorna 1 linha como JSON |
| `ORDS.source_type_csv_query` | SELECT que retorna CSV |
| `ORDS.source_type_media` | BLOB (imagens, PDFs) |

### Collection query (mais simples para listas)

```sql
BEGIN
  ORDS.define_handler(
    p_module_name => 'laudos.v1',
    p_pattern     => 'laudo',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_collection_query,
    p_source      => q'[
SELECT id, numero, paciente, data_emissao, status
  FROM laudos
 WHERE (:status IS NULL OR status = :status)
 ORDER BY data_emissao DESC
]'
  );
  COMMIT;
END;
/
```

ORDS retorna automaticamente:
```json
{
  "items": [...],
  "hasMore": true,
  "limit": 25,
  "offset": 0,
  "count": 25,
  "links": [...]
}
```

## Autenticação

### OAuth 2.0 (recomendado)

```sql
-- Define role
BEGIN
  ORDS.create_role(p_role_name => 'laudos_reader');
  COMMIT;
END;
/

-- Liga role ao módulo
BEGIN
  ORDS.define_privilege(
    p_privilege_name => 'priv.laudos.read',
    p_roles          => 'laudos_reader',
    p_patterns       => '/laudos/v1/*',
    p_label          => 'Leitura de laudos',
    p_description    => 'Permite GET em /laudos/v1/*'
  );
  COMMIT;
END;
/

-- Cria client OAuth
BEGIN
  OAUTH.create_client(
    p_name            => 'sistema_externo',
    p_grant_type      => 'client_credentials',
    p_owner           => 'APP',
    p_description     => 'Cliente para sistema externo',
    p_support_email   => 'dba@example.com',
    p_privilege_names => 'priv.laudos.read'
  );
  COMMIT;
END;
/

-- Cliente faz GET https://server/ords/api/oauth/token com client_id e client_secret
-- Recebe access_token, usa em Authorization: Bearer <token>
```

### Roles APEX (autenticação via APEX user)

Para integrar com sessão APEX existente:

```sql
BEGIN
  ORDS.define_handler(
    ...
    p_source => q'[
DECLARE
  l_user VARCHAR2(255);
BEGIN
  l_user := APEX_CUSTOM_AUTH.get_username;
  IF l_user IS NULL THEN
    OWA_UTIL.status_line(401);
    OWA_UTIL.http_header_close;
    RETURN;
  END IF;
  -- ... lógica
END;
]'
  );
END;
/
```

## Códigos HTTP padronizados

| Status | Quando usar |
|---|---|
| 200 OK | GET, PUT (atualização sucesso) |
| 201 Created | POST (criação sucesso) |
| 204 No Content | DELETE sucesso, ou PUT sem retorno |
| 400 Bad Request | JSON malformado, parâmetro inválido |
| 401 Unauthorized | Sem credenciais ou inválidas |
| 403 Forbidden | Autenticado mas sem permissão |
| 404 Not Found | Recurso não existe |
| 409 Conflict | Conflito (ex: CPF duplicado) |
| 422 Unprocessable Entity | Validação de negócio falhou |
| 500 Internal Server Error | Bug interno |

```sql
-- Helper: setar status + JSON error
PROCEDURE return_error(p_status NUMBER, p_message VARCHAR2) IS
BEGIN
  OWA_UTIL.status_line(p_status);
  OWA_UTIL.mime_header('application/json', FALSE);
  OWA_UTIL.http_header_close;

  APEX_JSON.open_object;
  APEX_JSON.write('error', p_message);
  APEX_JSON.write('status', p_status);
  APEX_JSON.close_object;
END;
```

## CORS

ORDS suporta CORS via metadata. Habilite globalmente ou por módulo:

```sql
-- No módulo, no handler:
OWA_UTIL.mime_header('application/json', FALSE);
HTP.p('Access-Control-Allow-Origin: *');
HTP.p('Access-Control-Allow-Methods: GET, POST, PUT, DELETE');
HTP.p('Access-Control-Allow-Headers: Content-Type, Authorization');
OWA_UTIL.http_header_close;
```

Para produção, **não use `*`** — liste origins específicas.

## Versionamento

Mantenha versões antigas funcionando enquanto deprecam:

```sql
-- v1 (mantido para clientes legados)
ORDS.define_module(p_module_name => 'laudos.v1', p_base_path => '/laudos/v1/', ...);

-- v2 (atual)
ORDS.define_module(p_module_name => 'laudos.v2', p_base_path => '/laudos/v2/', ...);

-- v3 (próxima, em desenvolvimento)
ORDS.define_module(p_module_name => 'laudos.v3', p_base_path => '/laudos/v3/', p_status => 'NOT_PUBLISHED');
```

Comunique deprecation via header:
```
Deprecation: true
Sunset: Thu, 01 Jan 2026 00:00:00 GMT
Link: <https://server/ords/api/laudos/v2/laudo/123>; rel="successor-version"
```

## SQL Injection em handlers PL/SQL

Handlers `ORDS.source_type_plsql` recebem parâmetros diretamente em bind variables (`:id`, `:status`) — isso é seguro por padrão. **O risco aparece quando o handler constrói SQL dinâmico** com partes vindas do request.

### Cenário perigoso: identificadores dinâmicos

Quando você precisa que o caller escolha tabela, coluna, ou direção de ordenação:

```sql
-- ❌ VULNERÁVEL: cliente pode injetar SQL via :sort_column
DECLARE
  l_sql VARCHAR2(4000);
BEGIN
  l_sql := 'SELECT id, name FROM clientes ORDER BY ' || :sort_column || ' DESC';
  -- Cliente passa: ?sort_column=name; DROP TABLE clientes --
  OPEN l_cursor FOR l_sql;
  ...
END;
```

Bind variables não funcionam para identificadores (nomes de colunas/tabelas) — apenas para valores. Para identificadores dinâmicos, use `DBMS_ASSERT`:

```sql
-- ✅ SEGURO: DBMS_ASSERT valida o identificador
DECLARE
  l_sql        VARCHAR2(4000);
  l_safe_col   VARCHAR2(30);
  l_safe_dir   VARCHAR2(4);
BEGIN
  -- Valida que é um nome SQL simples (sem injection)
  l_safe_col := DBMS_ASSERT.simple_sql_name(:sort_column);
  
  -- Valida direção via lista branca (DBMS_ASSERT não cobre keywords)
  l_safe_dir := CASE UPPER(:sort_direction)
                  WHEN 'ASC'  THEN 'ASC'
                  WHEN 'DESC' THEN 'DESC'
                  ELSE 'ASC'  -- default seguro
                END;
  
  l_sql := 'SELECT id, name FROM clientes ORDER BY ' || l_safe_col || ' ' || l_safe_dir;
  
  OPEN l_cursor FOR l_sql;
  ...
EXCEPTION
  WHEN OTHERS THEN
    -- DBMS_ASSERT lança ORA-44004 se nome inválido
    OWA_UTIL.status_line(400);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Parâmetro de ordenação inválido');
    APEX_JSON.close_object;
END;
```

### Funções DBMS_ASSERT

| Função | Valida |
|---|---|
| `simple_sql_name(p_name)` | Nome SQL simples (letras, números, `_`, `$`, `#`); até 30 chars |
| `qualified_sql_name(p_name)` | Nome qualificado (`schema.tabela.coluna`) |
| `sql_object_name(p_name)` | Nome de objeto **que existe** no dicionário |
| `schema_name(p_name)` | Nome de schema **que existe** |
| `enquote_name(p_name)` | Adiciona aspas e valida (preserva case) |
| `enquote_literal(p_str)` | Escapa string como literal SQL (`'foo''bar'`) |

### Lista branca: padrão para opções enumeradas

Para parâmetros que devem ser de um conjunto fixo (status, ordem, formato), **lista branca é mais seguro que DBMS_ASSERT**:

```sql
DECLARE
  l_safe_status VARCHAR2(20);
BEGIN
  l_safe_status := CASE UPPER(:status)
                     WHEN 'PENDENTE'  THEN 'PENDENTE'
                     WHEN 'ATIVO'   THEN 'ATIVO'
                     WHEN 'ARQUIVADO' THEN 'ARQUIVADO'
                     ELSE NULL  -- ignora valor não reconhecido
                   END;

  -- Agora l_safe_status é seguro para uso em SQL
  ...
END;
```

### Princípio geral

1. **Valores → bind variables** (`:id`, `:name`, `:valor`). Nunca concatene.
2. **Identificadores → DBMS_ASSERT** ou lista branca.
3. **Direção/ordenação/keyword → lista branca** (DBMS_ASSERT não cobre keywords como `ASC`/`DESC`).
4. **Em dúvida, recuse SQL dinâmico.** Se a flexibilidade não é essencial, prefira queries fixas com filtros opcionais (`WHERE (:status IS NULL OR status = :status)`).

## Anti-patterns

| Anti-pattern | Por que é ruim |
|---|---|
| GET que altera dados | Quebra REST, cache faz coisas inesperadas |
| POST sem validação | Mass assignment, dados inconsistentes |
| Endpoint sem autenticação acessando dados sensíveis | Vulnerabilidade óbvia |
| Senhas/tokens no path/query string | Aparecem em logs |
| Versionamento via query string `?v=2` | Cache fica confuso, prefira path |
| Retornar tudo da tabela em GET | Vazamento de dados, performance ruim |
| HTTP 200 com `{"error": "..."}` no body | Quebra integração — use código correto |

## Linkagem

- Templates prontos em `assets/ords_module.sql`, `assets/ords_handler.sql`
- Para PL/SQL dentro do handler → `plsql-trivadis-guidelines.md`
- Para autenticação avançada → documentação ORDS oficial
