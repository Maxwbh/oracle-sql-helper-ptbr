# Data Dictionary — Estrutura, Nomenclatura e Compatibilidade

Referência para consulta e uso correto das views do dicionário de dados Oracle. Cobre hierarquia de prefixos, nomenclatura interna de colunas, disponibilidade por edição e tecnologia, evolução entre versões 11g a 26ai, e fontes confiáveis para atualização.

---

## 1. Hierarquia de prefixos

O dicionário Oracle é em camadas: cada camada abstrai a anterior e controla o que o usuário pode enxergar.

```
X$KTFBFE, X$KGLOB ...   ← Tabelas internas (C structs em memória). Só SYS.
       ↓
V$SESSION, V$SQL ...    ← Views fixas sobre X$. SYS + SELECT_CATALOG_ROLE.
GV$SESSION, GV$SQL ...  ← Versão global das V$ (todas instâncias RAC).
       ↓
DBA_OBJECTS, DBA_TABLES ... ← Visão completa do banco. Requer privilégio DBA ou SELECT_CATALOG_ROLE.
ALL_OBJECTS, ALL_TABLES ... ← Objetos que o usuário corrente pode acessar (próprios + grants).
USER_OBJECTS, USER_TABLES ... ← Só objetos do próprio schema. Sem restrição de privilégio.
       ↓
CDB_OBJECTS, CDB_TABLES ... ← Versão multi-tenant das DBA_*. Inclui coluna CON_ID. Só em 12c+/EE.
```

### Quando usar cada prefixo

| Contexto | Prefixo recomendado |
|---|---|
| Script DBA, auditoria, monitoração | `DBA_*` |
| Código de aplicação (package, APEX) | `USER_*` ou `ALL_*` |
| RAC — ver todas as instâncias | `GV$*` |
| CDB/PDB — queries cross-container | `CDB_*` |
| Diagnóstico de performance em tempo real | `V$*` / `GV$*` |
| Histórico de performance (AWR) | `DBA_HIST_*` — **requer Diagnostics Pack** |

### Regra de ouro: `V$` é tempo real, `DBA_HIST_` é histórico

```sql
-- Tempo real (sempre disponível em EE e SE2)
SELECT sql_id, elapsed_time, executions FROM v$sql WHERE ...;

-- Histórico — SÓ com Diagnostics Pack licenciado
SELECT sql_id, elapsed_time_total FROM dba_hist_sqlstat WHERE ...;
```

---

## 2. Nomenclatura interna de colunas

Oracle segue padrões internos consistentes. Conhecê-los evita busca no docs para cada view.

### Sufixos de identificação

| Sufixo | Significado | Exemplo |
|---|---|---|
| `_ID` | Identificador numérico interno | `OBJECT_ID`, `CON_ID`, `INST_ID` |
| `_NAME` | Nome textual do objeto | `TABLE_NAME`, `INDEX_NAME`, `USERNAME` |
| `_TYPE` | Tipo/categoria do objeto | `OBJECT_TYPE`, `SEGMENT_TYPE`, `LOCK_TYPE` |
| `_NO` | Número sequencial ou ordinal | `BLOCK_NO`, `FILE_NO`, `SEQUENCE_NO` |
| `_#` (hash/cardinal) | Identificador de versão/geração | `SERIAL#`, `HASH_VALUE`, `ADDRESS` |

### Sufixos de tamanho e espaço

| Sufixo | Unidade | Exemplo |
|---|---|---|
| `_BYTES` | Bytes | `BYTES`, `BYTES_USED`, `MAX_BYTES` |
| `_BLOCKS` | Blocos Oracle (default 8KB) | `BLOCKS`, `EMPTY_BLOCKS`, `AVG_SPACE` |
| `_MB` | Megabytes (raro, mais em views 12c+) | `TOTAL_MB`, `FREE_MB` |

### Sufixos de tempo

| Sufixo | Formato | Exemplo |
|---|---|---|
| `_TIME` | Timestamp ou intervalo (varia) | `LAST_CALL_ET` (segundos), `LOGON_TIME` (DATE) |
| `_DATE` | Oracle DATE | `LAST_DDL_TIME`, `CREATED`, `LAST_ANALYZED` |
| `_SCN` | System Change Number (NUMBER) | `CURRENT_SCN`, `FIRST_CHANGE#`, `NEXT_CHANGE#` |
| `_ET` | Elapsed Time em segundos | `LAST_CALL_ET`, `SECONDS_IN_WAIT` |
| `_CS` | Centésimos de segundo | `CPU_TIME` (em V$SQL) |
| `_US` | Microssegundos | `ELAPSED_TIME` (em V$SQL) |

