# Performance Tuning — Análise e Otimização

Performance tuning para desenvolvedor Oracle. Foco no que dá retorno mais rápido: bind variables, indexes, plan análise, e bulk processing. Não cobre AWR/ASH (escopo DBA) nem otimização de hardware.

## Princípio fundamental: medir antes, depois

Não otimize por intuição. Sempre:
1. **Antes:** mede tempo de execução (SET TIMING ON, SQL trace)
2. **Hipótese:** identifica o gargalo via plan, V$SQL, V$SESSION_WAIT
3. **Depois:** aplica mudança, mede de novo
4. **Compara:** ganho real ou só placebo?

Sem medição, "essa query agora tá mais rápida" é alucinação.

## Bind Variables — a otimização #1

### Por que bind variables importam

Cada query nova passa por:
1. **Parse:** valida sintaxe, semântica, gera AST
2. **Bind:** substitui variáveis
3. **Execute:** roda
4. **Fetch:** retorna linhas

**Hard parse** (passo 1+2) é caro. Cache compartilhado (`shared_pool`) cacheia plan já parseado para reuse.

Sem bind:
```sql
-- Cada execução é query diferente para Oracle
SELECT * FROM emp WHERE id = 100;  -- hard parse
SELECT * FROM emp WHERE id = 200;  -- hard parse
SELECT * FROM emp WHERE id = 300;  -- hard parse
```

Com bind:
```sql
-- Uma query, plan reusado
SELECT * FROM emp WHERE id = :id;  -- 1 hard parse
-- Execuções subsequentes só re-bindam
```

### Verificar uso

```sql
-- Top SQL por hard parses (queries sem bind)
SELECT sql_text, parse_calls, executions,
       parse_calls / NULLIF(executions, 0) * 100 AS parse_pct
  FROM v$sqlarea
 WHERE parse_calls > 1
   AND executions > 0
 ORDER BY parse_pct DESC
 FETCH FIRST 20 ROWS ONLY;
```

### Sintomas de falta de bind

```sql
-- Queries quase idênticas (literais diferentes) — sintoma claro
SELECT sql_id, sql_text FROM v$sqlarea
 WHERE sql_text LIKE 'SELECT % FROM emp WHERE id = %';
```

Se vê 50 entradas iguais com IDs diferentes literais → falta bind.

### Em PL/SQL: nativamente bindado

```sql
-- Em PL/SQL, isto USA bind automaticamente
SELECT * INTO l_rec FROM emp WHERE id = p_id;

-- E EXECUTE IMMEDIATE também, com USING
EXECUTE IMMEDIATE 'SELECT * FROM emp WHERE id = :1' INTO l_rec USING p_id;

-- MAS concatenação NÃO usa bind
EXECUTE IMMEDIATE 'SELECT * FROM emp WHERE id = ' || p_id;  -- ❌
```

### Em ORDS/APEX

Bind é automático com:
- `:P1_NOME` (APEX item references)
- `:id` (ORDS path parameters)
- Bind variables em PL/SQL

## EXPLAIN PLAN

### Capturar plan

```sql
-- Forma 1: gerar plan antes de executar
EXPLAIN PLAN FOR
SELECT c.name, COUNT(i.id)
  FROM clientes c
  LEFT JOIN faturas i ON c.id = i.id_cliente
 WHERE c.status = 'A'
 GROUP BY c.name;

SELECT * FROM TABLE(DBMS_XPLAN.display);
```

### Plan da query mais recente

```sql
SELECT * FROM TABLE(DBMS_XPLAN.display_cursor);
```

### Plan de uma query específica em cache

```sql
-- Encontra SQL_ID
SELECT sql_id, sql_text FROM v$sqlarea
 WHERE sql_text LIKE '%trecho_distinto%';

-- Mostra plan
SELECT * FROM TABLE(DBMS_XPLAN.display_cursor(sql_id => 'abcd1234efgh5'));
```

### Lendo o plan

