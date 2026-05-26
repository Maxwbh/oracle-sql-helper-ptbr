---
name: oracle-tuning-ptbr
description: Performance tuning Oracle 19c — explain plan, AWR em tempo real, ASH, indexes, hints, bind variables, cursor sharing, DBMS_STATS, V$SQL, V$SQLAREA, V$SESSION_WAIT. ATIVE em query lenta, full scan indesejado, hard parse alto, index strategy, plano de execução ruim, estatísticas desatualizadas, cardinality errada, AWR snapshot, ASH amostragem. Frases — "query está lenta", "qual index criar", "melhorar explain plan", "muitos hard parse", "cursor sharing", "optimizer hint", "runstats". NAO ATIVE em DBA operacional (sessões/locks/tablespace), código PL/SQL novo, APEX, ORDS. Templates em assets/.
metadata:
  version: "2.0.0"
  author: "Maxwell da Silva Oliveira"
  contact: "contato@msbrasil.inf.br"
  git: "https://github.com/maxwbh"
  organization: "M&S do Brasil LTDA"
  site: "https://msbrasil.inf.br"
  changelog: |
    v2.0.0: Breaking — divisão de oracle-sql-helper-ptbr v1.6.0 em 6 skills especializadas. Esta skill cobre Performance tuning — explain plan, AWR, ASH, indexes. Instale as 6 irmãs para cobertura completa da stack Oracle.
    v1.6.0: (oracle-sql-helper-ptbr) Novo reference ords-data-dictionary-ptbr.md — USER_ORDS_*/DBA_ORDS_*, depreciacao OAUTH/ORDS_SECURITY, evolucao 18.x-25.x.
    v1.5.0: (oracle-sql-helper-ptbr) Novo reference apex-data-dictionary-ptbr.md — hierarquia APEX_APPLICATION_*/APEX_APPL_*/APEX_WORKSPACE_*, versoes 19-26.1.
    v1.4.0: (oracle-sql-helper-ptbr) Remocao de clientes reais. Autoria M&S do Brasil LTDA.
    v1.3.0: (oracle-sql-helper-ptbr) Novo reference data-dictionary-ptbr.md — hierarquia Oracle, matriz edicao x tecnologia, evolucao 11g-26ai.
  tags:
    - "oracle"
    - "tuning"
    - "performance"
    - "explain-plan"
    - "awr"
    - "ash"
    - "indexes"
    - "statistics"
  category: "database"
  language: "pt-BR"
  icon: "🚀"
---

# oracle-tuning-ptbr — v2.0.0

Performance tuning Oracle 19c — análise de planos de execução, índices, AWR e ASH em tempo real.

**Desenvolvido por:** Maxwell da Silva Oliveira — [M&S do Brasil LTDA](https://msbrasil.inf.br)

## Áreas cobertas

| Área | Reference | Assets |
|---|---|---|
| **Performance** | `references/performance-tuning.md` | `explain_plan_workflow.sql`, `index_strategy_examples.sql` |

## Quando ativar

- Query lenta — análise de explain plan, `AUTOTRACE`, `DBMS_XPLAN.DISPLAY_CURSOR`
- Índices: `B-Tree`, `Bitmap`, `Function-Based`, `Composite`, `Invisible`
- `V$SQL`, `V$SQLAREA` — top SQL por `ELAPSED_TIME`, `CPU_TIME`, `BUFFER_GETS`
- `V$SESSION_WAIT`, `V$SYSTEM_EVENT` — wait event analysis
- Hard parse alto: bind variables ausentes, cursor sharing
- Cardinality errada: `DBMS_STATS`, `METHOD_OPT`, `HISTOGRAM`
- AWR em tempo real: `DBA_HIST_SQLSTAT`, `DBA_HIST_SYSTEM_EVENT` (requer Diagnostics Pack)
- ASH: `V$ACTIVE_SESSION_HISTORY`, `DBA_HIST_ACTIVE_SESS_HISTORY`
- Hints: `/*+ APPEND */`, `/*+ INDEX */`, `/*+ PARALLEL */`, `/*+ FIRST_ROWS */`
- `MERGE` vs loop, `BULK COLLECT` para I/O pesado
- Estatísticas: `GATHER_SCHEMA_STATS`, `GATHER_TABLE_STATS`, lock stats

**Não usar** para: DBA ops (sessão/lock/kill), código PL/SQL novo, APEX, ORDS.

## Princípios canônicos

- **Medir antes de otimizar.** Baseline com `SET TIMING ON` + `AUTOTRACE`. Sem medição, otimização é placebo.
- **Bind variables primeiro.** Hard parse elevado em `V$SQLAREA` resolve antes de qualquer tuning de index.
- **Index ≠ sempre melhor.** Full scan em tabela pequena ou query retornando > 10% das linhas geralmente vence B-Tree.
- **AWR requer licença.** `DBA_HIST_*` → Diagnostics Pack obrigatório. Checar `control_management_pack_access`.
- **Histogram nas colunas com skew.** Sem histogram, optimizer usa densidade plana → plano errado em distribuição assimétrica.
- **CREATE INDEX ONLINE** em produção — sem `ONLINE`, bloqueia DML.

## Referências cruzadas

| Precisa de | Skill |
|---|---|
| PL/SQL com BULK COLLECT, loop otimizado | **oracle-plsql-ptbr** |
| AWR histórico, sessões, DBA operacional | **oracle-dba-ptbr** |
| Query lenta em report APEX | **oracle-apex-ptbr** |
| Naming Trivadis em scripts de tuning | **oracle-trivadis-ptbr** |
