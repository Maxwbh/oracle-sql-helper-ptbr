--==============================================================================
-- Template: EXPLAIN PLAN — Workflow de Análise
--
-- Workflow completo para diagnosticar query lenta:
--   1. Capturar plan estimado (EXPLAIN PLAN FOR)
--   2. Capturar plan real com runtime stats (GATHER_PLAN_STATISTICS)
--   3. Comparar estimativa vs realidade
--   4. Verificar stats de tabelas/colunas envolvidas
--   5. Decidir ação: criar index, atualizar stats, refatorar query
--==============================================================================


--==============================================================================
-- ETAPA 1: Plan estimado — antes de executar
--==============================================================================

EXPLAIN PLAN FOR
SELECT c.id, c.nome, COUNT(i.id) AS qtd_faturas
  FROM clientes c
  LEFT JOIN faturas i ON c.id = i.id_cliente
                       AND i.data_emissao > SYSDATE - 30
 WHERE c.status = 'A'
 GROUP BY c.id, c.nome;

-- Visualiza o plan estimado
SELECT * FROM TABLE(DBMS_XPLAN.display(
  format => 'BASIC +PREDICATE +COST +ROWS'
));

-- Format options úteis:
--   BASIC      — operação, nome
--   +PREDICATE — filtros (access vs filter)
--   +COST      — custo estimado
--   +ROWS      — cardinalidade estimada
--   +BYTES     — bytes estimados
--   ALL        — tudo
--   ALLSTATS   — runtime stats (precisa GATHER_PLAN_STATISTICS)
--   LAST       — última execução (para display_cursor)
--   IOSTATS    — physical/logical reads
--   MEMSTATS   — uso de memória


--==============================================================================
-- ETAPA 2: Plan real com runtime stats
--==============================================================================

-- Adicione hint GATHER_PLAN_STATISTICS na query
SELECT /*+ GATHER_PLAN_STATISTICS */
       c.id, c.nome, COUNT(i.id) AS qtd_faturas
  FROM clientes c
  LEFT JOIN faturas i ON c.id = i.id_cliente
                       AND i.data_emissao > SYSDATE - 30
 WHERE c.status = 'A'
 GROUP BY c.id, c.nome;

-- Imediatamente após executar (mesma sessão):
SELECT * FROM TABLE(DBMS_XPLAN.display_cursor(
  format => 'ALLSTATS LAST'
));

-- Output adiciona colunas:
--   E-Rows  — estimativa do optimizer
--   A-Rows  — realidade
--   A-Time  — tempo real
--   Buffers — LIOs reais
--   Reads   — physical reads
--   OMem    — memória ótima
--   1Mem    — memória 1-pass
--   Used-Mem— memória efetivamente usada


--==============================================================================
-- ETAPA 3: Comparar estimativa vs realidade — interpretar resultado
--==============================================================================

/*
Indicadores de problema:

1. E-Rows muito diferente de A-Rows (>10x divergência)
   → Stats desatualizadas ou histograma faltando
   → Ação: gather_table_stats com method_opt apropriado

2. A-Rows altíssimo em step intermediário
   → Filtro acontecendo tarde demais (depois de join)
   → Ação: revisar predicados, considerar reordenar joins

3. NESTED LOOPS com A-Rows alto na linha externa
   → Optimizer estimou cardinalidade baixa, mas é alta
   → Ação: HASH JOIN seria melhor; verificar stats

4. Buffers muito alto comparado ao output
   → Lendo muito para retornar pouco
   → Ação: criar index, refatorar para evitar full scan

5. A-Time muito desbalanceado entre steps
   → Step específico domina o tempo
   → Foco da otimização nesse step

6. TEMP space usage (Used-Mem com '0Mem' ou aviso)
   → Sort/hash spilled to disk
   → Ação: aumentar PGA_AGGREGATE_TARGET ou refatorar
*/


--==============================================================================
-- ETAPA 4: Plan de query já em cache (sem re-executar)
--==============================================================================

-- Encontra SQL_ID da query
SELECT sql_id, child_number, sql_text, executions, elapsed_time
  FROM v$sqlarea
 WHERE sql_text LIKE '%clientes c%LEFT JOIN faturas i%'
 ORDER BY last_active_time DESC;

-- Mostra plan
SELECT * FROM TABLE(DBMS_XPLAN.display_cursor(
  sql_id        => 'abcd1234efgh5',
  child_number  => 0,
  format        => 'ALLSTATS LAST'
));


--==============================================================================
-- ETAPA 5: Verificar stats das tabelas envolvidas
--==============================================================================

-- Stats das tabelas
SELECT table_name,
       num_rows,
       blocks,
       avg_row_len,
       last_analyzed,
       sample_size,
       stale_stats
  FROM dba_tab_statistics
 WHERE owner = USER
   AND table_name IN ('CUSTOMERS', 'INVOICES')
 ORDER BY table_name;

-- Stats das colunas usadas em WHERE/JOIN/GROUP BY
SELECT table_name, column_name,
       num_distinct,
       num_nulls,
       density,
       histogram,
       last_analyzed
  FROM dba_tab_col_statistics
 WHERE owner = USER
   AND table_name IN ('CUSTOMERS', 'INVOICES')
   AND column_name IN ('STATUS', 'CUSTOMER_ID', 'INVOICE_DATE')
 ORDER BY table_name, column_name;

-- Indexes das tabelas
SELECT i.index_name, i.index_type, i.uniqueness,
       LISTAGG(c.column_name, ', ') WITHIN GROUP (ORDER BY c.column_position) AS columns,
       i.last_analyzed,
       i.distinct_keys,
       i.clustering_factor
  FROM dba_indexes i
  JOIN dba_ind_columns c ON i.owner = c.index_owner
                         AND i.index_name = c.index_name
 WHERE i.owner = USER
   AND i.table_name IN ('CUSTOMERS', 'INVOICES')
 GROUP BY i.index_name, i.index_type, i.uniqueness, i.last_analyzed,
          i.distinct_keys, i.clustering_factor
 ORDER BY i.table_name;


