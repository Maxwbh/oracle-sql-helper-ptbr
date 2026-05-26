---
name: oracle-dba-ptbr
description: DBA operacional Oracle 19c e dicionário (V$, GV$, DBA_*, CDB_*, DBA_HIST_*). ATIVE em sessão travada, bloqueio, kill session, RAC (GV$SESSION, INST_ID), flashback query/table, recompile objetos inválidos, tablespace cheio, espaço em disco, DBMS_STATS, AWR histórico, ASH (DBA_HIST_ACTIVE_SESS_HISTORY), Diagnostics Pack, SE2 vs EE, Data Guard, CDB/PDB, V$PDBS. Frases — "quem tá bloqueando", "recuperar dado deletado", "objetos inválidos", "qual view DBA usar", "tablespace cheio", "edição do banco", "Diagnostics Pack licença". NAO ATIVE em código PL/SQL novo, APEX, ORDS, explain plan/tuning.
metadata:
  version: "2.0.0"
  author: "Maxwell da Silva Oliveira"
  contact: "contato@msbrasil.inf.br"
  git: "https://github.com/maxwbh"
  organization: "M&S do Brasil LTDA"
  site: "https://msbrasil.inf.br"
  changelog: |
    v2.0.0: Breaking — divisão de oracle-sql-helper-ptbr v1.6.0 em 6 skills especializadas. Esta skill cobre DBA operacional e Oracle Data Dictionary (V$, GV$, DBA_*, CDB_*). Instale as 6 irmãs para cobertura completa da stack Oracle.
    v1.6.0: (oracle-sql-helper-ptbr) Novo reference ords-data-dictionary-ptbr.md — USER_ORDS_*/DBA_ORDS_*, depreciacao OAUTH/ORDS_SECURITY, evolucao 18.x-25.x.
    v1.5.0: (oracle-sql-helper-ptbr) Novo reference apex-data-dictionary-ptbr.md — hierarquia APEX_APPLICATION_*/APEX_APPL_*/APEX_WORKSPACE_*, versoes 19-26.1.
    v1.4.0: (oracle-sql-helper-ptbr) Remocao de clientes reais. Autoria M&S do Brasil LTDA.
    v1.3.0: (oracle-sql-helper-ptbr) Novo reference data-dictionary-ptbr.md — hierarquia Oracle, matriz edicao x tecnologia, evolucao 11g-26ai.
  tags:
    - "oracle"
    - "dba"
    - "performance"
    - "awr"
    - "ash"
    - "rac"
    - "flashback"
    - "data-dictionary"
  category: "database"
  language: "pt-BR"
  icon: "🛡️"
---

# oracle-dba-ptbr — v2.0.0

DBA operacional Oracle 19c e dicionário completo de views (estáticas e dinâmicas).

**Desenvolvido por:** Maxwell da Silva Oliveira — [M&S do Brasil LTDA](https://msbrasil.inf.br)

## Áreas cobertas

| Área | Reference | Assets |
|---|---|---|
| **DBA operacional** | `references/dba-operations.md` | `session_management.sql`, `flashback_query.sql`, `recompile_invalid_objects.sql` |
| **Oracle Data Dictionary** | `references/data-dictionary-ptbr.md` | (queries embutidas no reference) |

## Quando ativar

- Sessões travadas, bloqueios, `blocking_session`, kill session
- RAC: `GV$SESSION`, `GV$LOCK`, `INST_ID`, kill cross-instance
- Flashback query (`AS OF TIMESTAMP`, `AS OF SCN`) e `FLASHBACK TABLE`
- Objetos inválidos: listar, recompilar, dependências
- Tablespace: uso, datafiles, free space, autoextend
- Estatísticas: `DBMS_STATS`, `last_analyzed`, locked stats
- AWR histórico: `DBA_HIST_*` — **verifica licença Diagnostics Pack primeiro**
- ASH: `V$ACTIVE_SESSION_HISTORY`, `DBA_HIST_ACTIVE_SESS_HISTORY`
- Dúvidas sobre edição: SE2 vs EE, `V$OPTION`
- CDB/PDB: `V$PDBS`, `V$CONTAINERS`, `CDB_*`, `CON_ID`
- Data Guard: `V$DATAGUARD_STATUS`, `V$MANAGED_STANDBY`
- Hierarquia de views: `X$`, `V$`, `GV$`, `DBA_*`, `ALL_*`, `USER_*`

**Não usar** para: código PL/SQL novo, APEX, ORDS, explain plan/index tuning.

## Princípios canônicos

- **Privilégio mínimo:** app user faz DML; schema owner faz DDL; DBA só quando necessário.
- **KILL com cautela:** verifica transação ativa antes — rollback pode demorar horas.
- **`V$OPTION` antes de `DBA_HIST_*`:** confirma Diagnostics Pack ativo (`control_management_pack_access`). Uso sem licença é infração contratual.
- **RAC:** `V$SESSION` = instância local; `GV$SESSION` = todas. Sempre inclui `INST_ID` no kill em RAC.
- **Flashback:** respeita `undo_retention`. Para períodos longos: Flashback Database (configuração prévia).
- **CDB:** `CDB_*` + `CON_ID` para visão cross-container. `DBA_*` = container corrente.

## Referências cruzadas

| Precisa de | Skill |
|---|---|
| Código PL/SQL, packages, procedures | **oracle-plsql-ptbr** |
| Explain plan, AWR em tempo real, indexes | **oracle-tuning-ptbr** |
| APEX views (APEX_WORKSPACE_ACTIVITY_LOG) | **oracle-apex-ptbr** |
| ORDS views (USER_ORDS_*, DBA_ORDS_*) | **oracle-ords-ptbr** |
| Naming Trivadis em scripts DBA | **oracle-trivadis-ptbr** |