Saída típica:
```
| Id | Operation              | Name      | Rows | Bytes | Cost | Time     |
|  0 | SELECT STATEMENT       |           |  100 | 5000  |  120 | 00:00:01 |
|  1 |  HASH GROUP BY         |           |  100 | 5000  |  120 | 00:00:01 |
|* 2 |   HASH JOIN OUTER      |           | 1000 | 50000 |  118 | 00:00:01 |
|* 3 |    TABLE ACCESS FULL   | CUSTOMERS |  500 | 15000 |   45 | 00:00:01 |
|  4 |    TABLE ACCESS FULL   | INVOICES  | 5000 | 200000|   72 | 00:00:01 |
```

**Ler de dentro pra fora, de baixo pra cima:**
1. Linha 4: full scan em INVOICES
2. Linha 3: full scan em CUSTOMERS, filtrando status='A'
3. Linha 2: HASH JOIN das duas tabelas
4. Linha 1: agrupa
5. Linha 0: retorna

**Sinais de alerta:**
- `TABLE ACCESS FULL` em tabelas grandes (>10k linhas) → falta index?
- `NESTED LOOPS` com tabelas grandes → cardinalidade subestimada?
- Cost muito desbalanceado entre etapas → algum step domina

### Tipos de acesso a índice — a diferença que importa

Quando a query usa um índice, o plan mostra um destes tipos. **Não são equivalentes** — cada um indica eficiência diferente:

| Tipo | Custo típico | Significado |
|---|---|---|
| `INDEX UNIQUE SCAN` | 1-3 LIO | Acesso por valor único (PK ou unique constraint). Best case absoluto. |
| `INDEX RANGE SCAN` | 1-N LIO | Range de valores; pode retornar 1 linha ou milhares |
| `INDEX FULL SCAN` | mais que TABLE FULL geralmente | Lê o índice inteiro (geralmente ruim) |
| `INDEX FAST FULL SCAN` | similar a FULL SCAN | Lê índice em paralelo, sem ordem |
| `INDEX SKIP SCAN` | variável | "Pula" prefixos do composite index quando primeira coluna não é filtrada |

#### `INDEX UNIQUE SCAN` — query por chave única

```
| 1 | TABLE ACCESS BY INDEX ROWID | CUSTOMERS    |   1 |  100 |   2 |
| 2 |  INDEX UNIQUE SCAN          | PK_CUSTOMERS |   1 |      |   1 |
```

A query `WHERE id_cliente = 100` em PK retorna garantidamente 1 linha. Optimizer faz lookup direto: 2-3 LIO.

#### `INDEX RANGE SCAN` — query por chave não-única ou range

```
| 1 | TABLE ACCESS BY INDEX ROWID BATCHED | INVOICES         | 200 | 10000 |  15 |
| 2 |  INDEX RANGE SCAN                   | IDX_INV_CUST_DT  | 200 |       |   3 |
```

`WHERE id_cliente = 100 AND data_emissao > SYSDATE - 30`: pode retornar 0 linhas, 1, ou 1000.

**Diferença prática:**
- `RANGE SCAN` retornando 1 linha: ótimo
- `RANGE SCAN` retornando 100k linhas: pode ser pior que `TABLE ACCESS FULL`
  - Cada linha gerada pelo index → 1 LIO no índice + 1 LIO na tabela (via ROWID)
  - Se 30%+ da tabela é retornada, full scan é mais eficiente

#### `INDEX FULL SCAN` — geralmente é problema

```
| 1 | INDEX FULL SCAN | IDX_INVOICES_DATE | 100k | ... | 250 |
```

Aparece quando:
- `ORDER BY` em coluna indexada **sem WHERE filtrante**
- `MIN/MAX` em coluna indexada (otimização legítima — caso raro de FULL SCAN bom)
- Optimizer estimou que ler o índice é mais barato que tabela inteira (raro)

#### `INDEX SKIP SCAN` — caso especial em composite index

Composite index em `(status, criado_em)`. Query `WHERE criado_em > SYSDATE - 7` (sem filtrar `status`).

```
| 2 |  INDEX SKIP SCAN | IDX_INV_STATUS_DT | ... |
```

