# Templates SQL — Assets

Templates `.sql` prontos para clonar e adaptar. Todos seguem **Trivadis Guidelines 4.4** e a convenção de naming PT-BR da skill.

## Convenções aplicadas

- **Nomes em PT-BR** — variáveis, tabelas, procedures, packages
- **Comentários em PT-BR** — explicam o porquê, não o quê
- **Prefixos Trivadis em inglês** (convenção do padrão) — `g_`, `gc_`, `l_`, `lc_`, `p_`, `r_`, `t_`, `co_`, `e_`
- **Keywords Oracle em inglês obrigatoriamente** — `BEGIN`, `EXCEPTION`, `BULK COLLECT`, `MERGE INTO`, etc.
- **Pacotes Oracle nativos não traduzidos** — `DBMS_LOB`, `APEX_JSON`, `OWA_UTIL`, `UTL_HTTP`, etc.
- **Status values em PT-BR** — `'PENDENTE'`, `'PAGO'`, `'CANCELADO'`, `'PROCESSADO'`, `'VENCIDO'`, `'ALERTA'`, `'ATIVO'`

Tabelas usadas como exemplo: `clientes`, `faturas`, `documentos`, `pagamentos`, `usuarios`, `funcionarios`, `log_eventos`, `log_auditoria`, `fila_processamento`, `arquivo_faturas`.

## Índice por área

### PL/SQL — fundamentos e padrões avançados

| Arquivo | Cobre |
|---|---|
| `package_header.sql` | Esqueleto de package SPEC com tipos públicos, exceptions, procedures e functions documentadas (Javadoc-like) |
| `package_body.sql` | Esqueleto de package BODY com `gc_nome_pacote`, exception handler completo, procedure pública + privada + autonomous transaction para logging |
| `exception_template.sql` | Bloco BEGIN/EXCEPTION padrão para qualquer procedure: validações, lógica, handlers em três níveis (específico → conhecido → catch-all) |
| `bulk_processing_template.sql` | Três variantes: BULK COLLECT completo, BULK COLLECT com LIMIT (chunked), e FORALL com SAVE EXCEPTIONS |
| `dml_alternatives_to_plsql.sql` | **Princípio #0**: SQL puro antes de PL/SQL. Cobre MERGE em vez de loop+IF EXISTS, DBMS_ERRLOG em vez de FORALL SAVE EXCEPTIONS, multitable INSERT, External Tables em vez de UTL_FILE, INSERT SELECT com APPEND/PARALLEL |
| `nocopy_for_lobs.sql` | **Princípio #8**: NOCOPY hint para LOBs (BLOB/CLOB > 100KB) e collections grandes em IN OUT/OUT. Cobre cenário de PDF pages com BLOB. Inclui caveats (compilador pode ignorar, estado intermediário em exception) |
| `clob_blob_operations.sql` | DBMS_LOB para CLOB/BLOB: insert, read em chunks, Base64 encode/decode, hash SHA-256, busca, parsing CSV em CLOB |
| `logger_integration.sql` | Integração com Logger (OraOpenSource): instalação, padrões de uso, scopes, `log_error`/`log_warn`/`log_information`/`log_permanent`, integração com APEX e ORDS |
| `triggers_canonicos.sql` | **Princípios #9 e #10**: triggers sem business logic, sempre compound trigger. Cobre audit triggers (criado_em/criado_por/atualizado_em/atualizado_por), surrogate keys, cross-edition triggers para EBR, anti-patterns clássicos (mutating table, AUTONOMOUS_TRANSACTION em trigger, validação de domínio em trigger) |

### APEX 24.2