--==============================================================================
-- ETAPA 6: Atualizar stats (se desatualizadas)
--==============================================================================

-- Tabela única
EXEC DBMS_STATS.gather_table_stats(
  ownname          => USER,
  tabname          => 'INVOICES',
  estimate_percent => DBMS_STATS.auto_sample_size,
  method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
  cascade          => TRUE,                    -- inclui indexes
  degree           => DBMS_STATS.default_degree
);

-- Coluna específica com histograma forçado (para distribuição skewed)
EXEC DBMS_STATS.gather_table_stats(
  ownname    => USER,
  tabname    => 'INVOICES',
  method_opt => 'FOR COLUMNS status SIZE 254'
);


--==============================================================================
-- ETAPA 7: Decidir ação baseado no diagnóstico
--==============================================================================

/*
Sintoma 1: TABLE ACCESS FULL em tabela grande, WHERE seletivo
  → Falta index na coluna do WHERE
  → Use index_strategy_examples.sql

Sintoma 2: INDEX FULL SCAN em coluna que deveria ser RANGE SCAN
  → Predicado mascara o uso do index (função em coluna)
  → Reescreva predicado ou crie function-based index

Sintoma 3: NESTED LOOPS com cardinalidade alta na driving table
  → Optimizer escolheu errado, deveria HASH JOIN
  → Atualize stats. Se persistir, hint USE_HASH

Sintoma 4: HASH JOIN com TEMP spill
  → Hash table não cabe em memória
  → Aumente PGA, ou filtre antes do join, ou particione

Sintoma 5: SORT em ORDER BY/GROUP BY
  → Index na coluna evitaria SORT
  → CREATE INDEX em coluna de ordenação

Sintoma 6: VIEW MATERIALIZATION em subquery
  → Subquery sendo materializada pode ser inline ou pior
  → Reescreva como JOIN direto, ou use hint NO_MATERIALIZE
*/


--==============================================================================
-- ETAPA 8: Comparar plans antes/depois (regression analysis)
--==============================================================================

-- Captura plan ANTES de qualquer mudança
SELECT * FROM TABLE(DBMS_XPLAN.display_cursor(
  sql_id => 'abcd1234efgh5',
  format => 'ALL'
));

-- Faz a mudança (cria index, atualiza stats, refatora query)

-- Re-executa query
SELECT /*+ GATHER_PLAN_STATISTICS */ ... ;

-- Captura plan DEPOIS
SELECT * FROM TABLE(DBMS_XPLAN.display_cursor(
  format => 'ALLSTATS LAST'
));

-- Compare:
--   - Cost diminuiu?
--   - A-Rows e A-Time diminuíram?
--   - Buffers diminuíram?
--   - Operação principal mudou (e.g. FULL SCAN → INDEX RANGE SCAN)?


--==============================================================================
-- ETAPA 9: Salvar plan estável (SQL Plan Baseline)
--
-- Quando encontrou um plan bom e quer "fixar" para evitar regressão:
--==============================================================================

-- Captura plan atual da cache em baseline
DECLARE
  l_qtd PLS_INTEGER;
BEGIN
  l_qtd := DBMS_SPM.load_plans_from_cursor_cache(
    sql_id => 'abcd1234efgh5'
  );
  DBMS_OUTPUT.put_line('Plans capturados: ' || l_qtd);
END;
/

-- Listar baselines existentes
SELECT sql_handle, plan_name, enabled, accepted, fixed, created
  FROM dba_sql_plan_baselines
 WHERE sql_text LIKE '%clientes c%';

-- Habilitar/desabilitar
EXEC DBMS_SPM.alter_sql_plan_baseline(
  sql_handle      => 'SQL_abcd1234efgh5',
  plan_name       => 'SQL_PLAN_xyz',
  attribute_name  => 'enabled',
  attribute_value => 'YES'
);


--==============================================================================
-- WORKFLOW RESUMO — checklist de query lenta
--==============================================================================

/*
1. ✅ Capturei plan estimado? (EXPLAIN PLAN FOR + display)
2. ✅ Capturei plan real? (GATHER_PLAN_STATISTICS + display_cursor ALLSTATS)
3. ✅ E-Rows bate com A-Rows?
   ├── Não → atualizar stats (DBMS_STATS.gather_table_stats)
   └── Sim → analisar operações
4. ✅ Operação principal é FULL SCAN em tabela grande?
   ├── Sim, WHERE seletivo → criar index
   ├── Sim, WHERE não-seletivo → revisar predicado ou aceitar
   └── Não → próximo passo
5. ✅ Index sendo usado, mas tipo de scan errado?
   ├── INDEX FULL SCAN → predicado pode estar mascarando
   ├── INDEX SKIP SCAN com >10 valores distintos → criar index melhor
   └── INDEX RANGE SCAN com A-Rows >>> esperado → cardinalidade ruim
6. ✅ Joins escolhidos corretamente?
   ├── NESTED LOOPS lento → considerar HASH JOIN (USE_HASH hint)
   └── HASH JOIN com spill → aumentar PGA
7. ✅ Bind variables sendo usadas? (não há literais que causam hard parse)
8. ✅ Stats atualizadas em todas as tabelas envolvidas?
9. ✅ Privilégios de leitura em V$ views ok? (SELECT_CATALOG_ROLE)
10. ✅ Resultado satisfatório? Salvar baseline se sim.
*/
