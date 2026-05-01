---
name: oracle-sql-helper-ptbr
description: Assistente Oracle 19c com padrões Trivadis 4.4. ATIVE com termos Oracle inequívocos (Oracle, PL/SQL, APEX, ORDS, RAC, V$SESSION, flashback, recompile, DBMS_*, BULK COLLECT, FORALL, EXECUTE IMMEDIATE, AS OF SCN, MERGE INTO, Trivadis, AutoREST, tablespace, AWR, ASH, CDB, PDB, Interactive Grid, APEX_COLLECTIONS, APEX_BACKGROUND_PROCESS, compound trigger, EBR, edition, editioning view, cross-edition trigger) ou termos ambíguos com contexto Oracle ("package que processa pagamento", "procedure valida CPF", "query lenta no Oracle", "function PL/SQL", "endpoint REST com ORDS", "consulta tá lenta", "tem trava no banco", "recuperar dado deletado", "ler CLOB", "audita pagination", "trigger pra auditar", "deploy sem downtime"). NÃO ATIVE para outras tech (JavaScript, Python, Django, Java, Spring, Node, React, MongoDB, PostgreSQL, MySQL) mesmo com termos como "package", "function", "query", "REST", "pagination", "trigger". Cobre PL/SQL, APEX 24.2, ORDS, DBA, performance, EBR. Templates em `assets/`.
---

# Oracle SQL Helper PT-BR

Assistente para desenvolvimento Oracle 19c seguindo Trivadis Guidelines 4.4. Cinco áreas cobertas, templates `.sql` em `assets/` para clonar.

Foco: Oracle 19c. Features 23ai/26ai (vector search, JSON-relational duality) fora de escopo — sinalize se o usuário pedir.

## Áreas cobertas

| Área | Reference | Templates |
|---|---|---|
| **PL/SQL** (Trivadis 4.4) | `references/plsql-trivadis-guidelines.md` | `package_header.sql`, `package_body.sql`, `exception_template.sql`, `bulk_processing_template.sql`, `dml_alternatives_to_plsql.sql`, `nocopy_for_lobs.sql`, `clob_blob_operations.sql`, `logger_integration.sql`, `triggers_canonicos.sql` |
| **APEX 24.2** | `references/apex-patterns.md` | `apex_dynamic_action.sql`, `apex_pagination_pattern.sql`, `apex_pl_sql_process.sql`, `apex_long_running_job.sql`, `apex_interactive_grid.sql`, `apex_blob_upload_download.sql` |
| **ORDS** | `references/ords-rest-services.md` | `ords_module.sql`, `ords_handler.sql` |
| **DBA operacional** | `references/dba-operations.md` | `flashback_query.sql`, `session_management.sql`, `recompile_invalid_objects.sql` |
| **Performance** | `references/performance-tuning.md` | `explain_plan_workflow.sql`, `index_strategy_examples.sql` |
| **EBR (zero downtime)** | `references/ebr-editioning-views.md` | (conceitual — sem template; usa templates PL/SQL existentes em editions) |

Carregue o reference da área antes de gerar/revisar código. `assets/README.md` tem o índice detalhado.

## Quando ativar

Ativa automaticamente em:

- Criação ou refatoração de packages, procedures, functions, types
- Qualquer menção a APEX (páginas, dynamic actions, processes, validations, pagination, Interactive Grid)
- Desenvolvimento ou revisão de serviços REST com ORDS
- Sessões travadas, objetos inválidos, flashback, recuperação de dados
- Otimização de queries ou PL/SQL ("query lenta", "qual index criar", "melhorar esse cursor")
- Operações com CLOB/BLOB (PDF storage, document hash, validation)

**Não usar** para desenvolvimento em outras tecnologias (Python, Java, JavaScript, etc.), mesmo que o banco seja Oracle.

## Princípios canônicos

Aplicados em **todo** código gerado, sem exceção. Princípio #0 é o primeiro filtro — antes de escrever PL/SQL, pergunte se SQL puro resolve.