### Atenção: mesma unidade, nome diferente por view

```sql
-- V$SQL: ELAPSED_TIME em microssegundos
SELECT elapsed_time / 1e6 AS segundos FROM v$sql;

-- DBA_HIST_SQLSTAT: ELAPSED_TIME_TOTAL também em microssegundos
SELECT elapsed_time_total / 1e6 AS segundos FROM dba_hist_sqlstat;

-- V$SESSION: LAST_CALL_ET em segundos (inteiro)
SELECT last_call_et AS segundos FROM v$session;
```

### Sufixos de status

| Valor comum | Significado |
|---|---|
| `STATUS = 'VALID'` / `'INVALID'` | Objetos compilados (DBA_OBJECTS) |
| `STATUS = 'ACTIVE'` / `'INACTIVE'` / `'KILLED'` | Sessões (V$SESSION) |
| `ENABLED` / `DISABLED` | Constraints, triggers |
| `YES` / `NO` | Flags booleanos (VARCHAR2) |

### Owner vs Username: quando cada um aparece

| Coluna | Views | Conteúdo |
|---|---|---|
| `OWNER` | `DBA_OBJECTS`, `DBA_TABLES`, `DBA_SEGMENTS` | Schema proprietário do objeto |
| `USERNAME` | `DBA_USERS`, `V$SESSION` | Conta de banco de dados |
| `GRANTEE` | `DBA_SYS_PRIVS`, `DBA_TAB_PRIVS` | Quem recebe o privilégio |
| `GRANTOR` | `DBA_TAB_PRIVS` | Quem concedeu |

---

## 3. Mapa por categoria — views mais importantes

### Objetos do banco

| View | Cobre | Colunas-chave |
|---|---|---|
| `DBA_OBJECTS` | Todos os objetos (tables, packages, views...) | `OWNER`, `OBJECT_NAME`, `OBJECT_TYPE`, `STATUS`, `LAST_DDL_TIME` |
| `DBA_SOURCE` | Código-fonte de procedures, functions, packages | `OWNER`, `NAME`, `TYPE`, `LINE`, `TEXT` |
| `DBA_ERRORS` | Erros de compilação | `OWNER`, `NAME`, `TYPE`, `LINE`, `POSITION`, `TEXT` |
| `DBA_DEPENDENCIES` | Dependências entre objetos | `OWNER`, `NAME`, `REFERENCED_OWNER`, `REFERENCED_NAME` |
| `USER_ERRORS` | Erros do schema corrente (sem OWNER) | `NAME`, `TYPE`, `LINE`, `POSITION`, `TEXT` |

### Tabelas e colunas

| View | Cobre | Colunas-chave |
|---|---|---|
| `DBA_TABLES` | Metadados de tabelas | `OWNER`, `TABLE_NAME`, `NUM_ROWS`, `LAST_ANALYZED`, `PARTITIONED` |
| `DBA_TAB_COLUMNS` | Colunas das tabelas | `OWNER`, `TABLE_NAME`, `COLUMN_NAME`, `DATA_TYPE`, `NULLABLE`, `COLUMN_ID` |
| `DBA_TAB_COMMENTS` | Comentários em tabelas | `OWNER`, `TABLE_NAME`, `COMMENTS` |
| `DBA_COL_COMMENTS` | Comentários em colunas | `OWNER`, `TABLE_NAME`, `COLUMN_NAME`, `COMMENTS` |
| `DBA_SEGMENTS` | Espaço físico alocado | `OWNER`, `SEGMENT_NAME`, `SEGMENT_TYPE`, `BYTES`, `BLOCKS` |

### Constraints

| View | Cobre | Colunas-chave |
|---|---|---|
| `DBA_CONSTRAINTS` | Definição das constraints | `OWNER`, `CONSTRAINT_NAME`, `CONSTRAINT_TYPE`, `TABLE_NAME`, `STATUS`, `VALIDATED` |
| `DBA_CONS_COLUMNS` | Colunas que compõem cada constraint | `OWNER`, `CONSTRAINT_NAME`, `TABLE_NAME`, `COLUMN_NAME`, `POSITION` |

Tipos em `CONSTRAINT_TYPE`: `P` (PK), `U` (Unique), `R` (FK), `C` (Check), `V` (View with check option).

### Índices

