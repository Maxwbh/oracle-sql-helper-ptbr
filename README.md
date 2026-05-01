# oracle-sql-helper-ptbr

Skill em português brasileiro para [Claude](https://claude.ai) focada em desenvolvimento Oracle 19c, seguindo padrões **Trivadis Coding Guidelines 4.4**.

Versão atual: **v6** (abril 2026)

## O que é uma "skill"?

Skills são pacotes de instruções, templates e references que estendem o comportamento do Claude para domínios específicos. Ao instalar esta skill, o Claude passa a:

- Aplicar padrões Trivadis 4.4 automaticamente em todo código PL/SQL gerado
- Usar convenção de naming PT-BR (variáveis, tabelas, comentários) com prefixos Trivadis em inglês
- Sugerir templates prontos para os cenários mais comuns
- Reconhecer anti-patterns clássicos e propor correções

## Áreas cobertas

| Área | Reference | Templates |
|---|---|---|
| **PL/SQL** (Trivadis 4.4) | `references/plsql-trivadis-guidelines.md` | 9 templates (packages, exceptions, BULK, NOCOPY, CLOB/BLOB, Logger, triggers canônicos) |
| **APEX 24.2** | `references/apex-patterns.md` | 6 templates (Dynamic Action, pagination, Page Process, Background Process, Interactive Grid, BLOB upload/download) |
| **ORDS** | `references/ords-rest-services.md` | 2 templates (module + handler) |
| **DBA operacional** | `references/dba-operations.md` | 3 templates (Flashback, sessões travadas, recompile inválidos) |
| **Performance** | `references/performance-tuning.md` | 2 templates (EXPLAIN PLAN workflow, estratégias de índice) |
| **EBR** (zero downtime) | `references/ebr-editioning-views.md` | (conceitual — usa templates PL/SQL existentes em editions) |

## Princípios canônicos

A skill aplica 11 princípios em todo código gerado:

0. **SQL puro antes de PL/SQL** (princípio Tim Hall — SQL > PL/SQL quando possível)
1. **Bind variables sempre** (nunca concatenação de valores em SQL dinâmico)
2. **BULK em loops PL/SQL** (BULK COLLECT + FORALL)
3. **Exception com contexto** (`lc_nome_unidade` propagado em `raise_application_error`)
4. **ROLLBACK explícito** em handlers de procedures que fazem DML
5. **Logger em vez de DBMS_OUTPUT** para produção
6. **Privilégios mínimos** (separação owner/app user)
7. **Auditabilidade** (`criado_em`, `criado_por`, `atualizado_em`, `atualizado_por`, soft delete)
8. **NOCOPY para LOB/collection grande** em IN OUT/OUT
9. **Triggers não contêm regra de negócio**
10. **Quando usar trigger, sempre compound trigger**
11. **EBR para mudanças de schema com zero downtime**

## Convenção de nomes

- **Nomes em PT-BR** sempre que possível: `clientes`, `faturas`, `id_fatura`, `valor_total`, `processar_pagamento`
- **Prefixos Trivadis em inglês** (convenção do padrão): `g_`, `gc_`, `l_`, `lc_`, `p_`, `r_`, `t_`, `co_`, `e_`
- **Keywords Oracle em inglês obrigatoriamente**: `BEGIN`, `EXCEPTION`, `BULK COLLECT`, `MERGE INTO`, etc.
- **Pacotes Oracle nativos não traduzidos**: `DBMS_LOB`, `APEX_JSON`, `OWA_UTIL`, `UTL_HTTP`
- **Status values em PT-BR**: `'PENDENTE'`, `'PAGO'`, `'CANCELADO'`, `'PROCESSADO'`, `'VENCIDO'`, `'ATIVO'`

## Instalação

### Para uso pessoal no Claude.ai (Pro/Team/Enterprise)

1. Baixe o arquivo `.skill` da [aba Releases](../../releases) deste repositório (procurar `oracle-sql-helper-ptbr-v6.skill`)
2. Em Claude.ai, vá em **Settings → Capabilities → Skills**
3. Faça upload do arquivo `.skill`
4. A skill ativa automaticamente quando você menciona termos Oracle inequívocos (PL/SQL, APEX, ORDS, etc.)

### Para uso via API

A skill pode ser usada como referência para construir prompts de sistema customizados em integrações via API. O conteúdo da `SKILL.md` e referências serve como base de conhecimento.

## Estrutura do repositório

```
oracle-sql-helper-ptbr/
├── SKILL.md                              # Frontmatter + princípios + convenções
├── assets/                               # Templates SQL prontos para clonar
│   ├── README.md                         # Índice dos templates
│   ├── package_header.sql
│   ├── package_body.sql
│   ├── exception_template.sql
│   ├── bulk_processing_template.sql
│   ├── dml_alternatives_to_plsql.sql
│   ├── nocopy_for_lobs.sql
│   ├── clob_blob_operations.sql
│   ├── logger_integration.sql
│   ├── triggers_canonicos.sql
│   ├── apex_*.sql                        # 6 templates APEX
│   ├── ords_*.sql                        # 2 templates ORDS
│   ├── flashback_query.sql
│   ├── session_management.sql
│   ├── recompile_invalid_objects.sql
│   ├── explain_plan_workflow.sql
│   └── index_strategy_examples.sql
└── references/                           # Documentos de referência
    ├── plsql-trivadis-guidelines.md
    ├── apex-patterns.md
    ├── ords-rest-services.md
    ├── dba-operations.md
    ├── performance-tuning.md
    └── ebr-editioning-views.md
```

## Estatísticas

- **22 templates SQL** prontos para uso
- **6 references** com conceitos e padrões
- **11 princípios canônicos**
- ~110 KB total descompactado
- ~300 KB de conteúdo técnico em comentários e exemplos

## Histórico de versões

| Versão | Mudanças principais |
|---|---|
| **v6** (abr/2026) | +3 princípios canônicos (#9, #10, #11); +template `triggers_canonicos.sql`; +reference `ebr-editioning-views.md` (Edition-Based Redefinition para zero downtime) |
| v5 (mar/2026) | Inversão de naming inglês→PT-BR em massa; preserva prefixos Trivadis em inglês |
| v4 (mar/2026) | Auditoria com Oracle-Base/Tim Hall; princípio #0 (SQL > PL/SQL); +`dml_alternatives_to_plsql.sql`; +`nocopy_for_lobs.sql` |
| v3 (mar/2026) | Auditoria rigorosa; 5 templates novos; 7 princípios canônicos formalizados; 21 antipatterns |
| v2 (mar/2026) | Logger OraOpenSource; DBMS_ASSERT em ORDS; APEX_BACKGROUND_PROCESS para 24.2 |
| v1 (mar/2026) | Versão inicial |

## Skill complementar

Para Oracle AI Database 26ai (features 23ai/26ai como Vector Search, JSON Relational Duality, RAFT replication), use a skill paralela: [oracle-26ai-helper-ptbr](https://github.com/maxwbh/oracle-26ai-helper-ptbr).

## Padrão de referência

Esta skill é baseada em [Trivadis Coding Guidelines 4.4](https://trivadis.github.io/plsql-and-sql-coding-guidelines/v4.4/), considerado padrão de fato no ecossistema Oracle. Inclui também adoções pontuais do fork [Insum PL/SQL & SQL Coding Guidelines](https://insum-labs.github.io/plsql-and-sql-coding-guidelines/) onde agregam valor (especificamente regras G-7720 sobre triggers sem business logic e G-7730 sobre compound triggers obrigatórios).

## Filosofia

- **PT-BR como idioma principal** — comentários, nomes de domínio (clientes, faturas), status — facilita leitura por equipe brasileira
- **Trivadis 4.4 como base** — não Insum, não custom; o padrão mais adotado em comunidade Oracle
- **Tim Hall (Oracle-Base) como referência adicional** — princípio "SQL > PL/SQL" e práticas de NOCOPY
- **Templates executáveis em `assets/`** — não snippets em markdown, mas SQL real que roda em Oracle 19c+
- **Anti-patterns documentados antes×depois** — código errado e corrigido lado a lado

## Limitações

- **Foco em Oracle 19c** — features 23ai/26ai estão em skill separada
- **APEX 24.2** — versões anteriores podem não ter todas as APIs mencionadas
- **Standard Edition vs Enterprise Edition** — algumas features (Flashback, Partitioning) requerem EE
- **Português brasileiro** — não é português europeu

## Contribuindo

Issues e PRs bem-vindos. Se identificar:
- Anti-patterns não cobertos
- APIs APEX/ORDS faltantes
- Erros nos templates
- Sugestões de naming PT-BR

abra issue descrevendo o caso de uso real.

## Licença

Apache License 2.0 — veja [LICENSE](LICENSE).

Esta skill é construída sobre o trabalho de:
- [Trivadis](https://trivadis.github.io/plsql-and-sql-coding-guidelines/) (Roger Troller, Philipp Salvisberg, e demais contribuidores) — padrão original
- [Insum Solutions](https://insum-labs.github.io/plsql-and-sql-coding-guidelines/) (Rich Soule e equipe) — fork com refinamentos
- [Oracle-Base](https://oracle-base.com/) (Tim Hall) — princípios e padrões práticos
- [OraOpenSource Logger](https://github.com/OraOpenSource/Logger) — framework de logging

## Autor

**Maxwell da Silva Oliveira** — Senior Oracle Developer

- Empresa: M&S do Brasil
- Sete Lagoas, Minas Gerais, Brasil
- E-mail: [maxwbh@gmail.com](mailto:maxwbh@gmail.com)
- GitHub: [@maxwbh](https://github.com/maxwbh)

Construída com auxílio de Claude (Anthropic) através de processo iterativo de auditoria contra documentação oficial Oracle, Oracle-Base, e padrões Trivadis/Insum.