| Arquivo | Cobre |
|---|---|
| `apex_dynamic_action.sql` | Dynamic Actions: Execute PL/SQL Code (server-side), Execute JavaScript Code, padrões de cancel/refresh/dialog |
| `apex_pagination_pattern.sql` | Pagination correto em Classic Reports e Interactive Reports: Row Ranges, Page Items to Submit, Region Cache. **Cenário típico**: auditoria de pagination em apps com dezenas de páginas |
| `apex_pl_sql_process.sql` | Page Process (Submit/Load) e AJAX Callbacks (`apex.server.process`). Tratamento de erro com `APEX_ERROR.add_error` |
| `apex_long_running_job.sql` | `APEX_BACKGROUND_PROCESS` para jobs > 30s. Tabela de controle, polling de progresso, dialog de confirmação |
| `apex_interactive_grid.sql` | Configuração IG editável, save process custom, validações por linha, computed columns |
| `apex_blob_upload_download.sql` | File upload via `APEX_APPLICATION_TEMP_FILES`, download via `WPG_DOCLOAD.download_file`, preview inline, integração com tabela documentos |

### ORDS

| Arquivo | Cobre |
|---|---|
| `ords_module.sql` | Módulo ORDS completo CRUD: define_module, define_template, define_handler para GET (collection + item), POST, PUT, DELETE. Inclui versionamento (v1, v2), OAuth 2.0 client credentials, autorização via roles |
| `ords_handler.sql` | Handler ORDS isolado com tratamento HTTP correto: status codes (200/201/400/404/422/500), MIME types, JSON via APEX_JSON, validação de input com DBMS_ASSERT |

### DBA Operacional

| Arquivo | Cobre |
|---|---|
| `flashback_query.sql` | Recuperação de dados via Flashback: AS OF TIMESTAMP, AS OF SCN, FLASHBACK TABLE, FLASHBACK QUERY com VERSIONS BETWEEN |
| `session_management.sql` | Identificar sessões ativas/bloqueadas, killar sessões com cuidado, RAC (cross-instance kill), monitoramento de long ops |
| `recompile_invalid_objects.sql` | UTL_RECOMP, DBMS_UTILITY.compile_schema, recompile manual com tracking, identificação de dependências |

### Performance

| Arquivo | Cobre |
|---|---|
| `explain_plan_workflow.sql` | EXPLAIN PLAN, DBMS_XPLAN.display, AUTOTRACE, SQL Monitor, identificação de full table scans, nested loops vs hash joins |
| `index_strategy_examples.sql` | Quando criar índices: B-Tree, Bitmap, Function-based, Composite, Covering. Quando NÃO criar. Análise de uso (V$OBJECT_USAGE) |

## Como usar

1. **Identifique a área** do problema/tarefa
2. **Leia o reference** correspondente em `references/`
3. **Clone o template** em `assets/`
4. **Adapte** preservando: prefixos Trivadis, exception handler, naming PT-BR
5. **Use Logger** para mensagens (não `DBMS_OUTPUT`)
6. **Para LOB/collection grande** em parâmetros: aplique `NOCOPY`

## Decisão rápida — qual template usar

| Cenário | Template |
|---|---|
| Criar package novo | `package_header.sql` + `package_body.sql` |
| Procedure com exception handler | `exception_template.sql` |
| Loop processando muitas linhas | Primeiro: `dml_alternatives_to_plsql.sql` (cabe SQL puro?). Se não: `bulk_processing_template.sql` |
| BLOB/CLOB grande passado entre procedures | `nocopy_for_lobs.sql` |
| Hash de documento, Base64 conversão | `clob_blob_operations.sql` |
| Logging de produção | `logger_integration.sql` |
| Página APEX nova | Identifique tipo: form (`apex_pl_sql_process.sql`), grid (`apex_interactive_grid.sql`), upload (`apex_blob_upload_download.sql`), report (`apex_pagination_pattern.sql`), JS interaction (`apex_dynamic_action.sql`) |
| Processo APEX > 30s | `apex_long_running_job.sql` |
| API REST nova | `ords_module.sql` (CRUD completo) ou `ords_handler.sql` (endpoint isolado) |
| Recuperar dado deletado | `flashback_query.sql` |
| Sessão travada | `session_management.sql` |
| Objetos inválidos após deploy | `recompile_invalid_objects.sql` |
| Query lenta | `explain_plan_workflow.sql` |
| Decidir se cria índice | `index_strategy_examples.sql` |
