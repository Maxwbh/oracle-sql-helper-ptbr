# DBA Operations — Tarefas Operacionais Recorrentes

Operações que desenvolvedor sênior Oracle faz no dia-a-dia: monitorar sessões, identificar bloqueios, recompilar objetos inválidos, recuperar dados com flashback. Foco em **diagnóstico e correção rápida**, não administração profunda (DBA dedicado).

## Pré-requisitos de privilégios

A maioria dessas operações exige roles além de DBA básico:

| Operação | Privilégio necessário |
|---|---|
| Ver V$SESSION (todas) | SELECT_CATALOG_ROLE ou SELECT ANY DICTIONARY |
| KILL session | ALTER SYSTEM |
| Flashback query (own schema) | FLASHBACK em tabelas próprias |
| Flashback query (outros) | FLASHBACK ANY TABLE |
| Recompile schema | DBA ou ALTER ANY PROCEDURE/TYPE/TRIGGER |
| Ver waits e locks | SELECT_CATALOG_ROLE |

Princípio Trivadis: **privilégio mínimo necessário**. Não use SYS exceto se realmente precisar.

## Sessões — V$SESSION e relacionadas

### Sessões ativas no momento

```sql
-- Sessões ativas (não em IDLE)
SELECT
    s.sid,
    s.serial#,
    s.username,
    s.osuser,
    s.machine,
    s.program,
    s.status,
    s.sql_id,
    s.last_call_et AS seconds_in_call,
    sq.sql_text
  FROM v$session s
  LEFT JOIN v$sql sq ON s.sql_id = sq.sql_id
                   AND sq.child_number = s.sql_child_number
 WHERE s.username IS NOT NULL
   AND s.status = 'ATIVO'
   AND s.type = 'USER'
 ORDER BY s.last_call_et DESC;
```

### Sessões de um usuário específico

```sql
SELECT sid, serial#, status, machine, program, last_call_et,
       logon_time, sql_id
  FROM v$session
 WHERE username = 'MS_APP'
 ORDER BY logon_time DESC;
```

### Long-running queries

```sql
-- Sessões com query rodando > 60 segundos
SELECT s.sid, s.serial#, s.username, s.last_call_et, s.sql_id,
       sq.sql_text
  FROM v$session s
  JOIN v$sql sq ON s.sql_id = sq.sql_id
                AND sq.child_number = s.sql_child_number
 WHERE s.status = 'ATIVO'
   AND s.last_call_et > 60
   AND s.username IS NOT NULL
 ORDER BY s.last_call_et DESC;
```

## Bloqueios (Locks)

### Identificar bloqueios

```sql
-- Quem bloqueia quem
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
```

### Cadeia completa de bloqueios (RAC-aware)

```sql
SELECT
    LPAD(' ', 2*LEVEL) || s.sid || ', ' || s.username || ' (' || s.osuser || ')' AS session_chain,
    s.event,
    s.seconds_in_wait,
    s.sql_id,
    s.machine
  FROM v$session s
 WHERE LEVEL > 1 OR EXISTS (
       SELECT 1 FROM v$session WHERE blocking_session = s.sid
       )
 CONNECT BY PRIOR s.sid = s.blocking_session
 START WITH s.blocking_session IS NULL;
```

### Locks por objeto

```sql
SELECT
    s.sid, s.serial#, s.username,
    o.object_name, o.object_type,
    DECODE(l.locked_mode,
           0, 'None',  1, 'Null',  2, 'Row-S',
           3, 'Row-X', 4, 'Share', 5, 'S/Row-X',
           6, 'Exclusive') AS lock_mode
  FROM v$locked_object l
  JOIN v$session s ON l.session_id = s.sid
  JOIN dba_objects o ON l.object_id = o.object_id
 ORDER BY s.sid, o.object_name;
```

### Killar sessão (último recurso)

```sql
-- Identifica primeiro
SELECT sid, serial#, username, machine, status
  FROM v$session
 WHERE sid = 1234;

-- Kill local (single instance)
ALTER SYSTEM KILL SESSION '1234,5678' IMMEDIATE;

-- Kill em RAC (especifica instância)
ALTER SYSTEM KILL SESSION '1234,5678,@2' IMMEDIATE;
--                                    ^ instance_id

-- DISCONNECT é alternativa mais "graciosa"
ALTER SYSTEM DISCONNECT SESSION '1234,5678' IMMEDIATE;
```