| View | Cobre | Colunas-chave |
|---|---|---|
| `DBA_INDEXES` | Definição dos índices | `OWNER`, `INDEX_NAME`, `TABLE_NAME`, `INDEX_TYPE`, `STATUS`, `UNIQUENESS`, `PARTITIONED` |
| `DBA_IND_COLUMNS` | Colunas de cada índice | `INDEX_OWNER`, `INDEX_NAME`, `TABLE_NAME`, `COLUMN_NAME`, `COLUMN_POSITION`, `DESCEND` |
| `DBA_IND_EXPRESSIONS` | Índices baseados em função | `INDEX_OWNER`, `INDEX_NAME`, `COLUMN_EXPRESSION`, `COLUMN_POSITION` |

### Sessões e performance em tempo real

| View | Disponibilidade | Colunas-chave |
|---|---|---|
| `V$SESSION` | Todas as edições | `SID`, `SERIAL#`, `USERNAME`, `STATUS`, `SQL_ID`, `EVENT`, `BLOCKING_SESSION`, `LAST_CALL_ET` |
| `GV$SESSION` | RAC (todas as instâncias) | Igual V$SESSION + `INST_ID` |
| `V$SQL` | Todas as edições | `SQL_ID`, `SQL_TEXT`, `EXECUTIONS`, `ELAPSED_TIME`, `CPU_TIME`, `BUFFER_GETS`, `DISK_READS` |
| `V$SQLAREA` | Todas as edições | Agrega V$SQL por SQL_ID (sem child cursors) |
| `V$SESSION_WAIT` | Todas as edições | `SID`, `EVENT`, `WAIT_CLASS`, `SECONDS_IN_WAIT`, `STATE` |
| `V$LOCKED_OBJECT` | Todas as edições | `SESSION_ID`, `OBJECT_ID`, `LOCKED_MODE`, `XIDUSN` |
| `V$ACTIVE_SESSION_HISTORY` | **EE + Diagnostics Pack** | `SAMPLE_TIME`, `SESSION_ID`, `SQL_ID`, `EVENT`, `WAIT_CLASS`, `SESSION_STATE` |

### Histórico de performance (AWR) — somente EE + Diagnostics Pack

| View | Cobre |
|---|---|
| `DBA_HIST_SNAPSHOT` | Snapshots AWR disponíveis (begin/end SCN e timestamp) |
| `DBA_HIST_SQLSTAT` | Estatísticas SQL por snapshot |
| `DBA_HIST_SQL_PLAN` | Planos de execução históricos |
| `DBA_HIST_ACTIVE_SESS_HISTORY` | ASH persistido (1 em 10 amostras do V$ACTIVE_SESSION_HISTORY) |
| `DBA_HIST_SYSSTAT` | Estatísticas de sistema por snapshot |
| `DBA_HIST_SYSTEM_EVENT` | Eventos de espera históricos |
| `DBA_HIST_WR_CONTROL` | Configuração do AWR (intervalo, retenção) |

### Tablespaces e armazenamento

| View | Cobre | Colunas-chave |
|---|---|---|
| `DBA_TABLESPACES` | Tablespaces definidos | `TABLESPACE_NAME`, `STATUS`, `CONTENTS`, `EXTENT_MANAGEMENT` |
| `DBA_DATA_FILES` | Datafiles dos tablespaces permanentes | `TABLESPACE_NAME`, `FILE_NAME`, `BYTES`, `AUTOEXTENSIBLE`, `MAXBYTES` |
| `DBA_TEMP_FILES` | Datafiles temporários | `TABLESPACE_NAME`, `FILE_NAME`, `BYTES` |
| `DBA_FREE_SPACE` | Espaço livre por tablespace | `TABLESPACE_NAME`, `BYTES`, `BLOCKS` |

### Privilégios e usuários

| View | Cobre |
|---|---|
| `DBA_USERS` | Usuários do banco (status, expiração, tablespace default) |
| `DBA_SYS_PRIVS` | Privilégios de sistema (CREATE TABLE, CREATE PROCEDURE…) |
| `DBA_TAB_PRIVS` | Privilégios em objetos (SELECT, INSERT, EXECUTE…) |
| `DBA_ROLE_PRIVS` | Roles atribuídas a usuários |
| `DBA_ROLES` | Roles existentes no banco |
| `SESSION_PRIVS` | Privilégios efetivos da sessão corrente |

### APEX — views do dicionário

| View | Cobre |
|---|---|
| `APEX_APPLICATIONS` | Aplicações APEX no workspace |
| `APEX_APPLICATION_PAGES` | Páginas de cada aplicação |
| `APEX_APPLICATION_PAGE_REGIONS` | Regiões por página (IR, CR, IG, Form…) |
| `APEX_APPLICATION_PAGE_IR` | Interactive Reports |
| `APEX_APPLICATION_PAGE_ITEMS` | Page items e seus tipos |
| `APEX_APPLICATION_PROCESS` | Page processes |
| `APEX_WORKSPACE_ACTIVITY_LOG` | Log de atividade do workspace |

