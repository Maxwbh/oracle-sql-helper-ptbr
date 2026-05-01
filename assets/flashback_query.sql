--==============================================================================
-- Template: Flashback Query — Recuperação de Dados
--
-- Usa AS OF TIMESTAMP / AS OF SCN para consultar dados como estavam em
-- momento passado, dentro do undo retention.
--
-- Pré-requisitos:
--   - Privilégio FLASHBACK ANY TABLE (ou FLASHBACK em tabelas próprias)
--   - undo_retention configurado para abranger o período desejado
--==============================================================================


--==============================================================================
-- 1. Verificar viabilidade — undo retention disponível
--==============================================================================

-- Configuração atual de undo_retention (em segundos)
SHOW PARAMETER undo_retention;

-- Undo retention efetivamente disponível (pode ser menor que configurado se
-- houve necessidade de reuse de espaço)
SELECT TUNED_UNDORETENTION AS available_seconds,
       TUNED_UNDORETENTION/60 AS available_minutes,
       TUNED_UNDORETENTION/3600 AS available_hours
  FROM v$undostat
 WHERE rownum = 1
 ORDER BY end_time DESC;

-- SCN atual (referência para comparação)
SELECT current_scn FROM v$database;

-- Conversão SCN ↔ Timestamp (aproximada)
SELECT timestamp_to_scn(SYSTIMESTAMP - INTERVAL '30' MINUTE) AS scn_30min_ago,
       scn_to_timestamp(123456789) AS timestamp_for_scn
  FROM dual;


--==============================================================================
-- 2. Consultar dados em momento passado — AS OF TIMESTAMP
--==============================================================================

-- Como a tabela estava há 30 minutos
SELECT id, nome, status, ultima_modificacao
  FROM clientes AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE)
 WHERE id = 12345;

-- Em momento específico
SELECT id, nome, status
  FROM clientes AS OF TIMESTAMP TO_TIMESTAMP('2024-04-30 14:30:00', 'YYYY-MM-DD HH24:MI:SS')
 WHERE id = 12345;

-- Em momento de hoje pela manhã
SELECT id, nome, status
  FROM clientes AS OF TIMESTAMP TRUNC(SYSDATE) + INTERVAL '8' HOUR
 WHERE id = 12345;


--==============================================================================
-- 3. Consultar com AS OF SCN — mais preciso
--==============================================================================

-- Capture SCN ANTES de fazer mudanças (para poder voltar com precisão)
DECLARE
  l_scn NUMBER;
BEGIN
  SELECT current_scn INTO l_scn FROM v$database;
  
  -- Faz a operação que depois pode precisar reverter
  UPDATE clientes SET status = 'INATIVO' WHERE id = 12345;
  COMMIT;
  
  DBMS_OUTPUT.put_line('SCN ANTES da operação: ' || l_scn);
  DBMS_OUTPUT.put_line('Para reverter, use: AS OF SCN ' || l_scn);
END;
/

-- Mais tarde, recupere com SCN
SELECT id, nome, status
  FROM clientes AS OF SCN 1234567890
 WHERE id = 12345;


--==============================================================================
-- 4. Comparar versão atual vs anterior
--==============================================================================

-- Mostra diferenças entre estado atual e há 1 hora
SELECT
    a.id,
    a.nome AS atual_name,
    h.nome AS antigo_name,
    a.status AS atual_status,
    h.status AS antigo_status,
    CASE WHEN a.nome <> h.nome OR a.status <> h.status THEN 'ALTERADO'
         ELSE 'INALTERADO' END AS situacao
  FROM clientes a
  JOIN clientes AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR) h
    ON a.id = h.id
 WHERE a.id IN (12345, 12346, 12347)
 ORDER BY a.id;


--==============================================================================
-- 5. Recuperar registro deletado (re-inserir)
--==============================================================================

-- Recupera linha que foi deletada nas últimas 30 minutos
INSERT INTO clientes (id, nome, status, criado_em)
SELECT id, nome, status, criado_em
  FROM clientes AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE)
 WHERE id = 12345
   AND NOT EXISTS (
       SELECT 1 FROM clientes WHERE id = 12345
   );

COMMIT;


--==============================================================================
-- 6. FLASHBACK TABLE — restaurar tabela inteira
--==============================================================================

-- Pré-requisito: row movement habilitado (uma vez)
ALTER TABLE clientes ENABLE ROW MOVEMENT;

-- Restaurar tabela ao estado de 30 minutos atrás
FLASHBACK TABLE clientes
  TO TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE);

-- Ou ao SCN específico
FLASHBACK TABLE clientes TO SCN 1234567890;

-- Restaurar para BEFORE DROP (se foi feito DROP TABLE recentemente)
-- Tabela tem que estar na recyclebin
FLASHBACK TABLE clientes TO BEFORE DROP;


--==============================================================================
-- 7. FLASHBACK VERSIONS QUERY — histórico de mudanças
--==============================================================================

-- Mostra todas as versões de uma linha em um intervalo
-- Útil para auditoria: "quem alterou e quando?"
SELECT
    versions_starttime,
    versions_endtime,
    versions_xid,
    DECODE(versions_operation,
           'I', 'INSERT',
           'U', 'UPDATE',
           'D', 'DELETE',
           versions_operation) AS operation,
    id, nome, status
  FROM clientes
 VERSIONS BETWEEN TIMESTAMP (SYSTIMESTAMP - INTERVAL '2' HOUR) AND SYSTIMESTAMP
 WHERE id = 12345
 ORDER BY versions_starttime;


--==============================================================================
-- 8. Identificar quem fez a transação (com flashback transaction query)
--==============================================================================

-- Pré-requisito: SUPPLEMENTAL LOG DATA habilitado
-- (geralmente exige privilégio DBA — só funciona se já configurado)
SELECT
    fxid.start_timestamp,
    fxid.commit_timestamp,
    fxid.logon_user,
    fxid.undo_change#,
    fxid.operation,
    fxid.table_name,
    fxid.row_id
  FROM flashback_transaction_query fxid
 WHERE fxid.table_name = 'CUSTOMERS'
   AND fxid.commit_timestamp BETWEEN
       SYSTIMESTAMP - INTERVAL '2' HOUR AND SYSTIMESTAMP
 ORDER BY fxid.start_timestamp DESC;


--==============================================================================
-- Limitações importantes
--==============================================================================

/*
1. UNDO RETENTION é o teto:
   - Padrão: 900 segundos (15 minutos)
   - Configure undo_retention maior se precisa janela maior
   - Mesmo assim, undo pode ser sobrescrito se sistema precisa de espaço

2. DDL invalida flashback:
   - TRUNCATE, DROP COLUMN, ALTER TABLE estrutural
   - Após DDL, não pode mais consultar AS OF antes do DDL na mesma tabela

3. Flashback Database (não usado aqui):
   - Reverte BANCO INTEIRO a um momento
   - Exige configuração prévia (RECYCLE BIN, FAST_START_MTTR_TARGET)
   - Operação destrutiva — desfaz tudo

4. Erro ORA-01555 "snapshot too old":
   - Significa que undo expirou — não dá mais para voltar tão atrás
   - Se aparecer, undo retention era insuficiente

5. Em RAC:
   - SCN é global — funciona em todas instâncias
   - undo retention pode variar por instância
*/
