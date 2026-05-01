--==============================================================================
-- Template: Index Strategy — Quando criar, qual tipo, casos antes×depois
--
-- Foco prático: cenários comuns onde indexes resolvem (ou não) e qual tipo
-- escolher. Cada caso mostra query, plan antes, ação, plan depois.
--==============================================================================


--==============================================================================
-- CASO 1: Coluna em WHERE com alta seletividade
--
-- Query: buscar fatura específica
-- Tabela: faturas (1M linhas)
-- Coluna: numero_fatura (1M valores distintos, único)
--==============================================================================

-- ANTES — FULL SCAN da tabela (custoso)
/*
SELECT * FROM faturas WHERE numero_fatura = '2024-000123';

| Operation         | Name     | Rows | Cost  |
| TABLE ACCESS FULL | INVOICES | 1    | 4500  |
*/

-- AÇÃO: criar unique index
CREATE UNIQUE INDEX uk_fatura_numero ON faturas(numero_fatura);

-- DEPOIS — INDEX UNIQUE SCAN (poucos LIOs)
/*
| Operation                    | Name           | Rows | Cost |
| TABLE ACCESS BY INDEX ROWID  | INVOICES       | 1    | 3    |
|  INDEX UNIQUE SCAN           | UK_FATURA_NUMERO  | 1    | 2    |
*/

-- Resultado: cost 4500 → 3 (1500x melhor)


--==============================================================================
-- CASO 2: Coluna em WHERE + ORDER BY
--
-- Query: lista faturas de um cliente, mais recentes primeiro
-- Tabela: faturas (1M linhas, 50k clientes ⇒ ~20 faturas/cliente)
--==============================================================================

-- ANTES — FULL SCAN + SORT
/*
SELECT * FROM faturas 
 WHERE id_cliente = 12345 
 ORDER BY data_emissao DESC;

| Operation              | Name     | Rows | Cost |
| SORT ORDER BY          |          | 20   | 4502 |
|  TABLE ACCESS FULL     | INVOICES | 20   | 4500 |
*/

-- AÇÃO: composite index com ORDER BY incluído
CREATE INDEX idx_fat_cli_data ON faturas(id_cliente, data_emissao DESC);

-- DEPOIS — INDEX RANGE SCAN, sem SORT
/*
| Operation                    | Name              | Rows | Cost |
| TABLE ACCESS BY INDEX ROWID  | INVOICES          | 20   | 5    |
|  INDEX RANGE SCAN DESCENDING | IDX_FAT_CLI_DATA | 20   | 3    |
*/

-- Por que funciona:
--   - id_cliente é prefixo do índice → range scan eficiente
--   - data_emissao está no índice → não precisa ler tabela para ordenar
--   - DESCENDING é nativo do índice (ou range scan reverso)


--==============================================================================
-- CASO 3: Função em coluna do WHERE (function-based index)
--
-- Query: buscar cliente por nome (case-insensitive)
--==============================================================================

-- ANTES — função UPPER mascara index regular
/*
SELECT * FROM clientes WHERE UPPER(nome) = 'JOAO SILVA';

| Operation         | Name      | Rows | Cost |
| TABLE ACCESS FULL | CUSTOMERS | 1    | 200  |  -- index em nome não usado
*/

-- AÇÃO: function-based index
CREATE INDEX idx_cli_upper_nome ON clientes(UPPER(nome));

-- DEPOIS — usa o FBI
/*
| Operation                    | Name                 | Rows | Cost |
| TABLE ACCESS BY INDEX ROWID  | CUSTOMERS            | 1    | 4    |
|  INDEX RANGE SCAN            | IDX_CLI_UPPER_NOME  | 1    | 2    |
*/

-- Princípio: predicado e índice precisam ter EXATAMENTE a mesma função


--==============================================================================
-- CASO 4: Coluna com baixa cardinalidade (B-tree NÃO é melhor escolha)
--
-- Query: contar registros por status
-- Tabela: eventos (10M linhas), coluna status com 5 valores distintos
--==============================================================================

-- TENTATIVA 1: B-tree index (default)
CREATE INDEX idx_eventos_status ON eventos(status);

/*
SELECT COUNT(*) FROM eventos WHERE status = 'PENDENTE';

Optimizer pode escolher full scan:
| TABLE ACCESS FULL | EVENTS | 2M | 25000 |

Ou index range scan (lento, lê 2M ROWIDs):
| INDEX RANGE SCAN | IDX_EVENTOS_STATUS | 2M | 8000 |
*/

-- TENTATIVA 2: Bitmap index (melhor para baixa cardinalidade EM DW)
DROP INDEX idx_eventos_status;
CREATE BITMAP INDEX idx_eventos_status_bm ON eventos(status);

