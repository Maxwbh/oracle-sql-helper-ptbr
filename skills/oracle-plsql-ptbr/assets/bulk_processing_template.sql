--==============================================================================
-- Template: Bulk Processing com BULK COLLECT + FORALL
--
-- Uso: substitua loops linha-a-linha por este padrão quando processar
--      volumes (>1000 linhas). Performance é tipicamente 10x-100x melhor.
--
-- Inclui:
--   - Variante 1: BULK COLLECT completo (volumes pequenos a médios)
--   - Variante 2: BULK COLLECT com LIMIT (volumes grandes, chunked commit)
--   - Variante 3: FORALL com SAVE EXCEPTIONS (continua em caso de erros)
--==============================================================================


--==============================================================================
-- VARIANTE 1: BULK COLLECT completo
-- Use quando volume cabe em memória (< ~100k linhas tipicamente)
--==============================================================================

DECLARE
  -- Tipo coleção do registro completo
  TYPE t_lista_faturas IS TABLE OF faturas%ROWTYPE;
  l_faturas t_lista_faturas;
BEGIN
  -- Coleta todas as linhas em memória de uma vez
  SELECT *
    BULK COLLECT INTO l_faturas
    FROM faturas
   WHERE status = 'PENDENTE';

  -- Processa em bulk
  FORALL i IN l_faturas.FIRST..l_faturas.LAST
    UPDATE arquivo_faturas
       SET valor = l_faturas(i).valor,
           arquivado_em = SYSDATE
     WHERE id = l_faturas(i).id;

  COMMIT;
  
  DBMS_OUTPUT.put_line('Processadas ' || l_faturas.COUNT || ' faturas');
END;
/


--==============================================================================
-- VARIANTE 2: BULK COLLECT com LIMIT (chunked)
-- Use para volumes grandes que não cabem em memória ou para commits parciais
-- 
-- LIMIT 10000 é um valor típico — ajuste conforme:
--   - Memória disponível na sessão (PGA)
--   - Tamanho médio das linhas
--   - Frequência de COMMIT desejada
--==============================================================================

DECLARE
  CURSOR co_faturas IS
    SELECT id, id_cliente, valor, data_vencimento
      FROM faturas
     WHERE status = 'PENDENTE';

  TYPE t_lista_faturas IS TABLE OF co_faturas%ROWTYPE;
  l_faturas t_lista_faturas;

  lc_tamanho_chunk CONSTANT PLS_INTEGER := 10000;
  l_total_linhas   PLS_INTEGER := 0;
BEGIN
  OPEN co_faturas;
  LOOP
    -- Pega chunk de até 10000 linhas
    FETCH co_faturas BULK COLLECT INTO l_faturas LIMIT lc_tamanho_chunk;
    
    -- Sai quando não há mais linhas
    EXIT WHEN l_faturas.COUNT = 0;

    -- Processa chunk
    FORALL i IN l_faturas.FIRST..l_faturas.LAST
      INSERT INTO log_processamento_faturas (
        id_fatura, id_cliente, valor, data_vencimento, processado_em
      ) VALUES (
        l_faturas(i).id,
        l_faturas(i).id_cliente,
        l_faturas(i).valor,
        l_faturas(i).data_vencimento,
        SYSDATE
      );

    l_total_linhas := l_total_linhas + l_faturas.COUNT;
    
    -- Commit por chunk para liberar undo (importante em volumes grandes)
    COMMIT;
    
    DBMS_OUTPUT.put_line('Chunk processado. Total acumulado: ' || l_total_linhas);
  END LOOP;
  CLOSE co_faturas;
  
  DBMS_OUTPUT.put_line('Total final: ' || l_total_linhas || ' linhas processadas');
END;
/


--==============================================================================
-- VARIANTE 3: FORALL com SAVE EXCEPTIONS
-- Use quando algumas linhas podem falhar mas o processamento deve continuar.
-- Exemplo: carga de dados com possíveis violações de constraint pontuais.
--==============================================================================