**Cuidado:** `KILL` interrompe transação ativa. Operações DML em andamento sofrem rollback automático, o que pode ser longo (horas em DML grande).

## RAC — Particularidades

```sql
-- Em RAC, V$SESSION é da instância local; GV$SESSION é global
SELECT inst_id, sid, serial#, username, machine, status
  FROM gv$session
 WHERE username = 'MS_APP'
 ORDER BY inst_id, sid;

-- Identifica qual instância
SELECT instance_number, instance_name, host_name, status
  FROM gv$instance
 ORDER BY instance_number;
```

## Objetos Inválidos

### Listar invalid objects

```sql
SELECT owner, object_name, object_type, status, last_ddl_time
  FROM dba_objects
 WHERE status = 'INVALID'
   AND owner NOT IN ('SYS', 'SYSTEM', 'XDB', 'CTXSYS')  -- ignora system schemas
 ORDER BY owner, object_type, object_name;
```

### Recompilar (em ordem segura)

```sql
-- Schema-wide (procedures, packages, views, types em ordem de dependência)
EXEC DBMS_UTILITY.compile_schema(schema => 'MS_APP', compile_all => FALSE);

-- compile_all=FALSE: só recompila inválidos (recomendado)
-- compile_all=TRUE:  recompila tudo (lento, raramente necessário)
```

### Recompile individual

```sql
-- Package
ALTER PACKAGE ms_app.payment_pkg COMPILE;
ALTER PACKAGE ms_app.payment_pkg COMPILE BODY;

-- Procedure
ALTER PROCEDURE ms_app.processar_fatura COMPILE;

-- Type (pode invalidar dependentes)
ALTER TYPE ms_app.t_payment COMPILE;

-- View
ALTER VIEW ms_app.v_active_invoices COMPILE;
```

### Verificar erros após compile

```sql
-- Erros do último compile no schema
SELECT name, type, line, position, text
  FROM user_errors
 ORDER BY name, sequence;

-- Para outro schema (precisa privilégio)
SELECT owner, name, type, line, position, text
  FROM dba_errors
 WHERE owner = 'MS_APP'
 ORDER BY owner, name, sequence;
```

### Por que objetos ficam inválidos

| Causa | Solução |
|---|---|
| Tabela usada por package teve coluna alterada | ALTER PACKAGE ... COMPILE |
| Privilégio revogado | Restaurar privilégio + recompilar |
| Type dependency (TYPE alterado) | Recompilar TYPE BODY + dependentes em ordem |
| Sinônimo apontando para objeto deletado | Recriar/redirecionar synonym |
| Patch de Oracle | Pós-patch, rodar `?/rdbms/admin/utlrp.sql` |

## Flashback Query — Recuperação

Permite consultar dados como estavam em momento passado, **dentro do undo retention** (geralmente 15min-1h, configurável).

### AS OF TIMESTAMP

```sql
-- Como a tabela estava há 30 minutos
SELECT * FROM clientes
  AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE)
 WHERE id = 12345;

-- Em momento específico
SELECT * FROM clientes
  AS OF TIMESTAMP TO_TIMESTAMP('2024-04-30 14:30:00', 'YYYY-MM-DD HH24:MI:SS')
 WHERE id = 12345;
```

### AS OF SCN

System Change Number — mais preciso e estável que timestamp.

```sql
-- Pega SCN atual
SELECT current_scn FROM v$database;

-- Mais tarde, recupera com SCN anterior
SELECT * FROM clientes
  AS OF SCN 1234567890
 WHERE id = 12345;
```

### Recuperar registro deletado

```sql
-- Tabela em momento anterior
INSERT INTO clientes (id, name, status)
SELECT id, name, status
  FROM clientes AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR)
 WHERE id = 12345
   AND NOT EXISTS (SELECT 1 FROM clientes WHERE id = 12345);
```