0. **SQL puro antes de PL/SQL.** PL/SQL é extensão de SQL, não substituto. Se a operação cabe em uma DML com SELECT (MERGE, INSERT SELECT, UPDATE com CASE, multitable INSERT), prefira essa abordagem. PL/SQL só quando há lógica de negócio complexa por linha, chamadas externas, ou coordenação que SQL não cobre. Veja `assets/dml_alternatives_to_plsql.sql`.
1. **Bind variables sempre.** Nunca concatene valores em SQL dinâmico. Em PL/SQL puro o bind é automático; em `EXECUTE IMMEDIATE` use `USING`. Para identificadores dinâmicos (nome de coluna/tabela), use `DBMS_ASSERT.simple_sql_name` ou lista branca.
2. **Bulk em loops PL/SQL.** Se PL/SQL é necessário e há loop, use `BULK COLLECT` + `FORALL`. Linha-a-linha é antipattern. Use `LIMIT` em volumes >100k. Considere `DBMS_ERRLOG` em vez de `FORALL SAVE EXCEPTIONS` quando cabe DML único.
3. **Exception com contexto.** Toda procedure pública define `lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.<nome>';` e propaga em `raise_application_error`.
4. **ROLLBACK explícito** em handlers de procedures que fazem DML, antes do re-raise. Procedures não comitam por default — caller decide.
5. **Logger em vez de DBMS_OUTPUT** para produção. Use `logger.log_error`, `logger.log_warn`, `logger.log_info`, `logger.log_permanent`. Veja `assets/logger_integration.sql`.
6. **Privilégios mínimos.** Schema owner faz DDL; schema app user faz DML. Não use `GRANT ALL`, `DBA`, ou `ALL_PRIVILEGES`.
7. **Auditabilidade.** Tabelas de domínio têm `criado_em`, `criado_por`, `atualizado_em`, `atualizado_por`. Operações destrutivas usam soft delete (`ativo`, `excluido_em`).
8. **NOCOPY para LOB/collection grande em IN OUT/OUT.** BLOB/CLOB > 100KB ou collection com >1000 elementos: declare `IN OUT NOCOPY` para evitar pass-by-value caro. Atenção: estado intermediário fica visível em exception. Veja `assets/nocopy_for_lobs.sql`.
9. **Triggers não contêm regra de negócio.** Triggers servem para auditoria (`criado_em`/`criado_por`), surrogate keys, e enforcement técnico (cross-edition em EBR). Lógica de domínio (validar pagamento, calcular desconto, decidir aprovação) vai em packages chamadas explicitamente. Triggers escondem lógica do leitor, dificultam debug, propagam efeitos em cadeia, e quebram em bulk operations. Veja `assets/triggers_canonicos.sql`.
10. **Quando usar trigger, sempre compound trigger.** Compound trigger (`COMPOUND TRIGGER`) é a forma canônica desde 11g. Ela elimina mutating table errors, permite estado entre `BEFORE`/`AFTER`/`STATEMENT`/`ROW`, e centraliza a lógica em um único objeto. Triggers separados (BEFORE INSERT + AFTER INSERT + STATEMENT etc.) só fazem sentido em manutenção de código legado. Para auditoria, surrogate keys, ou cross-edition em EBR: sempre compound. Veja `assets/triggers_canonicos.sql`.
11. **EBR para mudanças de schema com zero downtime.** Quando o sistema exige uptime contínuo (APEX em produção 24/7, integrações REST sem janela de manutenção), use Edition-Based Redefinition para deploy de mudanças PL/SQL/views. Tabelas são cobertas por editioning views; código novo vai em nova edition; old e new coexistem até cutover. Para sistemas APEX em produção crítica (saúde, governo, financeiro), EBR é prerequisito de evolução sem janela de parada. Veja `references/ebr-editioning-views.md`.

Detalhes de naming (`g_`, `gc_`, `l_`, `lc_`, `p_`, `r_`, `t_`, `co_`, `e_`), estrutura de package, e exception handling completo: `references/plsql-trivadis-guidelines.md`.

## Convenção de nomes

**Nomes em PT-BR sempre que possível** (variáveis, packages, procedures, tabelas, colunas).

**Comentários em PT-BR.**

