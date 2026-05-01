--==============================================================================
-- Template: Gerenciamento de Sessões
--
-- Queries V$SESSION e ações relacionadas: identificar sessões ativas,
-- bloqueios, long-running queries, e killar sessões problemáticas.
--
-- Pré-requisitos:
--   - SELECT_CATALOG_ROLE para ver V$ views completas
--   - ALTER SYSTEM para KILL/DISCONNECT sessions
--==============================================================================


--==============================================================================
-- 1. Sessões ativas no momento (não-IDLE)
--==============================================================================

SELECT
    s.sid,
    s.serial#,
    s.username,
    s.osuser,
    s.machine,
    s.program,
    s.module,
    s.status,
    s.last_call_et AS seconds_in_call,
    s.sql_id,
    SUBSTR(sq.sql_text, 1, 100) AS sql_preview
  FROM v$session s
  LEFT JOIN v$sql sq ON s.sql_id = sq.sql_id
                    AND sq.child_number = s.sql_child_number
 WHERE s.username IS NOT NULL    -- exclui sessões internas Oracle
   AND s.type = 'USER'           -- só usuários (não SYS background)
   AND s.status = 'ATIVO'       -- só executando algo
 ORDER BY s.last_call_et DESC;


--==============================================================================
-- 2. Sessões de um usuário específico
--==============================================================================

SELECT sid, serial#, status, machine, program, module,
       last_call_et AS sec_in_call,
       logon_time, sql_id
  FROM v$session
 WHERE username = 'APP_OWNER'
 ORDER BY logon_time DESC;


--==============================================================================
-- 3. Long-running queries (>60 segundos)
--==============================================================================

SELECT s.sid,
       s.serial#,
       s.username,
       s.last_call_et AS sec_running,
       s.sql_id,
       s.event,
       SUBSTR(sq.sql_text, 1, 200) AS sql_text
  FROM v$session s
  JOIN v$sql sq ON s.sql_id = sq.sql_id
                AND sq.child_number = s.sql_child_number
 WHERE s.status = 'ATIVO'
   AND s.last_call_et > 60
   AND s.username IS NOT NULL
 ORDER BY s.last_call_et DESC;


--==============================================================================
-- 4. Bloqueios — quem está bloqueando quem
--==============================================================================

SELECT
    blocking_session AS blocker_sid,
    sid AS blocked_sid,
    serial#,
    username,
    seconds_in_wait,
    sql_id,
    event,
    blocking_instance
  FROM v$session
 WHERE blocking_session IS NOT NULL
 ORDER BY seconds_in_wait DESC;


--==============================================================================
-- 5. Cadeia completa de bloqueios (árvore)
--==============================================================================

SELECT
    LPAD(' ', 2 * LEVEL) ||
      'SID ' || s.sid || ' (' || s.username || '@' || s.machine || ')' AS chain,
    s.event,
    s.seconds_in_wait,
    s.sql_id,
    s.status
  FROM v$session s
 WHERE LEVEL > 1
    OR EXISTS (
       SELECT 1 FROM v$session b
        WHERE b.blocking_session = s.sid
       )
 CONNECT BY PRIOR s.sid = s.blocking_session
 START WITH s.blocking_session IS NULL
 ORDER SIBLINGS BY s.sid;


--==============================================================================
-- 6. Locks por objeto
--==============================================================================

SELECT
    s.sid,
    s.serial#,
    s.username,
    s.osuser,
    o.owner,
    o.object_name,
    o.object_type,
    DECODE(l.locked_mode,
           0, 'None',
           1, 'Null',
           2, 'Row-S (SS)',
           3, 'Row-X (SX)',
           4, 'Share',
           5, 'S/Row-X (SSX)',
           6, 'Exclusive') AS lock_mode,
    s.status,
    s.last_call_et
  FROM v$locked_object l
  JOIN v$session s ON l.session_id = s.sid
  JOIN dba_objects o ON l.object_id = o.object_id
 ORDER BY o.owner, o.object_name, s.sid;


--==============================================================================
-- 7. KILL session — uso operacional
--==============================================================================

-- ANTES de KILL, sempre identifique o que a sessão está fazendo:
SELECT
    sid, serial#, username, machine, status,
    last_call_et AS sec_in_call,
    sql_id,
    (SELECT sql_text FROM v$sql 
      WHERE sql_id = s.sql_id 
        AND rownum = 1) AS sql_text
  FROM v$session s
 WHERE sid = 1234;  -- ← substitua pelo SID real

