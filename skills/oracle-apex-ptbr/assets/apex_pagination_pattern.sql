--==============================================================================
-- Template: APEX Pagination — Padrão Correto
--
-- Uso: configurações e queries para relatorios com pagination performante.
--      Cobre Classic Report e Interactive Report.
--
-- Princípios:
--   - Pagination Type "Row Ranges X to Y" para volumes (2k+ linhas)
--   - Query SEM ORDER BY complexo (usa ROW_NUMBER da APEX)
--   - Items hidden para preservar estado entre requests
--   - Region cache cuidadoso (Always Refresh vs Cached)
--==============================================================================


--==============================================================================
-- 1. Classic Report — configuração no APEX Builder
--==============================================================================

/*
CONFIGURAÇÃO DO REGION (Classic Report):

  Region Type:                 Classic Report
  Source Type:                 SQL Query
  
  Pagination Section:
    Pagination Type:           Row Ranges X to Y (with Set Pagination)
    Number of Rows:            50    (ou referência :G_PAGE_SIZE)
    Number of Rows (Item):     P10_LINHAS_POR_PAGINA  (opcional, dinâmico)
    Maximum Row Count:         10000  (limite duro de segurança)
  
  Page Items to Submit:        P10_FILTRO_STATUS, P10_FILTRO_DATA_INICIO,
                                P10_FILTRO_DATA_FIM
  Region Cache:                Cached  (se filtros pouco mudam)
                              ou Always Refresh (se busca é dinâmica)
*/


--==============================================================================
-- 2. Query do Region — formato correto
--==============================================================================

-- BOM: query simples, ordering em coluna indexada, filtros via items
SELECT
    inv.id,
    inv.numero_fatura,
    cust.nome AS nome_cliente,
    inv.data_emissao,
    inv.data_vencimento,
    inv.valor,
    inv.status
  FROM faturas inv
  JOIN clientes cust ON inv.id_cliente = cust.id
 WHERE (:P10_FILTRO_STATUS IS NULL OR inv.status = :P10_FILTRO_STATUS)
   AND (:P10_FILTRO_DATA_INICIO IS NULL OR inv.data_emissao >= :P10_FILTRO_DATA_INICIO)
   AND (:P10_FILTRO_DATA_FIM IS NULL OR inv.data_emissao <= :P10_FILTRO_DATA_FIM)
 ORDER BY inv.data_emissao DESC, inv.id DESC;
-- ↑ ORDER BY em colunas com index funciona bem com pagination


--==============================================================================
-- 3. Items hidden para preservação de estado
--==============================================================================

/*
ITEMS DA PÁGINA (configure no APEX Builder):

  P10_NUMERO_PAGINA
    Type: Hidden
    Value Protected: Yes
    Default Value: 1
  
  P10_LINHAS_POR_PAGINA
    Type: Hidden  
    Value Protected: Yes
    Default Value: 50
  
  P10_FILTRO_STATUS
    Type: Select List
    LOV: 'A;Ativos,P;Pendentes,D;Concluídos'
    
  P10_FILTRO_DATA_INICIO
    Type: Date Picker
  
  P10_FILTRO_DATA_FIM
    Type: Date Picker
*/


--==============================================================================
-- 4. Interactive Report — particularidades
--==============================================================================

/*
Para IR (Interactive Report), pagination é geralmente automática mas:

  - Habilite "Maximum Rows" no relatório (Region attributes → Source)
  - "Maximum Row Count" também (default 10000 — aumente se preciso, com cuidado)
  - Para volumes >50k linhas, considere converter para Classic Report 
    com pagination explícita — IR fica lento

CONFIGURAÇÃO IR:
  Source SQL:                <a mesma query acima>
  Pagination Display Position: Bottom-Right (default)
  Maximum Rows Per Page:     500  (mas o usuário pode alterar via UI)
  Maximum Row Count:         50000

VANTAGEM IR:
  - Usuário pode salvar visões customizadas
  - Sort/filter/group dinâmicos
  - Export para CSV/Excel automático
  
DESVANTAGEM IR:
  - Performance pior em volumes grandes
  - Customização de display mais complexa
  - Pagination fixa em estilo "1-25 of 1234"
*/


--==============================================================================
-- 5. Refresh com preservação de estado (via JS)
--==============================================================================

/*
JavaScript para refresh preservando filtros:

  apex.region('lista_invoices').refresh();

Se quiser passar items dinamicamente:

  apex.server.process('REFRESH_INVOICES', {
    pageItems: '#P10_FILTRO_STATUS,#P10_FILTRO_DATA_INICIO,#P10_FILTRO_DATA_FIM,#P10_NUMERO_PAGINA'
  }, {
    success: function(data) {
      apex.region('lista_invoices').refresh();
    }
  });
*/


--==============================================================================
-- 6. Query com agregados (footer/totals) — pattern
--==============================================================================

-- Para mostrar totais consolidados como footer do report:
-- Use uma query separada ou subquery em coluna.
-- 
-- ATENÇÃO: total deve refletir TODOS os filtros, não só a página atual.

-- Query do report (página atual):
SELECT id, nome_cliente, valor, status
  FROM invoices_v
 WHERE (:P10_FILTRO_STATUS IS NULL OR status = :P10_FILTRO_STATUS);

-- Query do total (rodapé) — em outra Region tipo "Static" ou via DA:
SELECT
    COUNT(*) AS qtd_total,
    SUM(valor) AS valor_total
  FROM invoices_v
 WHERE (:P10_FILTRO_STATUS IS NULL OR status = :P10_FILTRO_STATUS);


--==============================================================================
-- 7. Antipatterns comuns em pagination APEX
--==============================================================================

/*
ANTI-PATTERN 1: ORDER BY UPPER(coluna) sem function-based index

  -- RUIM: força full scan + sort
  SELECT * FROM clientes
   WHERE status = 'A'
   ORDER BY UPPER(nome);

  -- BOM: criar FBI ou ordenar por coluna direta
  CREATE INDEX idx_cli_upper_nome ON clientes(UPPER(nome));
  -- Agora a query usa o index


ANTI-PATTERN 2: Region Cache "Always" com filtros em items

  -- Cache sempre desatualizado quando usuário muda filtro.
  -- Use "Cached" só quando a query é estável (não depende de filtros UI).


ANTI-PATTERN 3: Items "Source Used: Always" sem necessidade

  -- Causa re-execução do origem a cada request da página.
  -- Use "Only when null" ou "When item null and value null in session".


ANTI-PATTERN 4: COUNT(*) em footer fazendo full scan

  -- Quando volume é grande e o COUNT já é caro:
  --   - Cacheie o COUNT em variável de sessão
  --   - Ou use estimativa via DBMS_STATS


ANTI-PATTERN 5: Query do report dependente de tabela temp em sessão APEX

  -- APEX session pode ser "limpa" entre requests em alguns ambientes.
  -- Se precisa cachear dados, use APEX_COLLECTIONS:
  
  -- Setup:
  APEX_COLLECTION.create_or_truncate_collection('MY_DATA');
  APEX_COLLECTION.add_member('MY_DATA', p_n001 => 100, p_c001 => 'X');
  
  -- Query do report:
  SELECT n001 AS id, c001 AS code FROM apex_collections
   WHERE collection_name = 'MY_DATA';
*/