### Descoberta — o próprio dicionário

```sql
-- Lista todas as views do dicionário disponíveis
SELECT table_name, comments
  FROM dictionary
 WHERE table_name LIKE 'DBA_HIST%'
 ORDER BY table_name;

-- Colunas de uma view específica
SELECT column_name, comments
  FROM dict_columns
 WHERE table_name = 'V$SESSION'
 ORDER BY column_id;

-- Definição interna de uma V$ view
SELECT view_definition
  FROM v$fixed_view_definition
 WHERE view_name = 'GV$SESSION';
```

---

## 4. Matriz Edição × Disponibilidade de Views

### Resumo de edições

| Edição | Abrev. | Características |
|---|---|---|
| Standard Edition 2 | SE2 | Até 2 sockets. Sem RAC nativo (SE2 HA usa cluster OS). Sem Partitioning, AWR, ASH. |
| Enterprise Edition | EE | Sem limite de sockets. Suporte a todas as opções e packs. |
| EE + Diagnostics Pack | EE+D | Habilita AWR, ASH, ADDM. Licença adicional obrigatória. |
| EE + Tuning Pack | EE+T | Habilita SQL Tuning Advisor, SQL Access Advisor, DBMS_SQLTUNE. Requer EE+D. |
| Personal Edition | PE | Desenvolvimento local, single-user. Feature set EE, sem suporte RAC. |

### Matriz de disponibilidade

| View / Feature | SE2 | EE | EE + Diagnostics | EE + Tuning |
|---|:---:|:---:|:---:|:---:|
| `V$SESSION`, `V$SQL`, `V$LOCKED_OBJECT` | ✅ | ✅ | ✅ | ✅ |
| `DBA_OBJECTS`, `DBA_TABLES`, `DBA_USERS` | ✅ | ✅ | ✅ | ✅ |
| `DBA_HIST_SNAPSHOT` | ❌ | ❌ | ✅ | ✅ |
| `DBA_HIST_SQLSTAT` | ❌ | ❌ | ✅ | ✅ |
| `DBA_HIST_ACTIVE_SESS_HISTORY` | ❌ | ❌ | ✅ | ✅ |
| `V$ACTIVE_SESSION_HISTORY` | ❌ | ❌ | ✅ | ✅ |
| `DBA_ADVISOR_*` (Advisors) | ❌ | ❌ | ❌ | ✅ |
| `DBA_SQLTUNE_*` | ❌ | ❌ | ❌ | ✅ |
| `DBA_TAB_PARTITIONS`, `DBA_IND_PARTITIONS` | ✅ (views existem) | ✅ | ✅ | ✅ |
| Particionamento real de tabelas | ❌ | ✅ (opção paga) | ✅ | ✅ |
| `V$PDBS`, `V$CONTAINERS`, `CDB_*` | ❌ até 20c / ✅ 21c (3 PDBs) | ✅ 12c+ | ✅ | ✅ |
| `DBA_GOLDENGATE_*` | ❌ | ✅ (GoldenGate licença sep.) | ✅ | ✅ |
| `DBA_POLICIES` (VPD/Label Security) | ❌ | ✅ | ✅ | ✅ |

### Como verificar o que está ativo no banco

```sql
-- Quais opções Oracle estão instaladas e habilitadas
SELECT parameter, value
  FROM v$option
 WHERE parameter IN (
   'Partitioning',
   'Real Application Clusters',
   'Oracle Label Security',
   'Automatic Storage Management',
   'OLAP',
   'Advanced Analytics',
   'Real Application Testing',
   'Data Mining'
 )
 ORDER BY parameter;

-- Verificar se Diagnostics Pack está em uso (uso ilegal sem licença)
-- Qualquer acesso a DBA_HIST_* ou V$ACTIVE_SESSION_HISTORY implica licença
SELECT feature_name, currently_used, detected_usages, first_usage_date
  FROM dba_feature_usage_statistics
 WHERE feature_name IN (
   'AWR Report',
   'Active Session History (ASH)',
   'Automatic Workload Repository',
   'SQL Tuning Advisor',
   'SQL Access Advisor'
 )
 ORDER BY feature_name;
```

**Atenção legal:** Oracle audita uso de packs via `DBA_FEATURE_USAGE_STATISTICS`. Mesmo consultar `DBA_HIST_*` sem licença do Diagnostics Pack é infração contratual.

