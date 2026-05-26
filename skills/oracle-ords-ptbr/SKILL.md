---
name: oracle-ords-ptbr
description: Oracle ORDS — REST services e dicionário USER_ORDS_*/DBA_ORDS_*. ATIVE em define_module, define_template, define_handler, AutoREST, OAuth, ORDS_SECURITY, ORDS_SECURITY_ADMIN, JWT, PAR via ORDS_PAR, privilege, role ORDS, ORDS_EXPORT, USER_ORDS_MODULES, USER_ORDS_HANDLERS, USER_ORDS_SCHEMAS, DBA_ORDS_*, source_type_collection_query, CORS, versionamento de API, depreciação OAUTH package. Frases — "criar endpoint REST", "módulo ORDS", "autenticar API", "inventário de handlers ORDS", "OAUTH deprecated". NAO ATIVE em APEX pages, PL/SQL puro, DBA operacional. Templates em assets/.
metadata:
  version: "2.0.0"
  author: "Maxwell da Silva Oliveira"
  contact: "contato@msbrasil.inf.br"
  git: "https://github.com/maxwbh"
  organization: "M&S do Brasil LTDA"
  site: "https://msbrasil.inf.br"
  changelog: |
    v2.0.0: Breaking — divisão de oracle-sql-helper-ptbr v1.6.0 em 6 skills especializadas. Esta skill cobre ORDS REST services e ORDS Data Dictionary (USER_ORDS_*/DBA_ORDS_*). Instale as 6 irmãs para cobertura completa da stack Oracle.
    v1.6.0: (oracle-sql-helper-ptbr) Novo reference ords-data-dictionary-ptbr.md — USER_ORDS_*/DBA_ORDS_*, depreciacao OAUTH/ORDS_SECURITY, evolucao 18.x-25.x.
    v1.5.0: (oracle-sql-helper-ptbr) Novo reference apex-data-dictionary-ptbr.md — hierarquia APEX_APPLICATION_*/APEX_APPL_*/APEX_WORKSPACE_*, versoes 19-26.1.
    v1.4.0: (oracle-sql-helper-ptbr) Remocao de clientes reais. Autoria M&S do Brasil LTDA.
    v1.3.0: (oracle-sql-helper-ptbr) Novo reference data-dictionary-ptbr.md — hierarquia Oracle, matriz edicao x tecnologia, evolucao 11g-26ai.
  tags:
    - "oracle"
    - "ords"
    - "rest-api"
    - "oauth"
    - "autorest"
    - "jwt"
    - "openapi"
  category: "development"
  language: "pt-BR"
  icon: "🌐"
---

# oracle-ords-ptbr — v2.0.0

Oracle REST Data Services — padrões de desenvolvimento e dicionário completo de views de metadados.

**Desenvolvido por:** Maxwell da Silva Oliveira — [M&S do Brasil LTDA](https://msbrasil.inf.br)

## Áreas cobertas

| Área | Reference | Assets |
|---|---|---|
| **REST services** | `references/ords-rest-services.md` | `ords_module.sql`, `ords_handler.sql` |
| **ORDS Data Dictionary** | `references/ords-data-dictionary-ptbr.md` | (queries embutidas no reference) |

## Quando ativar

- `ORDS.define_module`, `ORDS.define_template`, `ORDS.define_handler`
- `ORDS.enable_schema`, `ORDS.enable_object` (AutoREST)
- `ORDS_SECURITY.create_client`, `ORDS_SECURITY_ADMIN.*` (24.4+)
- `OAUTH.*` ou `OAUTH_ADMIN.*` → alertar depreciação (removidos em ORDS 25.3)
- `ORDS_PAR` — Pre-Authenticated Requests (24.4+)
- `ORDS_EXPORT.export_schema` — backup/deploy de configuração
- `USER_ORDS_MODULES`, `USER_ORDS_HANDLERS`, `USER_ORDS_SCHEMAS`
- `DBA_ORDS_*` (requer `ORDS_ADMINISTRATOR`) — ORDS 24.4+
- Source types: `collection/query`, `collection/item`, `plsql/block`, `mle/javascript`
- CORS, códigos HTTP REST, versionamento de API, OAuth 2.0
- JWT Profiles, `USER_ORDS_JWT_PROFILE`

**Não usar** para: APEX pages/regions, PL/SQL puro sem REST, DBA ops.

## Princípios canônicos

- **Hierarquia ORDS:** Schema → Module → Template → Handler → Parameter.
- **Bind variables sempre:** path params (`:id`), query string (`:status`) são bind automático. SQL dinâmico → `DBMS_ASSERT`.
- **Source type correto:** lista paginada → `collection/query`. Um item → `collection/item`. Lógica complexa → `plsql/block`. BLOB → `media/blob`.
- **Autenticação obrigatória** em qualquer endpoint que acesse dado sensível — `ORDS.define_privilege` + role.
- **OAUTH depreciado em 24.4:** migrar para `ORDS_SECURITY` / `ORDS_SECURITY_ADMIN`. Removido em ORDS 25.3.
- **Versionamento no path:** `/recurso/v1/` e `/recurso/v2/` — não via query string.
- **DBA_ORDS_*:** visão cross-schema (ORDS 24.4+). Requer role `ORDS_ADMINISTRATOR`.
- **ORDS_EXPORT:** use para CI/CD e backup de configuração.

## Referências cruzadas

| Precisa de | Skill |
|---|---|
| PL/SQL dentro de handler (packages, lógica) | **oracle-plsql-ptbr** |
| Naming e prefixos Trivadis no código | **oracle-trivadis-ptbr** |
| APEX consumindo endpoints ORDS | **oracle-apex-ptbr** |
| V$SESSION, locks, DBA operacional | **oracle-dba-ptbr** |
| Query lenta no handler | **oracle-tuning-ptbr** |