### FLASHBACK TABLE (restaurar tabela inteira)

```sql
-- Habilita row movement (uma vez)
ALTER TABLE clientes ENABLE ROW MOVEMENT;

-- Restaura
FLASHBACK TABLE clientes TO TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE);
```

**Cuidado:**
- Operações DDL (TRUNCATE, DROP COLUMN) impedem flashback subsequente
- Undo retention precisa abranger o período desejado: `SHOW PARAMETER undo_retention`
- Para períodos longos: Flashback Database (precisa configuração prévia)

### Verificar se flashback é viável

```sql
-- Undo retention atual
SHOW PARAMETER undo_retention;  -- valor em segundos

-- Quanto undo está disponível
SELECT TUNED_UNDORETENTION FROM v$undostat
 WHERE rownum = 1
 ORDER BY end_time DESC;

-- Tentar query, se falhar com ORA-01555 "snapshot too old", undo expirou
```

## Tablespaces e espaço

### Uso de tablespace

```sql
SELECT
    df.tablespace_name,
    ROUND(df.bytes/1024/1024, 2)        AS allocated_mb,
    ROUND(NVL(fs.bytes,0)/1024/1024, 2) AS free_mb,
    ROUND((df.bytes - NVL(fs.bytes,0)) * 100 / df.bytes, 2) AS pct_used
  FROM (SELECT tablespace_name, SUM(bytes) AS bytes
          FROM dba_data_files
         GROUP BY tablespace_name) df
  LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS bytes
               FROM dba_free_space
              GROUP BY tablespace_name) fs
    ON df.tablespace_name = fs.tablespace_name
 ORDER BY pct_used DESC;
```

### Top tabelas por tamanho

```sql
SELECT owner, segment_name, segment_type, ROUND(bytes/1024/1024, 2) AS mb
  FROM dba_segments
 WHERE owner = 'MS_APP'
 ORDER BY bytes DESC
 FETCH FIRST 20 ROWS ONLY;
```

## Statistics

### Atualizar estatísticas (importante para optimizer)

```sql
-- Schema inteiro
EXEC DBMS_STATS.gather_schema_stats(ownname => 'MS_APP', cascade => TRUE);

-- Tabela específica + todos os índices
EXEC DBMS_STATS.gather_table_stats(ownname => 'MS_APP',
                                    tabname => 'INVOICES',
                                    cascade => TRUE);

-- Verificar última vez que stats foi colhido
SELECT table_name, last_analyzed, num_rows
  FROM dba_tables
 WHERE owner = 'MS_APP'
 ORDER BY last_analyzed NULLS FIRST;
```

### Quando não atualizar

- Tabelas em uso heavy de write durante o dia (rode à noite)
- Tabelas particionadas grandes (use `granularity => 'PARTITION'`)
- Stats lock proposital para preservar plan

## DBMS_REDEFINITION (mover/renomear tabelas online)

Para alterações em tabelas grandes sem downtime:

```sql
-- Verifica se redefinição é possível
EXEC DBMS_REDEFINITION.can_redef_table('MS_APP', 'INVOICES');

-- Cria tabela interim, copia dados, sincroniza, faz swap
-- Veja documentação completa para passos
```

## Anti-patterns DBA

| Anti-pattern | Por quê |
|---|---|
| `KILL` em sessão sem entender o que faz | Pode rollback gigante, perda de trabalho |
| Recompile com `compile_all => TRUE` em produção | Lento, desnecessário, invalida cache |
| `ALTER SYSTEM` em produção sem janela | Pode afetar todos usuários |
| Flashback em tabela com row movement disabled | Falha — habilite antes |
| Stats em tabela em transformação ETL | Plan instável durante carga |
| Privilégios DBA para usuário aplicação | Vulnerabilidade ampla |
| TRUNCATE em vez de DELETE quando há FK | Erros confusos |

## Linkagem

- Templates prontos em `assets/session_management.sql`, `assets/recompile_invalid_objects.sql`, `assets/flashback_query.sql`
- Para queries lentas → `performance-tuning.md`
- Para PL/SQL com transações complexas → `plsql-trivadis-guidelines.md`