Optimizer "pula" cada valor distinto de `status` e faz range scan dentro de cada. Funciona bem se `status` tem **poucos** valores distintos (3-10). Com 10000 valores distintos, é mais lento que `TABLE ACCESS FULL`.

### O que checar em revisão de plan

1. **Operação principal usa índice?** Se `TABLE ACCESS FULL` em tabela grande, falta index.
2. **Tipo de scan no índice é apropriado?**
   - PK/unique → `UNIQUE SCAN`
   - Range com seletividade alta → `RANGE SCAN` retornando poucas linhas
   - `FULL SCAN` em índice raramente é desejado
3. **Cardinalidade estimada bate com real?**
   - `Rows` no plan vs realidade (use `DBMS_XPLAN.display_cursor` com `format => 'ALLSTATS LAST'` para ver real)
   - Diferença >10x indica stats ruins
4. **Joins usam o método certo?**
   - Tabelas pequenas + índice no join key → `NESTED LOOPS`
   - Tabelas grandes sem filtro seletivo → `HASH JOIN`
   - Ambas ordenadas → `MERGE JOIN`

### Verificando estatísticas reais (vs estimativas do optimizer)

```sql
-- Roda a query (ou já rodou recentemente)
SELECT /*+ GATHER_PLAN_STATISTICS */ ... FROM ...;

-- Mostra plan com runtime stats
SELECT * FROM TABLE(DBMS_XPLAN.display_cursor(
  format => 'ALLSTATS LAST'
));
```

Output mostra colunas adicionais:
- `E-Rows`: estimativa do optimizer
- `A-Rows`: realidade
- `A-Time`: tempo real gasto
- `Buffers`: LIOs reais

Se `E-Rows` e `A-Rows` divergem muito, optimizer escolheu plan errado. Atualize stats com `DBMS_STATS.gather_table_stats`.

## Indexes

### Quando criar index

| Cenário | Ajuda? |
|---|---|
| WHERE coluna = valor (alta seletividade) | Sim |
| WHERE coluna IN (lista) | Sim, se seletivo |
| WHERE LIKE 'inicio%' (pattern com início fixo) | Sim |
| WHERE LIKE '%meio%' (wildcard prefix) | Não ajuda B-tree |
| ORDER BY coluna | Sim, evita sort |
| JOIN ON coluna = outra | Sim, na coluna lookup |
| WHERE função(coluna) = valor | Não — precisa **function-based index** |

### Tipos de index

```sql
-- B-tree (default) — alta seletividade
CREATE INDEX idx_customers_status ON clientes(status);

-- Composite — múltiplas colunas em sequência
CREATE INDEX idx_invoices_cust_date ON faturas(id_cliente, data_emissao);

-- Function-based — quando WHERE usa função
CREATE INDEX idx_emp_upper_name ON funcionarios(UPPER(name));
-- Agora isto usa index:
SELECT * FROM funcionarios WHERE UPPER(name) = 'JOÃO SILVA';

-- Bitmap — baixa cardinalidade (poucos valores distintos), poucas modificações
-- Útil em data warehouse, NÃO em OLTP
CREATE BITMAP INDEX idx_emp_gender ON funcionarios(gender);

-- Unique — força unicidade + agiliza lookup
CREATE UNIQUE INDEX uk_customers_cpf ON clientes(cpf);
```

### Composite index — ordem importa

```sql
CREATE INDEX idx_inv_cust_date ON faturas(id_cliente, data_emissao);

-- USA o index
SELECT * FROM faturas WHERE id_cliente = 100;
SELECT * FROM faturas WHERE id_cliente = 100 AND data_emissao > SYSDATE - 30;

-- NÃO USA o index (não tem prefixo id_cliente)
SELECT * FROM faturas WHERE data_emissao > SYSDATE - 30;
```

**Regra:** coluna mais seletiva e mais usada em WHERE primeiro.

### Verificar uso de indexes

```sql
-- Indexes não utilizados (precisa MONITORING USAGE primeiro)
ALTER INDEX idx_customers_status MONITORING USAGE;

-- Depois de período de uso
SELECT index_name, used FROM v$object_usage
 WHERE table_name = 'CUSTOMERS';

-- Para parar
ALTER INDEX idx_customers_status NOMONITORING USAGE;
```