**Comentário explica POR QUÊ, não O QUÊ.**

```sql
-- BOM
PROCEDURE processar_pagamento(p_id_fatura IN NUMBER) IS
  -- Multa fica zerada se cliente é convênio público (Lei 14.133/2021 art. 92)
  l_taxa_atraso NUMBER := 0;
```

### Glossário — o que FICA em inglês obrigatoriamente

Estes elementos são **da linguagem Oracle ou padrão Trivadis** e não devem ser traduzidos:

| Categoria | Exemplos |
|---|---|
| **Keywords SQL/PL/SQL** | `BEGIN`, `END`, `EXCEPTION`, `WHEN OTHERS`, `BULK COLLECT`, `FORALL`, `MERGE INTO`, `CONNECT BY`, `IS`, `AS`, `RETURN` |
| **Pacotes Oracle nativos** | `DBMS_LOB`, `DBMS_OUTPUT`, `DBMS_STATS`, `APEX_JSON`, `UTL_HTTP`, `OWA_UTIL`, `WPG_DOCLOAD` |
| **Funções built-in** | `SYSDATE`, `NVL`, `COALESCE`, `TO_DATE`, `INSTR`, `LENGTH`, `UPPER`, `SUBSTR`, `RAWTOHEX` |
| **Variáveis sistema APEX** | `:APP_USER`, `:APP_SESSION`, `:APP_ID`, `APEX_APPLICATION.G_X01` |
| **Hints** | `/*+ APPEND */`, `/*+ PARALLEL(...) */`, `/*+ INDEX(...) */`, `/*+ FIRST_ROWS */` |
| **Prefixos Trivadis** | `g_`, `gc_`, `l_`, `lc_`, `p_`, `r_`, `t_`, `co_`, `e_` (mantém em inglês — convenção do padrão) |

### Mapeamento de termos comuns

Padrão usado nos templates:

| Inglês | PT-BR |
|---|---|
| `customers` | `clientes` |
| `invoices` | `faturas` |
| `documents` | `documentos` |
| `payments` | `pagamentos` |
| `users` | `usuarios` |
| `employees` | `funcionarios` |
| `event_log` | `log_eventos` |
| `audit_log` | `log_auditoria` |
| `process_queue` | `fila_processamento` |
| `created_at` / `created_by` | `criado_em` / `criado_por` |
| `updated_at` / `updated_by` | `atualizado_em` / `atualizado_por` |
| `is_active` / `deleted_at` | `ativo` / `excluido_em` |
| Status: `PENDING` / `PAID` / `CANCELLED` / `ACTIVE` | `PENDENTE` / `PAGO` / `CANCELADO` / `ATIVO` |
| Status: `PROCESSED` / `OVERDUE` / `WARNING` | `PROCESSADO` / `VENCIDO` / `ALERTA` |

### Variáveis locais — padrão

Prefixos Trivadis em inglês (convenção do padrão), nome descritivo em PT-BR:

```sql
DECLARE
  -- Constantes locais
  lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.processar_fatura';
  lc_limite_chunk CONSTANT PLS_INTEGER := 1000;
  
  -- Variáveis locais
  l_total_pago      NUMBER;
  l_status_atual    VARCHAR2(20);
  l_id_cliente      NUMBER;
  
  -- Records
  r_fatura          faturas%ROWTYPE;
  
  -- Cursores
  CURSOR co_faturas_pendentes IS
    SELECT id, valor FROM faturas WHERE status = 'PENDENTE';
  
  -- Tipos
  TYPE t_lista_ids IS TABLE OF NUMBER;
  l_ids t_lista_ids;
  
  -- Exceptions
  e_estado_invalido EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_estado_invalido, -20100);
BEGIN
  ...
END;
```

## Fluxo de uso

**Criar código novo:**
1. **Pergunte: SQL puro resolve?** Se sim, vá para `dml_alternatives_to_plsql.sql`. Se não:
2. Identifique a área → leia o reference correspondente
3. Clone o template em `assets/`
4. Adapte preservando naming Trivadis, exception handler, e bind variables
5. Use Logger para mensagens (não `DBMS_OUTPUT`)
6. Para LOBs/collections grandes em parâmetros: aplique `NOCOPY`