/*
| Operation               | Name                  | Rows | Cost |
| BITMAP CONVERSION COUNT |                       | 2M   | 50   |
|  BITMAP INDEX SINGLE VALUE | IDX_EVENTOS_STATUS_BM | 1   | 50   |
*/

-- ATENÇÃO:
--   - Bitmap só em data warehouse / OLAP (poucas escritas)
--   - Em OLTP, bitmap causa locks pesados em INSERT/UPDATE
--   - Para tabela transacional típica, prefira FULL SCAN ou rever modelagem


--==============================================================================
-- CASO 5: Composite index — ordem das colunas importa
--
-- Query A: WHERE id_cliente = X
-- Query B: WHERE data_emissao BETWEEN Y AND Z
-- Query C: WHERE id_cliente = X AND data_emissao BETWEEN Y AND Z
--==============================================================================

-- ÍNDICE 1: (id_cliente, data_emissao)
CREATE INDEX idx_fat_cd ON faturas(id_cliente, data_emissao);

/*
Query A (id_cliente = X):
  ✅ USA o índice (id_cliente é prefixo)
  | INDEX RANGE SCAN | IDX_FAT_CD |

Query B (data_emissao BETWEEN ...):
  ❌ NÃO usa o índice (sem prefixo id_cliente)
  | TABLE ACCESS FULL | INVOICES |
  
  EXCEÇÃO: optimizer pode usar INDEX SKIP SCAN se id_cliente tem
  poucos valores distintos. Mas geralmente é ruim.

Query C (ambos):
  ✅ USA o índice perfeitamente (range scan composto)
*/

-- ÍNDICE 2: (data_emissao, id_cliente) — ordem inversa
CREATE INDEX idx_fat_dc ON faturas(data_emissao, id_cliente);

/*
Query A (id_cliente = X):
  ❌ NÃO usa (sem prefixo data_emissao)

Query B (data_emissao BETWEEN ...):
  ✅ USA (prefix match)

Query C (ambos):
  ✅ USA mas menos eficiente que ÍNDICE 1 se id_cliente é mais seletivo
*/

-- REGRA: coluna mais seletiva e mais frequentemente filtrada PRIMEIRO


--==============================================================================
-- CASO 6: Covering index (não precisa ler a tabela)
--
-- Query: SELECT id_cliente, total FROM faturas WHERE data_emissao > X
--==============================================================================

-- ANTES — index só em data_emissao, lookup na tabela para id_cliente, total
CREATE INDEX idx_fat_data ON faturas(data_emissao);

/*
| TABLE ACCESS BY INDEX ROWID | INVOICES     | 1000 | 1005 |
|  INDEX RANGE SCAN           | IDX_FAT_DATA | 1000 | 5    |
*/

-- AÇÃO: covering index (todas as colunas da query no índice)
DROP INDEX idx_fat_data;
CREATE INDEX idx_fat_cobertura ON faturas(data_emissao, id_cliente, total);

-- DEPOIS — só lê o índice, não toca a tabela
/*
| INDEX RANGE SCAN | IDX_FAT_COBERTURA | 1000 | 5 |
*/

-- TRADE-OFF:
--   ✅ Query muito mais rápida
--   ❌ Index maior (mais I/O em DML, mais espaço)
--   ❌ Maintenance: cada UPDATE em id_cliente ou total atualiza índice
--   Use só quando query é crítica e DML é menos frequente


--==============================================================================
-- CASO 7: Index em coluna com NULLs
--
-- Particularidade: B-tree NÃO indexa linhas onde TODAS colunas são NULL
--==============================================================================

-- TABELA com 90% NULL na coluna:
--   processado_em: NULL (não processado) ou DATE (processado)

CREATE INDEX idx_fat_processado ON faturas(processado_em);

-- Query: encontrar não processadas (90% das linhas)
/*
SELECT * FROM faturas WHERE processado_em IS NULL;

| TABLE ACCESS FULL | INVOICES |  -- index não ajuda em IS NULL
*/

-- Query: encontrar processadas (10% das linhas)
/*
SELECT * FROM faturas WHERE processado_em IS NOT NULL;

| INDEX FAST FULL SCAN | IDX_FAT_PROCESSADO |  -- só linhas com valor
*/

-- ALTERNATIVA: composite com coluna NOT NULL para incluir NULLs
CREATE INDEX idx_fat_proc_id ON faturas(processado_em, id);

-- Agora IS NULL pode usar índice:
/*
SELECT * FROM faturas WHERE processado_em IS NULL;

| INDEX RANGE SCAN | IDX_FAT_PROC_ID |
*/


--==============================================================================
-- CASO 8: Quando NÃO criar index
--==============================================================================

-- 8.1 Tabela pequena (<10k linhas)
--   Full scan é rápido. Index adiciona overhead em DML sem ganho real.

