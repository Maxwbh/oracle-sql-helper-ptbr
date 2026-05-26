---
name: oracle-plsql-ptbr
description: PL/SQL Oracle 19c — packages, procedures, functions, types, cursores, LOBs e EBR. ATIVE em BULK COLLECT, FORALL, NOCOPY, EXECUTE IMMEDIATE, MERGE INTO, compound trigger, editioning view, cross-edition trigger, CLOB/BLOB, Logger, exception handler, DML alternatives. Frases ambíguas com contexto PL/SQL — "criar package", "refatorar procedure", "processar LOB", "zero downtime deploy", "loop tá lento", "trigger de auditoria". NAO ATIVE em páginas APEX, endpoints ORDS, DBA operacional (sessões/locks/tablespace), tuning de queries (explain plan/AWR/ASH). Aplica naming Trivadis automaticamente — para revisão explícita do padrão use oracle-trivadis-ptbr. Templates em assets/.
metadata:
  version: "2.0.0"
  author: "Maxwell da Silva Oliveira"
  contact: "contato@msbrasil.inf.br"
  git: "https://github.com/maxwbh"
  organization: "M&S do Brasil LTDA"
  site: "https://msbrasil.inf.br"
  changelog: |
    v2.0.0: Breaking — divisão de oracle-sql-helper-ptbr v1.6.0 em 6 skills especializadas. Esta skill cobre PL/SQL, packages, procedures, functions, LOBs, EBR, triggers. Instale as 6 irmãs para cobertura completa da stack Oracle.
    v1.6.0: (oracle-sql-helper-ptbr) Novo reference ords-data-dictionary-ptbr.md — USER_ORDS_*/DBA_ORDS_*, depreciacao OAUTH/ORDS_SECURITY, evolucao 18.x-25.x.
    v1.5.0: (oracle-sql-helper-ptbr) Novo reference apex-data-dictionary-ptbr.md — hierarquia APEX_APPLICATION_*/APEX_APPL_*/APEX_WORKSPACE_*, versoes 19-26.1.
    v1.4.0: (oracle-sql-helper-ptbr) Remocao de clientes reais. Autoria M&S do Brasil LTDA.
    v1.3.0: (oracle-sql-helper-ptbr) Novo reference data-dictionary-ptbr.md — hierarquia Oracle, matriz edicao x tecnologia, evolucao 11g-26ai.
  tags:
    - "oracle"
    - "plsql"
    - "database"
    - "packages"
    - "triggers"
    - "lob"
    - "ebr"
    - "logger"
    - "oracle-19c"
  category: "database"
  language: "pt-BR"
  icon: "🗄️"
---

# oracle-plsql-ptbr — v2.0.0

PL/SQL Oracle 19c seguindo Trivadis Guidelines 4.4. Foco em código correto, seguro e performático.

**Desenvolvido por:** Maxwell da Silva Oliveira — [M&S do Brasil LTDA](https://msbrasil.inf.br)

## Áreas cobertas

| Área | Reference | Assets |
|---|---|---|
| **EBR (zero downtime)** | `references/ebr-editioning-views.md` | (conceitual) |
| **PL/SQL** | `references/` → **oracle-trivadis-ptbr** | `package_header.sql`, `package_body.sql`, `exception_template.sql`, `bulk_processing_template.sql`, `dml_alternatives_to_plsql.sql`, `nocopy_for_lobs.sql`, `clob_blob_operations.sql`, `logger_integration.sql`, `triggers_canonicos.sql` |

> **Referência cruzada de nomenclatura:** padrão Trivadis 4.4 completo (prefixos, estrutura, naming PT-BR) está em **oracle-trivadis-ptbr**. Esta skill aplica as convenções automaticamente — carregue `oracle-trivadis-ptbr` quando o foco for revisão explícita de padrão.

## Quando ativar

- Criação ou refatoração de packages, procedures, functions, types
- BULK COLLECT + FORALL (loop PL/SQL em volume)
- NOCOPY para BLOB/CLOB > 100KB ou collections grandes em IN OUT
- EXECUTE IMMEDIATE com bind variables (SQL dinâmico)
- MERGE INTO como substituto de loop SELECT/INSERT/UPDATE
- LOBs: leitura em chunks, Base64, SHA-256, DBMS_LOB
- Compound trigger (auditoria, surrogate keys, cross-edition)
- EBR: editioning views, cross-edition triggers, deploy zero downtime
- Logger (OraOpenSource): log_error, log_warn, log_info, log_permanent
- Qualquer menção a AUTONOMOUS_TRANSACTION, PRAGMA, DBMS_ERRLOG

**Não usar** para: APEX pages/regions/items, ORDS endpoints/modules, DBA ops (sessão/lock/tablespace), tuning de queries.

## Princípios canônicos

0. **SQL puro antes de PL/SQL.** Se MERGE, INSERT SELECT ou UPDATE com CASE resolve — use. PL/SQL só quando há lógica de negócio por linha, chamadas externas ou coordenação complexa.
1. **Bind variables sempre.** Em EXECUTE IMMEDIATE use `USING`. Identificadores dinâmicos → `DBMS_ASSERT.simple_sql_name`.
2. **Bulk em loops.** `BULK COLLECT` + `FORALL`. Com `LIMIT` para volumes > 100k. `DBMS_ERRLOG` quando cabe DML único.
3. **Exception com contexto.** `lc_nome_unidade CONSTANT VARCHAR2(60)` em toda procedure pública. Re-raise via `raise_application_error`.
4. **ROLLBACK explícito** antes do re-raise em handlers com DML. Caller decide o commit.
5. **Logger em vez de DBMS_OUTPUT** em produção.
6. **Privilégios mínimos.** Schema owner faz DDL; app user faz DML.
7. **Auditabilidade.** `criado_em`, `criado_por`, `atualizado_em`, `atualizado_por` em tabelas de domínio.
8. **NOCOPY para LOB/collection grande** em IN OUT/OUT.
9. **Triggers não contêm regra de negócio.** Auditoria, surrogate key, cross-edition EBR.
10. **Sempre compound trigger** quando trigger é necessário.
11. **EBR para zero downtime.** Editioning views + editions + cross-edition triggers.

## Fluxo de uso

**Criar código:** SQL puro resolve? → `dml_alternatives_to_plsql.sql`. Não → clone template da área → adapte naming Trivadis → use Logger.

**Revisar código:** Princípio #0 primeiro. Depois antipatterns: concatenação em SQL dinâmico, loop linha-a-linha, `WHEN OTHERS THEN NULL`, `DBMS_OUTPUT` em produção, falta NOCOPY em LOB IN OUT. Para naming explícito → **oracle-trivadis-ptbr**.

## Referências cruzadas

| Precisa de | Skill |
|---|---|
| Naming, prefixos, checklist Trivadis | **oracle-trivadis-ptbr** |
| APEX page process, dynamic action, IG | **oracle-apex-ptbr** |
| ORDS handler, módulo REST | **oracle-ords-ptbr** |
| Sessão, lock, flashback, tablespace | **oracle-dba-ptbr** |
| Explain plan, AWR, index, tuning | **oracle-tuning-ptbr** |
