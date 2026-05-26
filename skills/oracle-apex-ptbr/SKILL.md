---
name: oracle-apex-ptbr
description: Oracle APEX 24.2 — desenvolvimento e dicionário de metadados. ATIVE em Dynamic Actions, Interactive Report, Interactive Grid, Classic Report, Page Process, AJAX Callback, Validations, Authorization Schemes, pagination, LOV, APEX_APPLICATION_*, APEX_APPLICATION_PAGE_*, APEX_WORKSPACE_*, APEX_APPL_*, Workflows, Tasks, AI configs, ACL, JSON Sources, APEX_ACTIVITY_LOG. Frases — "página APEX", "region IR", "IG editável", "process no submit", "qual view APEX usar", "auditar paginação APEX". NAO ATIVE em PL/SQL puro, ORDS endpoints, DBA operacional. Para naming use oracle-trivadis-ptbr. Templates em assets/.
metadata:
  version: "2.0.0"
  author: "Maxwell da Silva Oliveira"
  contact: "contato@msbrasil.inf.br"
  git: "https://github.com/maxwbh"
  organization: "M&S do Brasil LTDA"
  site: "https://msbrasil.inf.br"
  changelog: |
    v2.0.0: Breaking — divisão de oracle-sql-helper-ptbr v1.6.0 em 6 skills especializadas. Esta skill cobre APEX 24.2 development e APEX Data Dictionary. Instale as 6 irmãs para cobertura completa da stack Oracle.
    v1.6.0: (oracle-sql-helper-ptbr) Novo reference ords-data-dictionary-ptbr.md — USER_ORDS_*/DBA_ORDS_*, depreciacao OAUTH/ORDS_SECURITY, evolucao 18.x-25.x.
    v1.5.0: (oracle-sql-helper-ptbr) Novo reference apex-data-dictionary-ptbr.md — hierarquia APEX_APPLICATION_*/APEX_APPL_*/APEX_WORKSPACE_*, versoes 19-26.1.
    v1.4.0: (oracle-sql-helper-ptbr) Remocao de clientes reais. Autoria M&S do Brasil LTDA.
    v1.3.0: (oracle-sql-helper-ptbr) Novo reference data-dictionary-ptbr.md — hierarquia Oracle, matriz edicao x tecnologia, evolucao 11g-26ai.
  tags:
    - "oracle"
    - "apex"
    - "apex-24"
    - "interactive-report"
    - "interactive-grid"
    - "workflow"
    - "javascript"
  category: "development"
  language: "pt-BR"
  icon: "⚡"
---

# oracle-apex-ptbr — v2.0.0

Oracle APEX 24.2 — padrões de desenvolvimento e dicionário completo de views de metadados.

**Desenvolvido por:** Maxwell da Silva Oliveira — [M&S do Brasil LTDA](https://msbrasil.inf.br)

## Áreas cobertas

| Área | Reference | Assets |
|---|---|---|
| **Padrões APEX 24.2** | `references/apex-patterns.md` | `apex_dynamic_action.sql`, `apex_pagination_pattern.sql`, `apex_pl_sql_process.sql`, `apex_long_running_job.sql`, `apex_interactive_grid.sql`, `apex_blob_upload_download.sql` |
| **APEX Data Dictionary** | `references/apex-data-dictionary-ptbr.md` | (queries embutidas no reference) |

## Quando ativar

- Qualquer menção a APEX, App Builder, página, região, item, process, validation
- Dynamic Actions (event, true/false action, affected elements)
- Interactive Report: pagination, colunas, filtros, `APEX_APPLICATION_PAGE_IR`
- Interactive Grid: edição, save process, `APEX_APPLICATION_PAGE_IG`
- Page Process e AJAX Callback (apex.server.process)
- Authorization Scheme e Authentication Scheme
- Paginação de reports (Row Ranges, "of Z", cache de região)
- APEX_APPLICATION_*, APEX_WORKSPACE_*, APEX_APPL_*, APEX_ACTIVITY_LOG
- Workflows, Tasks, AI configs (24.1+), JSON Sources (24.2+)
- `APEX_BACKGROUND_PROCESS`, jobs longos (> 30s)
- BLOB upload/download via APEX (html2pdf, armazenamento)

**Não usar** para: PL/SQL puro sem APEX, ORDS endpoints, DBA operacional.

## Princípios canônicos

- **Page Process vs Dynamic Action:** lógica server-side com transação → Page Process. Reação client-side leve → Dynamic Action.
- **Pagination correta:** `Row Ranges X to Y of Z` em IR. Classic Report: `Rows X to Y`.
- **Items sensíveis:** `Value Protected: Yes` sempre em Hidden PKs.
- **Exception em process APEX:** use `APEX_ERROR.add_error` — nunca `raise_application_error` direto sem handler.
- **APEX não comita:** processos PL/SQL dentro de APEX não fazem COMMIT — o framework gerencia.
- **APEX_DICTIONARY:** ponto de entrada para descoberta de qualquer view de metadados APEX.

## Referências cruzadas

| Precisa de | Skill |
|---|---|
| PL/SQL dentro de processes (packages, bulk) | **oracle-plsql-ptbr** |
| Naming e prefixos Trivadis no código | **oracle-trivadis-ptbr** |
| Endpoints REST consumidos pelo APEX | **oracle-ords-ptbr** |
| Sessão APEX no banco, locks | **oracle-dba-ptbr** |
| Query lenta em report APEX | **oracle-tuning-ptbr** |