---

## 5. Matriz Tecnologia × Views específicas

### RAC (Real Application Clusters)

RAC: múltiplas instâncias Oracle sobre um único banco de dados. Cada nó tem seu `INSTANCE_NUMBER`.

| Comportamento | Single Instance | RAC |
|---|---|---|
| `V$SESSION` | Sessões da instância local | Apenas instância local |
| `GV$SESSION` | Não relevante | **Sessões de TODAS as instâncias** |
| Coluna `INST_ID` | Ausente em V$ | Presente em GV$ (identifica o nó) |
| Kill de sessão remota | N/A | `ALTER SYSTEM KILL SESSION 'sid,serial#,@inst_id'` |

```sql
-- RAC: sessões em todas as instâncias
SELECT inst_id, sid, serial#, username, status, sql_id
  FROM gv$session
 WHERE username IS NOT NULL
   AND type = 'USER'
 ORDER BY inst_id, sid;

-- RAC: identificar instâncias ativas
SELECT instance_number, instance_name, host_name, status, version
  FROM gv$instance
 ORDER BY instance_number;

-- RAC: bloqueios cross-instance
SELECT
    l1.inst_id AS blocker_inst, l1.sid AS blocker_sid,
    l2.inst_id AS blocked_inst,  l2.sid AS blocked_sid,
    s.seconds_in_wait
  FROM gv$lock l1
  JOIN gv$lock l2 ON l1.id1 = l2.id1 AND l1.id2 = l2.id2
  JOIN gv$session s ON l2.inst_id = s.inst_id AND l2.sid = s.sid
 WHERE l1.block = 1
   AND l2.request > 0;
```

**Views exclusivas RAC:**

| View | Cobre |
|---|---|
| `GV$*` | Versão global de qualquer V$ view |
| `V$GES_*` | Global Enqueue Service (lock distribuído) |
| `V$GCS_*` | Global Cache Service (cache fusion) |
| `V$CACHE_TRANSFER` | Transferências de blocos entre instâncias |
| `GV$INSTANCE` | Estado de cada instância do cluster |

### CDB / PDB (Multitenant — 12c+)

Multitenant: um Container Database (CDB) contém múltiplos Pluggable Databases (PDBs).

| Contexto de conexão | Views disponíveis | Vê dados de |
|---|---|---|
| Conectado no CDB$ROOT | `CDB_*`, `DBA_*`, `V$PDBS` | Todos os PDBs (com CON_ID) |
| Conectado em um PDB | `DBA_*`, `ALL_*`, `USER_*` | Apenas o PDB corrente |

```sql
-- Conectado no CDB$ROOT: ver todos os PDBs
SELECT con_id, name, open_mode, restricted
  FROM v$pdbs
 ORDER BY con_id;

-- CDB_OBJECTS: objetos em todos os PDBs
SELECT con_id, owner, object_name, object_type, status
  FROM cdb_objects
 WHERE status = 'INVALID'
   AND owner NOT IN ('SYS', 'SYSTEM')
 ORDER BY con_id, owner, object_name;

-- Verificar em qual container está
SELECT sys_context('USERENV', 'CON_NAME') AS container,
       sys_context('USERENV', 'CON_ID')   AS con_id
  FROM dual;
```

**Regra CDB_* vs DBA_*:** `CDB_*` inclui coluna `CON_ID` e retorna dados de todos os PDBs. `DBA_*` retorna apenas o container corrente.

**Disponibilidade por edição:**
- 12c–20c: Multitenant é EE. SE2 pode ter apenas 1 PDB (user PDB).
- 21c+: SE2 pode ter até 3 PDBs. EE ilimitado.

### Data Guard (Active Data Guard)

| Ambiente | Views relevantes | Comportamento |
|---|---|---|
| Primary | `V$DATABASE` (`PROTECTION_MODE`, `DB_UNIQUE_NAME`) | `OPEN_MODE = 'READ WRITE'` |
| Standby físico (ADG) | `V$MANAGED_STANDBY`, `V$DATAGUARD_STATUS` | `OPEN_MODE = 'READ ONLY WITH APPLY'` |
| Standby lógico | `DBA_LOGSTDBY_*` | Aplica SQL, não redo |

```sql
-- Status do Data Guard na primary/standby
SELECT db_unique_name, database_role, open_mode,
       protection_mode, protection_level
  FROM v$database;

-- MRP (Media Recovery Process) no standby
SELECT process, status, sequence#, block#, delay_mins
  FROM v$managed_standby;

-- Log de eventos do Data Guard
SELECT dest_id, message, timestamp
  FROM v$dataguard_status
 ORDER BY timestamp DESC
 FETCH FIRST 20 ROWS ONLY;
```