DECLARE
  TYPE t_lista_ids IS TABLE OF NUMBER;
  l_ids t_lista_ids := t_lista_ids();
  
  -- Tipo para erros capturados pelo SAVE EXCEPTIONS
  l_qtd_erros NUMBER;
  l_indice    NUMBER;
  
  -- Exception oficial do SAVE EXCEPTIONS
  e_erros_bulk EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_erros_bulk, -24381);
BEGIN
  -- Popula a coleção (em uso real, viria de SELECT BULK COLLECT)
  l_ids.EXTEND(5);
  l_ids(1) := 100; l_ids(2) := 200; l_ids(3) := 300;
  l_ids(4) := 400; l_ids(5) := 500;

  BEGIN
    FORALL i IN l_ids.FIRST..l_ids.LAST SAVE EXCEPTIONS
      UPDATE faturas
         SET status = 'ARQUIVADO',
             arquivado_em = SYSDATE
       WHERE id = l_ids(i);
  EXCEPTION
    WHEN e_erros_bulk THEN
      -- Captura erros individuais sem abortar o batch
      l_qtd_erros := SQL%BULK_EXCEPTIONS.COUNT;
      DBMS_OUTPUT.put_line('Total de erros: ' || l_qtd_erros);
      
      FOR j IN 1..l_qtd_erros LOOP
        l_indice := SQL%BULK_EXCEPTIONS(j).ERROR_INDEX;
        
        DBMS_OUTPUT.put_line(
          'Linha ' || l_indice ||
          ' (ID = ' || l_ids(l_indice) || '): ' ||
          SQLERRM(-SQL%BULK_EXCEPTIONS(j).ERROR_CODE)
        );
        
        -- Aqui você poderia inserir erros em tabela de log
        INSERT INTO log_erros_bulk (data_processamento, id_registro, mensagem_erro)
        VALUES (
          SYSDATE,
          l_ids(l_indice),
          SQLERRM(-SQL%BULK_EXCEPTIONS(j).ERROR_CODE)
        );
      END LOOP;
  END;
  
  COMMIT;
  
  DBMS_OUTPUT.put_line('Processamento concluído. ' || 
                      (l_ids.COUNT - NVL(l_qtd_erros, 0)) || ' sucessos, ' ||
                      NVL(l_qtd_erros, 0) || ' falhas.');
END;
/


--==============================================================================
-- Anti-patterns a EVITAR (comentários para referência)
--==============================================================================

/*
ANTI-PATTERN 1: Loop linha-a-linha em volume

  -- RUIM: cada UPDATE é uma round-trip ao SQL engine
  FOR r IN (SELECT id FROM faturas WHERE status = 'PENDENTE') LOOP
    UPDATE arquivo_faturas SET ... WHERE id = r.id;
  END LOOP;

  -- BOM: BULK COLLECT + FORALL


ANTI-PATTERN 2: BULK COLLECT sem LIMIT em tabela enorme

  -- RUIM: pode estourar PGA em tabelas com milhões de linhas
  SELECT * BULK COLLECT INTO l_colecao_gigante FROM tabela_enorme;

  -- BOM: usar LIMIT no FETCH (Variante 2 acima)


ANTI-PATTERN 3: COMMIT dentro de FOR loop sem chunking

  -- RUIM: COMMIT por linha é overhead enorme
  FOR r IN (...) LOOP
    UPDATE ...;
    COMMIT;  -- ❌
  END LOOP;

  -- BOM: COMMIT por chunk (Variante 2)


ANTI-PATTERN 4: Capturar e ignorar erros silenciosamente em FORALL

  -- RUIM: perde informação do erro
  BEGIN
    FORALL i IN 1..1000 SAVE EXCEPTIONS
      UPDATE ...;
  EXCEPTION
    WHEN OTHERS THEN NULL;  -- ❌
  END;

  -- BOM: capturar e_erros_bulk e logar individualmente (Variante 3)
*/