### Quando index pode atrapalhar

- DML pesado em tabela com muitos indexes (cada INSERT/UPDATE atualiza todos)
- Index muito grande comparado à tabela (rare scan + table access)
- Estatísticas obsoletas levando optimizer a escolher mal

## Hints — uso parcimonioso

Hints forçam optimizer a escolher caminho específico. **Quase sempre é melhor melhorar stats e indexes do que usar hints.** Mas há casos onde compensa.

### Sintaxe

```sql
SELECT /*+ INDEX(c idx_customers_status) */
       c.id, c.name
  FROM clientes c
 WHERE c.status = 'A';
```

### Hints úteis

| Hint | Uso |
|---|---|
| `INDEX(tabela index_name)` | Força uso de index específico |
| `NO_INDEX(tabela index_name)` | Proíbe index específico |
| `FULL(tabela)` | Força full scan |
| `USE_NL(tab1 tab2)` | Força nested loops |
| `USE_HASH(tab1 tab2)` | Força hash join |
| `LEADING(tabela)` | Define primeira tabela no join order |
| `PARALLEL(tabela, N)` | Habilita paralelismo |
| `RESULT_CACHE` | Cacheia resultado da query |
| `MATERIALIZE` em WITH | Força materialização de subquery |

### Quando hints fazem sentido

- Stats desatualizadas e impossível atualizar agora
- Optimizer consistentemente erra em caso conhecido
- Forçar plan estável em SQL crítico (use SQL Plan Baselines em vez quando possível)

### Quando NÃO usar hints

- "Vi um cara na internet usar" — sem entender o porquê
- Para "garantir" comportamento — frágil quando dados mudam
- Em vez de criar index — quase sempre o index resolveria melhor

## Cursor sharing e bind peeking

### Cursor sharing modes

```sql
-- Verifica modo
SHOW PARAMETER cursor_sharing;

-- EXACT (default 19c+): hard parse a cada literal
-- FORCE: substitui literais por bind automaticamente
-- SIMILAR: deprecated
```

`EXACT` é correto, força disciplina de bind no código.

### Bind peeking — efeito de "primeira execução"

Optimizer "espia" valor da bind na primeira execução para escolher plan. Se primeira execução tem valor incomum, plan pode ficar ruim para usos típicos.

**Sintoma:** query rápida normalmente, lenta em horários específicos.

**Mitigação:**
- Adaptive Cursor Sharing (default 11g+): Oracle gera múltiplos plans para diferentes "perfis" de bind
- SQL Plan Baselines: força plan específico

## Bulk Processing como otimização

Loops linha-a-linha em PL/SQL são MUITO mais lentos que bulk. Diferença de 10x-100x em volumes médios.

### Antes (linha-a-linha)

```sql
FOR r IN (SELECT id, valor FROM faturas) LOOP
  INSERT INTO archive_invoices VALUES (r.id, r.valor, SYSDATE);
END LOOP;
```

### Depois (bulk)

```sql
DECLARE
  TYPE t_inv_tab IS TABLE OF faturas%ROWTYPE;
  l_invs t_inv_tab;
BEGIN
  SELECT * BULK COLLECT INTO l_invs FROM faturas;

  FORALL i IN l_invs.FIRST..l_invs.LAST
    INSERT INTO archive_invoices(id, valor, archived_at)
    VALUES (l_invs(i).id, l_invs(i).valor, SYSDATE);

  COMMIT;
END;
```

### Para volumes muito grandes — chunking

```sql
DECLARE
  CURSOR co_inv IS SELECT * FROM faturas;
  TYPE t_inv_tab IS TABLE OF faturas%ROWTYPE;
  l_invs t_inv_tab;
  lc_limit CONSTANT PLS_INTEGER := 10000;
BEGIN
  OPEN co_inv;
  LOOP
    FETCH co_inv BULK COLLECT INTO l_invs LIMIT lc_limit;
    EXIT WHEN l_invs.COUNT = 0;

    FORALL i IN l_invs.FIRST..l_invs.LAST
      INSERT INTO archive_invoices(id, valor, archived_at)
      VALUES (l_invs(i).id, l_invs(i).valor, SYSDATE);

    COMMIT;  -- chunk-level commit
  END LOOP;
  CLOSE co_inv;
END;
```