**Atenção:** `V$ACTIVE_SESSION_HISTORY` em standby ativo (ADG) captura ASH do standby. Workloads read-only em ADG têm ASH próprio — diferente do primary.

### AWR (Automatic Workload Repository)

**Pré-requisito:** Enterprise Edition + Diagnostics Pack licenciado.

| View | Granularidade | Uso |
|---|---|---|
| `DBA_HIST_SNAPSHOT` | Por snapshot (default: 1h) | Período de comparação |
| `DBA_HIST_SQLSTAT` | Por SQL por snapshot | Top SQL histórico |
| `DBA_HIST_SQL_PLAN` | Por plano por snapshot | Evolução de planos |
| `DBA_HIST_ACTIVE_SESS_HISTORY` | 1 em 10 amostras ASH | ASH persistida (retenção longa) |
| `DBA_HIST_SYSSTAT` | Estatísticas de sistema | Throughput, I/O, parses |
| `DBA_HIST_SYSTEM_EVENT` | Eventos de espera | Wait profile histórico |
| `DBA_HIST_OSSTAT` | Sistema operacional | CPU, memória do host |
| `DBA_HIST_SEG_STAT` | Segmentos (tabelas/índices) | Top objetos por I/O |
| `DBA_HIST_WR_CONTROL` | Configuração do AWR | Intervalo e retenção |

```sql
-- Configuração atual do AWR
SELECT snap_interval, retention
  FROM dba_hist_wr_control;

-- Snapshots disponíveis
SELECT snap_id, begin_interval_time, end_interval_time
  FROM dba_hist_snapshot
 ORDER BY snap_id DESC
 FETCH FIRST 10 ROWS ONLY;

-- Alterar retenção (30 dias) e intervalo (60 minutos)
EXEC DBMS_WORKLOAD_REPOSITORY.modify_snapshot_settings(
       retention => 43200,   -- minutos (30 dias)
       interval  => 60);     -- minutos
```

### ASH (Active Session History)

**Pré-requisito:** Enterprise Edition + Diagnostics Pack licenciado.

| View | Período | Descrição |
|---|---|---|
| `V$ACTIVE_SESSION_HISTORY` | Última hora (~1h em memória) | Amostras a cada 1 segundo |
| `DBA_HIST_ACTIVE_SESS_HISTORY` | Retenção AWR (default 8 dias) | 1 em 10 amostras persistidas |

```sql
-- ASH em tempo real: top eventos últimos 10 minutos
SELECT event, wait_class, COUNT(*) AS amostras,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1) AS pct
  FROM v$active_session_history
 WHERE sample_time > SYSTIMESTAMP - INTERVAL '10' MINUTE
   AND session_state = 'WAITING'
 GROUP BY event, wait_class
 ORDER BY amostras DESC;

-- ASH histórico: carga por hora (última semana)
SELECT TRUNC(sample_time, 'HH') AS hora,
       COUNT(*) AS amostras,
       ROUND(COUNT(*) / 600, 2) AS avg_active_sessions
  FROM dba_hist_active_sess_history
 WHERE sample_time > SYSDATE - 7
 GROUP BY TRUNC(sample_time, 'HH')
 ORDER BY hora;
```

### Statspack (alternativa SE2 ao AWR)

SE2 não tem AWR/ASH. Statspack é a alternativa gratuita instalável manualmente.

```sql
-- Instalação (rodar como PERFSTAT ou SYS)
@?/rdbms/admin/spcreate.sql

-- Tirar snapshot manual
EXEC statspack.snap;

-- Views Statspack (prefixo STATS$)
SELECT snap_id, snap_time FROM stats$snapshot ORDER BY snap_id DESC;
SELECT sql_text, executions, disk_reads FROM stats$sql_summary
 WHERE snap_id = :snap ORDER BY disk_reads DESC;
```

---

## 6. Evolução por versão — 11g a 26ai

### Oracle 11g (11.1 / 11.2)

**Introduzido:**
- `DBA_HIST_*` completo (AWR existe desde 10g, mas 11g expande)
- `V$ACTIVE_SESSION_HISTORY` com informações RAC extras
- Compound triggers → `DBA_TRIGGERS.TRIGGER_TYPE = 'COMPOUND'`
- `DBA_RECYCLEBIN` (recycle bin desde 10g, expandido em 11g)
- `V$RESULT_CACHE_*` (SQL Result Cache)
- `DBA_PENDING_TRANSACTIONS`