-- Se confirmou que pode killar, em single-instance:
-- ALTER SYSTEM KILL SESSION '1234,5678' IMMEDIATE;
--                            ↑sid ↑serial#

-- Em RAC, especifique a instância:
-- ALTER SYSTEM KILL SESSION '1234,5678,@2' IMMEDIATE;
--                                      ↑instance_id

-- Alternativa mais "graciosa" (espera transação corrente terminar):
-- ALTER SYSTEM DISCONNECT SESSION '1234,5678' IMMEDIATE;

-- ATENÇÃO:
--  - Killar transação ativa força ROLLBACK (pode demorar muito em DML grande)
--  - Sessão em PMON cleanup demora a sumir do V$SESSION (até 1 minuto)
--  - Status muda para 'KILLED' antes de desaparecer


--==============================================================================
-- 8. RAC — Sessões em todas instâncias
--==============================================================================

SELECT inst_id, sid, serial#, username, machine, program, status,
       last_call_et, sql_id
  FROM gv$session
 WHERE username IS NOT NULL
   AND type = 'USER'
   AND status = 'ATIVO'
 ORDER BY inst_id, sid;

-- Identifica instâncias disponíveis
SELECT instance_number, instance_name, host_name, status, version
  FROM gv$instance
 ORDER BY instance_number;


--==============================================================================
-- 9. Wait eventos — onde a sessão está esperando
--==============================================================================

SELECT s.sid, s.serial#, s.username, s.event, s.wait_class,
       s.seconds_in_wait, s.state, s.sql_id
  FROM v$session s
 WHERE s.username IS NOT NULL
   AND s.status = 'ATIVO'
   AND s.event NOT LIKE 'SQL*Net%idle%'
   AND s.wait_class != 'Idle'
 ORDER BY s.seconds_in_wait DESC;


--==============================================================================
-- 10. Histórico de waits por sessão (últimos 10 minutos)
--==============================================================================

-- Active Session History (ASH) — exige Diagnostic Pack license
SELECT sample_time,
       session_id,
       session_state,
       event,
       sql_id,
       blocking_session
  FROM v$active_session_history
 WHERE sample_time > SYSDATE - INTERVAL '10' MINUTE
   AND session_id = 1234
 ORDER BY sample_time DESC;


--==============================================================================
-- 11. Sessions aging out — identificar sessões velhas mas inativas
--==============================================================================

SELECT
    sid, serial#, username, status, machine, program,
    ROUND((SYSDATE - logon_time) * 24, 2) AS hours_logged_in,
    last_call_et AS sec_since_last_call
  FROM v$session
 WHERE username IS NOT NULL
   AND status = 'INATIVO'
   AND (SYSDATE - logon_time) > 1/24  -- mais de 1 hora logado
   AND last_call_et > 1800            -- inativa por >30 minutos
 ORDER BY logon_time;


--==============================================================================
-- 12. Estatísticas por sessão (uso de recursos)
--==============================================================================

SELECT s.sid, s.username, s.program,
       NVL(stat.physical_reads, 0) AS physical_reads,
       NVL(stat.logical_reads, 0) AS logical_reads,
       NVL(stat.cpu_used, 0) AS cpu_used,
       NVL(stat.executions, 0) AS executions
  FROM v$session s
  LEFT JOIN (
       SELECT sid,
              SUM(CASE WHEN nome = 'physical reads' THEN value END) AS physical_reads,
              SUM(CASE WHEN nome = 'session logical reads' THEN value END) AS logical_reads,
              SUM(CASE WHEN nome = 'CPU used by this session' THEN value END) AS cpu_used,
              SUM(CASE WHEN nome = 'execute count' THEN value END) AS executions
         FROM v$sesstat ss
         JOIN v$statname sn ON ss.statistic# = sn.statistic#
        WHERE sn.nome IN ('physical reads', 'session logical reads',
                         'CPU used by this session', 'execute count')
        GROUP BY sid
       ) stat ON s.sid = stat.sid
 WHERE s.username IS NOT NULL
 ORDER BY logical_reads DESC NULLS LAST
 FETCH FIRST 20 ROWS ONLY;