## Identificar queries problemáticas

### Top SQL por tempo total

```sql
SELECT sql_id, sql_text, executions,
       ROUND(elapsed_time/1000000, 2)  AS elapsed_sec,
       ROUND(elapsed_time/NULLIF(executions,0)/1000, 2) AS avg_ms,
       buffer_gets, disk_reads
  FROM v$sqlarea
 WHERE executions > 0
 ORDER BY elapsed_time DESC
 FETCH FIRST 20 ROWS ONLY;
```

### Top SQL por buffer gets (uso de memória)

```sql
SELECT sql_id, sql_text, executions,
       buffer_gets,
       ROUND(buffer_gets/NULLIF(executions,0), 0) AS avg_buffer_gets
  FROM v$sqlarea
 WHERE executions > 0
 ORDER BY buffer_gets DESC
 FETCH FIRST 20 ROWS ONLY;
```

### Wait events em sessão problemática

```sql
SELECT s.sid, s.serial#, s.username, s.event, s.wait_class,
       s.seconds_in_wait, s.sql_id
  FROM v$session s
 WHERE s.username IS NOT NULL
   AND s.status = 'ATIVO'
   AND s.event NOT LIKE 'SQL*Net%idle%'
 ORDER BY s.seconds_in_wait DESC;
```

## Statistics — manter atualizadas

Optimizer **depende** de stats precisas. Sem stats:
- Estima cardinalidade errada
- Escolhe plan errado
- Performance imprevisível

```sql
-- Última coleta de stats
SELECT table_name, last_analyzed, num_rows, blocks
  FROM user_tables
 ORDER BY last_analyzed NULLS FIRST;

-- Coletar para tabela
EXEC DBMS_STATS.gather_table_stats(USER, 'INVOICES', cascade => TRUE);

-- Schema inteiro
EXEC DBMS_STATS.gather_schema_stats(USER, cascade => TRUE);
```

**Frequência:** geralmente Oracle Auto Task roda diariamente. Mas após cargas pesadas, force coleta manual.

## Anti-patterns Performance

| Anti-pattern | Sintoma | Correção |
|---|---|---|
| Concatenação de SQL com literais | Hard parses, shared_pool fragmentado | Bind variables |
| Loop linha-a-linha em volume | PL/SQL muito lento | BULK COLLECT + FORALL |
| `SELECT *` em vez de colunas | I/O extra, network extra | Selecione colunas necessárias |
| `COUNT(*)` para checar existência | Lê tudo | `WHERE EXISTS (SELECT 1 ...)` |
| Função em coluna do WHERE | Não usa index | Function-based index |
| OR sem indexes apropriados | Full scan | UNION ALL com index em cada |
| NOT IN com subquery | Estranhamento de NULL | NOT EXISTS |
| Subquery correlacionada | N execuções | JOIN ou WITH |
| Cursor implícito quando 0 ou 1 linha | Overhead de cursor | Single-row SELECT INTO |
| Stats desatualizadas | Plans subitamente ruins | DBMS_STATS regular |

## Checklist rápido para query lenta

1. ✅ Tem bind variables? (não literais)
2. ✅ EXPLAIN PLAN mostra full scan em tabela grande?
3. ✅ Stats da tabela atualizadas?
4. ✅ Index no WHERE/JOIN existe e está sendo usado?
5. ✅ Predicado usa função em coluna? (precisa FBI)
6. ✅ Volume da query é razoável? (não está retornando MB sem necessidade)
7. ✅ É loop em PL/SQL? (use BULK)
8. ✅ Tem subquery correlacionada? (refatore com JOIN)

## Linkagem

- Templates → `assets/` (não há templates específicos de performance — use os de PL/SQL com princípios aplicados)
- Para PL/SQL bulk → `plsql-trivadis-guidelines.md`
- Para troubleshoot operacional → `dba-operations.md`