**Notas de compatibilidade:**
- `V$SESSION.CON_ID` não existe em 11g (sem Multitenant)
- `DBA_TABLES.INMEMORY` não existe (sem In-Memory Column Store)

---

### Oracle 12c (12.1 / 12.2)

**Introduzido: Multitenant**
- `V$PDBS`, `V$CONTAINERS`
- `CDB_*` (versão cross-container de todas as DBA_*)
- Coluna `CON_ID` em praticamente todas as V$ views
- `DBA_CDB_RSRC_PLAN_DIRECTIVES` (Resource Manager multi-tenant)

**Introduzido: In-Memory**
- `V$IM_SEGMENTS`, `V$IM_COLUMN_LEVELS`
- `DBA_TABLES.INMEMORY`, `DBA_TABLES.INMEMORY_PRIORITY`
- `DBA_TAB_COLUMNS.INMEMORY_COMPRESSION`

**Introduzido: Outros**
- `DBA_IDENTIFIERS` (PL/Scope — análise de código)
- `DBA_STATEMENTS` (PL/Scope)
- `V$GOLDENGATE_*` (integração GoldenGate)
- `DBA_USERS.COMMON` (usuários comuns CDB vs locais)
- `DBA_OBJECTS.EDITION_NAME` (EBR)
- `DBA_EDITIONING_VIEWS`, `DBA_EDITIONING_VIEW_COLS`

---

### Oracle 18c / 19c (Long-Term Support Release)

**18c:**
- Polymorphic Table Functions → `DBA_PROCEDURES.POLYMORPHIC`
- `V$SQL.FULL_PLAN_HASH_VALUE` (novo hash mais estável)

**19c (foco da skill):**
- `DBA_GOLDENGATE_INBOUND` / `DBA_GOLDENGATE_OUTBOUND` (GoldenGate integrado)
- `V$SQL_MONITOR` melhorado (Real-Time SQL Monitoring)
- `DBA_MEMOPTIMIZE_WRITE_AREA` (Memoptimized Rowstore)
- `V$INMEMORY_AREA` expandido
- Automatic Indexing → `DBA_AUTO_INDEX_CONFIG`, `DBA_AUTO_INDEXES`

**Notas 19c importantes:**
- 19c é a versão LTS atual — máxima compatibilidade para produção
- Suporte estendido até 2027 (Premier), 2030 (Extended)
- Todas as views de 12c e 18c presentes

---

### Oracle 21c

**Introduzido:**
- `DBA_BLOCKCHAIN_TABLES` (Blockchain Tables)
- `DBA_IMMUTABLE_TABLES`
- `DBA_JSON_SCHEMA_*` (JSON Schema validation)
- `V$VECTOR_*` (preparação para AI Vector — expandido em 23ai)
- `DBA_PROPERTY_GRAPH_*` (Property Graphs SQL)
- SE2 passa a suportar até 3 PDBs → `V$PDBS` disponível em SE2 21c+

---

### Oracle 23ai

**Introduzido: AI Vector Search**
- `VECSYS.VECTOR_INDEX$` (índices vetoriais internos)
- `DBA_VECTOR_*`, `ALL_VECTOR_*`, `USER_VECTOR_*`
- `V$VECTOR_MEMORY_POOL`

**Introduzido: JSON Relational Duality**
- `DBA_JSON_DUALITY_VIEWS`, `ALL_JSON_DUALITY_VIEWS`, `USER_JSON_DUALITY_VIEWS`
- `DBA_JSON_DUALITY_VIEW_TABS`, `DBA_JSON_DUALITY_VIEW_TAB_COLS`

**Introduzido: Outros**
- `DBA_USERS.READ_ONLY` (novo modo read-only por usuário)
- `DB_DEVELOPER_ROLE` (role pré-definida) → visível em `DBA_ROLES`
- `DBA_PROPERTY_GRAPHS` expandido
- `DBA_ANNOTATIONS_USAGE` (anotações em objetos — nova feature SQL)
- `IF [NOT] EXISTS` em DDL — sem impacto em views, mas afeta `DBA_ERRORS`

---

### Oracle 26ai (atual — substitui 23ai via RU outubro 2025)

**Novidades em views (Release Updates recentes):**

| RU | Views novas |
|---|---|
| 23.26.0 | `ALL/DBA/USER_EXTERNAL_TAB_CACHES`, `ALL/DBA/USER_EXTERNAL_TAB_CACHE_LOCATIONS` |
| 23.26.1 | `ALL/DBA/USER_ASSERTIONS`, `ALL/DBA/USER_ASSERTION_DEPENDENCIES`, `ALL/DBA/USER_ASSERTION_LOCK_MATRIX`, `ALL/DBA/USER_TXEVENTQ_SUBSCRIBER_STAT` |
| 23.26.2 | `ALL/DBA/USER_END_USER_CONTEXT_DEFINITIONS` |