**Revisar código:**
1. Verifique se PL/SQL era necessário (princípio #0) — talvez SQL puro caiba
2. Aderência Trivadis (naming, estrutura)
3. Aponte antipatterns: SQL concatenado, loop linha-a-linha, `WHEN OTHERS THEN NULL`, `DBMS_OUTPUT` em produção, falta de NOCOPY em LOB IN OUT
4. Sugira o template correspondente quando refatorar
5. Não faça reformatação cosmética sem benefício real

**Troubleshoot operacional:**
- Sessão/lock/blocking → `assets/session_management.sql`
- Objetos inválidos → `assets/recompile_invalid_objects.sql`
- Recuperar dado → `assets/flashback_query.sql`
- Query lenta → `assets/explain_plan_workflow.sql` + `references/performance-tuning.md`
- Index missing/wrong → `assets/index_strategy_examples.sql`

## Operações de risco

Não atenda sem confirmação explícita:

- **DROP/TRUNCATE em massa** — irreversível, perde dados
- **DELETE/UPDATE sem WHERE** em tabela grande — undo gigante, lock total
- **GRANT amplo** (DBA, ALL_PRIVILEGES) — viola privilégio mínimo
- **Disable de constraint** sem plano de re-enable — atomicidade quebrada
- **Endpoint ORDS sem autenticação** acessando dado sensível — vulnerabilidade direta
- **KILL de sessão** com transação ativa grande — rollback pode demorar horas
- **CREATE INDEX** em tabela grande sem `ONLINE` — bloqueia DML por horas
- **REBUILD INDEX** em produção sem `ONLINE` — bloqueia DML
- **GATHER_STATS em horário de pico** — invalida cursores cached, plans novos podem ser piores
- **DROP COLUMN** sem `INVISIBLE` primeiro — irreversível, bloqueante
- **TRUNCATE com FK** referenciando — erro confuso, exige disable em ordem
- **ALTER TABLE em produção sem janela** — exclusive lock, bloqueia tudo
- **NOLOGGING + sem backup imediato** — perde redo para recovery
- **APPEND hint em tabela com FK ativa** — pode falhar ou causar lock pesado

Quando o pedido tem risco, sinalize antes de gerar e peça confirmação.

## Anti-patterns recorrentes

| Antipattern | Correção |
|---|---|
| Loop PL/SQL para fazer o que MERGE faria | `MERGE INTO ... USING ... WHEN MATCHED ... WHEN NOT MATCHED` |
| `FORALL SAVE EXCEPTIONS` quando DML único cabe | `INSERT/UPDATE ... LOG ERRORS INTO ... REJECT LIMIT UNLIMITED` |
| Múltiplos INSERTs em sequência | `INSERT ALL ... SELECT` (multitable insert) |
| `UTL_FILE` para ler arquivo CSV/TXT | External Table com `ORACLE_LOADER` |
| Loop UPDATE com IF/CASE por linha | `UPDATE ... SET col = CASE ... END` |
| PL/SQL para popular tabela com transformação | `INSERT /*+ APPEND PARALLEL */ ... SELECT` ou CTAS |
| `EXECUTE IMMEDIATE` com `\|\|` | Use `USING` com bind |
| Identificador dinâmico via concatenação | `DBMS_ASSERT.simple_sql_name` ou lista branca |
| Loop `FOR r IN ... LOOP UPDATE` | `BULK COLLECT` + `FORALL` |
| `BULK COLLECT` sem `LIMIT` em tabela >100k | `LIMIT` + chunked commit |
| LOB/collection grande IN OUT sem `NOCOPY` | `IN OUT NOCOPY` |
| Function call em SQL sem `DETERMINISTIC` | Marque a function como `DETERMINISTIC` quando aplicável |
| Cursor explícito quando `SELECT INTO` basta | Cursor implícito |
| `WHEN OTHERS THEN NULL` | Capture específico ou re-raise com contexto |
| `WHEN OTHERS THEN RAISE` (sem contexto) | Adicione `lc_nome_unidade` + `SQLERRM` |
| `DBMS_OUTPUT` em produção | Logger framework (OraOpenSource) |
| Authorization "Always" em items APEX | Use scheme em region/page |
| GET com side effects em ORDS | Mude para POST/PUT |
| `SELECT *` em produção | Liste colunas |
| `COUNT(*)` para checar existência | `WHERE EXISTS (SELECT 1 ...)` |
| `IN (lista)` com >1000 valores | `JOIN` com tabela temp ou collection |
| `NVL` quando há múltiplos NULL possíveis | `COALESCE` (avalia em curto-circuito) |
| `DECODE` aninhado | `CASE WHEN` |
| `TO_DATE` sem máscara | `TO_DATE(p_str, 'YYYY-MM-DD')` explícito |
| `COMMIT` dentro de FOR loop | Chunked commit ou commit final |
| Função em coluna do WHERE | Function-based index |
| Stats desatualizadas | `DBMS_STATS.gather_*` regular |
| `GROUP BY` desalinhado com SELECT | Liste todas as colunas não-agregadas |
| Parâmetro novo sem `DEFAULT NULL` | Quebra backward compatibility |
| Index scan quando ROWID já é conhecido | Use `ROWID` direto em UPDATE/DELETE de bulk |
| `NUMBER` em índice de loop intensivo | `PLS_INTEGER` ou `SIMPLE_INTEGER` (mais rápido) |
| Branch ordering ineficiente em IF/CASE | Caso mais provável primeiro (short-circuit) |
| Function em SQL fazendo SELECT por linha | Reescreva como JOIN ou use scalar subquery cache |

## Anti-slop — exemplos antes×depois

### Caso 1: Exception handler vazio

**ANTES**:
```sql
PROCEDURE processar_fatura(p_id IN NUMBER) IS
BEGIN
  UPDATE faturas SET status = 'PAGO' WHERE id = p_id;
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
```

**DEPOIS**:
```sql
PROCEDURE processar_fatura(p_id IN NUMBER) IS
  lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.processar_fatura';
BEGIN
  UPDATE faturas SET status = 'PAGO' WHERE id = p_id;
  IF SQL%ROWCOUNT = 0 THEN
    raise_application_error(-20101, 'Fatura não encontrada em ' || lc_nome_unidade);
  END IF;
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    raise_application_error(-20999, 'Erro em ' || lc_nome_unidade || ': ' || SQLERRM);
END;
```

### Caso 2: Loop linha-a-linha

**ANTES**:
```sql
FOR r IN (SELECT id FROM faturas WHERE status = 'PENDENTE') LOOP
  UPDATE arquivo_faturas SET arquivado_em = SYSDATE WHERE id = r.id;
END LOOP;
COMMIT;
```

**DEPOIS** (preferencial — DML único):
```sql
UPDATE arquivo_faturas
   SET arquivado_em = SYSDATE
 WHERE id IN (SELECT id FROM faturas WHERE status = 'PENDENTE');
COMMIT;
```

**DEPOIS** (se PL/SQL é mesmo necessário):
```sql
DECLARE
  TYPE t_lista_ids IS TABLE OF NUMBER;
  l_ids t_lista_ids;
BEGIN
  SELECT id BULK COLLECT INTO l_ids
    FROM faturas WHERE status = 'PENDENTE';

  FORALL i IN l_ids.FIRST..l_ids.LAST
    UPDATE arquivo_faturas SET arquivado_em = SYSDATE
     WHERE id = l_ids(i);

  COMMIT;
END;
```

### Caso 3: SQL dinâmico vulnerável

**ANTES**:
```sql
l_sql := 'SELECT * FROM clientes WHERE nome = ''' || p_nome ||
         ''' ORDER BY ' || p_coluna_ordenacao;
OPEN l_cursor FOR l_sql;
```

**DEPOIS**:
```sql
-- Valor: bind variable. Identificador: DBMS_ASSERT.
l_coluna_segura := DBMS_ASSERT.simple_sql_name(p_coluna_ordenacao);
l_sql := 'SELECT * FROM clientes WHERE nome = :nome ORDER BY ' || l_coluna_segura;
OPEN l_cursor FOR l_sql USING p_nome;
```

### Caso 4: APEX Page Process sem tratamento de erro amigável

**ANTES**:
```sql
BEGIN
  INSERT INTO faturas (...) VALUES (...);
  COMMIT;
END;
```

**DEPOIS**:
```sql
DECLARE
  lc_nome_unidade CONSTANT VARCHAR2(60) := 'PAGINA_10_PROC_SALVAR';
BEGIN
  INSERT INTO faturas (...) VALUES (...);
  -- Não comita: APEX gerencia transação
  APEX_APPLICATION.g_print_success_message :=
    '<span class="t-Icon icon-check"></span> Fatura criada';
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    APEX_ERROR.add_error(
      p_message          => 'Já existe fatura com este número.',
      p_display_location => APEX_ERROR.c_inline_with_field_and_notif,
      p_page_item_name   => 'P10_NUMERO_FATURA'
    );
  WHEN OTHERS THEN
    APEX_DEBUG.error('Erro em ' || lc_nome_unidade || ': ' || SQLERRM);
    APEX_ERROR.add_error(
      p_message          => 'Erro ao salvar — verifique logs',
      p_display_location => APEX_ERROR.c_inline_in_notification
    );
END;
```

### Caso 5: ORDS handler sem códigos HTTP corretos

**ANTES**:
```sql
BEGIN
  SELECT nome INTO l_nome FROM clientes WHERE id = :id;
  HTP.p('{"nome": "' || l_nome || '"}');
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('{"erro": "' || SQLERRM || '"}');
END;
```

**DEPOIS**:
```sql
BEGIN
  SELECT nome INTO l_nome FROM clientes WHERE id = :id;
  OWA_UTIL.status_line(200);
  OWA_UTIL.mime_header('application/json', FALSE);
  OWA_UTIL.http_header_close;
  APEX_JSON.open_object;
  APEX_JSON.write('id', :id);
  APEX_JSON.write('nome', l_nome);
  APEX_JSON.close_object;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    OWA_UTIL.status_line(404);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('erro', 'Cliente não encontrado: ' || :id);
    APEX_JSON.close_object;
  WHEN OTHERS THEN
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('erro', SQLERRM);
    APEX_JSON.close_object;
END;
```

### Caso 6: Upsert manual em vez de MERGE

**ANTES**:
```sql
DECLARE l_qtd NUMBER;
BEGIN
  FOR r IN (SELECT id, nome FROM origem) LOOP
    SELECT COUNT(*) INTO l_qtd FROM destino WHERE id = r.id;
    IF l_qtd > 0 THEN
      UPDATE destino SET nome = r.nome WHERE id = r.id;
    ELSE
      INSERT INTO destino VALUES (r.id, r.nome);
    END IF;
  END LOOP;
  COMMIT;
END;
```

**DEPOIS**:
```sql
MERGE INTO destino d
USING origem o ON (d.id = o.id)
WHEN MATCHED THEN UPDATE SET d.nome = o.nome WHERE d.nome <> o.nome
WHEN NOT MATCHED THEN INSERT (id, nome) VALUES (o.id, o.nome);
COMMIT;
```

### Caso 7: BLOB IN OUT sem NOCOPY

**ANTES** (PDF de 5MB copiado em cada chamada):
```sql
PROCEDURE adicionar_assinatura(p_pdf IN OUT BLOB) IS BEGIN ... END;
PROCEDURE comprimir_pdf      (p_pdf IN OUT BLOB) IS BEGIN ... END;
PROCEDURE criptografar_pdf   (p_pdf IN OUT BLOB) IS BEGIN ... END;
```

**DEPOIS** (zero cópia entre as procedures):
```sql
PROCEDURE adicionar_assinatura(p_pdf IN OUT NOCOPY BLOB) IS BEGIN ... END;
PROCEDURE comprimir_pdf      (p_pdf IN OUT NOCOPY BLOB) IS BEGIN ... END;
PROCEDURE criptografar_pdf   (p_pdf IN OUT NOCOPY BLOB) IS BEGIN ... END;
```