-- 8.2 Coluna com muitas atualizações
--   Cada UPDATE atualiza o índice. Em tabela com 50% UPDATE/dia,
--   índice em coluna mutável dobra carga de I/O.

-- 8.3 Query retorna >25-30% das linhas
--   Optimizer prefere full scan (LIO menor).
--   Cardinalidade alta + index = pior que full scan.

-- 8.4 Coluna com baixa cardinalidade em OLTP
--   Bitmap é melhor mas perigoso em OLTP. B-tree não ajuda.

-- 8.5 Substituir index existente sem medir
--   Antes de criar mais um, veja se um índice existente pode ser estendido.


--==============================================================================
-- CASO 9: Identificar indexes não utilizados
--==============================================================================

-- Habilita monitoramento (uma vez, em janela de pico de uso real)
BEGIN
  FOR r IN (
    SELECT index_name FROM user_indexes
     WHERE table_name = 'INVOICES'
  ) LOOP
    EXECUTE IMMEDIATE 'ALTER INDEX ' || r.index_name || ' MONITORING USAGE';
  END LOOP;
END;
/

-- Aguarde uns dias de uso normal

-- Consulta resultados
SELECT index_name, used, monitoring, start_monitoring, end_monitoring
  FROM v$object_usage
 WHERE table_name = 'INVOICES';

-- Indexes com used = 'NO' são candidatos a remoção
-- ATENÇÃO: confirme em vários dias e horários (alguns só usados em fim de mês)


--==============================================================================
-- CASO 10: Index para evitar lock em FK
--
-- Particularidade: FK sem index na child table causa locks pesados em DML
-- na parent.
--==============================================================================

-- Modelo:
--   clientes (id PK)
--   faturas (id PK, id_cliente FK references clientes)

-- SEM index em faturas.id_cliente:
--   DELETE FROM clientes WHERE id = 100;
--   → Oracle bloqueia toda faturas até validar FK
--   → Outros usuários não conseguem inserir fatura durante o DELETE

-- COM index em id_cliente:
CREATE INDEX idx_fat_id_cliente ON faturas(id_cliente);
--   → DELETE valida FK rapidamente, sem lock pesado

-- REGRA: SEMPRE crie index em colunas FK do lado child


--==============================================================================
-- CASO 11: Stats de index (importantes para optimizer escolher)
--==============================================================================

-- Após criar index, gather stats
EXEC DBMS_STATS.gather_index_stats(
  ownname  => USER,
  indname  => 'IDX_FAT_CLI_DATA'
);

-- Ou cascade ao criar/alterar tabela
EXEC DBMS_STATS.gather_table_stats(
  ownname => USER,
  tabname => 'INVOICES',
  cascade => TRUE  -- inclui todos os indexes
);

-- Verifica clustering factor (mais baixo = melhor)
SELECT index_name,
       num_rows,
       distinct_keys,
       clustering_factor,
       num_rows / NULLIF(distinct_keys, 0) AS avg_rows_per_key,
       last_analyzed
  FROM user_indexes
 WHERE table_name = 'INVOICES'
 ORDER BY index_name;

-- Clustering factor:
--   - Próximo de num_rows: dados desordenados, scan custoso
--   - Próximo de blocks: dados ordenados, scan eficiente
--   - Pode forçar reorganização da tabela ou usar IOT (Index-Organized Table)


--==============================================================================
-- DECISÃO RÁPIDA — qual tipo de index criar?
--==============================================================================

/*
WHERE coluna = valor (alta seletividade, único)
  → UNIQUE INDEX

WHERE coluna = valor (não único, alta seletividade)
  → B-tree INDEX

WHERE coluna IN (lista pequena)
  → B-tree INDEX (mesmo que para =)

WHERE coluna BETWEEN x AND y
  → B-tree INDEX (range scan)

WHERE função(coluna) = valor
  → FUNCTION-BASED INDEX

WHERE coluna LIKE 'prefix%'
  → B-tree INDEX (range scan no prefix)

WHERE coluna LIKE '%middle%'
  → B-tree NÃO ajuda. Considere Oracle Text (CONTEXT index)

ORDER BY coluna (em query frequente)
  → Index inclui essa coluna na posição apropriada

GROUP BY coluna
  → Mesmo que ORDER BY: index pode evitar SORT

JOIN ON tabela1.x = tabela2.y
  → Index na coluna do lado "many" (lookup side)

Coluna FK
  → SEMPRE crie índice (evita lock em DELETE da parent)

Coluna com 90%+ NULL
  → Considere index parcial: WHERE coluna IS NOT NULL

Coluna com poucos valores distintos em DW
  → BITMAP INDEX

Coluna com poucos valores distintos em OLTP
  → Geralmente NÃO indexar (bitmap causa locks)
*/