**Nota importante:** 23ai → 26ai não é upgrade de banco. É aplicação de Release Update. Sem re-certificação de aplicações.

---

## 7. Fontes confiáveis para atualização

### Hierarquia de confiabilidade

```
Oracle Docs (oficial)  ─── Fonte primária. Versão por versão.
         │
oracle-base.com        ─── Melhor fonte prática independente (Tim Hall). Cobre 8i→26ai.
         │
blogs.oracle.com       ─── Anúncios oficiais de features e releases.
         │
AskTOM                 ─── Tom Kyte / Connor McDonald. Respostas técnicas definitivas.
         │
My Oracle Support      ─── Bugs, patches, Notes. Requer contrato Oracle.
```

### URLs por versão — padrão de navegação

```
# Substituir {VER} por: 19 | 21 | 23 | 26

# Views estáticas (DBA_*, ALL_*, USER_*)
https://docs.oracle.com/en/database/oracle/oracle-database/{VER}/refrn/static-data-dictionary-views.html

# Views dinâmicas (V$*, GV$*)
https://docs.oracle.com/en/database/oracle/oracle-database/{VER}/refrn/dynamic-performance-views.html

# Novidades da versão (views adicionadas/alteradas por RU)
https://docs.oracle.com/en/database/oracle/oracle-database/{VER}/refrn/changes-this-release-oracle-database-reference.html

# Conceitos (hierarquia, X$, V$, GV$, CDB_*)
https://docs.oracle.com/en/database/oracle/oracle-database/{VER}/cncpt/data-dictionary-and-dynamic-performance-views.html

# Exemplo direto — 19c estático
https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/static-data-dictionary-views.html

# Exemplo direto — 26ai novidades
https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/changes-this-release-oracle-database-reference.html
```

### oracle-base.com — navegação por versão e tecnologia

```
# Artigos por versão
https://oracle-base.com/articles/{VER}/articles-{VER}
# Exemplo: https://oracle-base.com/articles/23/articles-23

# AWR
https://oracle-base.com/articles/10g/automatic-workload-repository-10g

# ASH
https://oracle-base.com/articles/10g/active-session-history

# RAC — categoria específica
https://oracle-base.com/articles/rac/articles-rac-and-grid-infrastructure

# Versões cobertas pelo menu: 8i | 9i | 10g | 11g | 12c | 18c | 19c | 21c | 23ai | 26ai
```

### AskTOM e Blog Oracle

```
# AskTOM — busca técnica
https://asktom.oracle.com

# Blog Oracle Database — anúncios de versão
https://blogs.oracle.com/database

# Anúncio oficial 26ai
https://blogs.oracle.com/database/oracle-announces-oracle-ai-database-26ai
```

### My Oracle Support — Notes úteis (requer login)

| Note ID | Assunto |
|---|---|
| 1594701.1 | Diagnostics Pack — o que requer licença |
| 1536116.1 | AWR — visão geral e configuração |
| 223117.1 | Statspack — instalação e uso (SE2) |
| 559546.1 | Diferenças SE vs EE por versão |

### Verificação local de licenciamento

```sql
-- Antes de usar DBA_HIST_* ou V$ACTIVE_SESSION_HISTORY:
-- confirmar se Diagnostics Pack está ativo
SELECT value FROM v$parameter WHERE name = 'control_management_pack_access';
-- Valores: 'DIAGNOSTIC+TUNING' | 'DIAGNOSTIC' | 'NONE'

-- Se retornar 'NONE': NÃO usar DBA_HIST_*, V$ACTIVE_SESSION_HISTORY, DBMS_SQLTUNE
-- Usar Statspack (@?/rdbms/admin/spcreate.sql) como alternativa

-- Histórico de uso de features (Oracle audita automaticamente)
SELECT feature_name, currently_used, first_usage_date, last_usage_date
  FROM dba_feature_usage_statistics
 WHERE currently_used = 'TRUE'
 ORDER BY feature_name;
```

---

## Linkagem interna

- Para sessões e locks → `assets/session_management.sql` + `references/dba-operations.md`
- Para AWR/ASH em performance → `references/performance-tuning.md`
- Para CDB/PDB em EBR → `references/ebr-editioning-views.md`
- Para APEX views (`APEX_APPLICATION_*`) → `references/apex-patterns.md`
