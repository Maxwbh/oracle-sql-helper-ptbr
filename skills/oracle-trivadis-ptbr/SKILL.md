---
name: oracle-trivadis-ptbr
description: Trivadis PL/SQL Guidelines 4.4 — nomenclatura, estrutura de código e revisão. ATIVE em revisar código Oracle com padrão Trivadis, validar prefixos (g_, gc_, l_, lc_, p_, r_, t_, co_, e_), naming PT-BR em variáveis/tabelas/colunas, checklist antes de deploy/GMUD, "esse código segue Trivadis?", "qual prefixo usar?", "como nomear essa variável?", "revisa esse package". NÃO ATIVE em geração de código (use oracle-plsql-ptbr), APEX development, ORDS endpoints, DBA operacional, tuning. As demais oracle-*-ptbr aplicam Trivadis automaticamente — esta skill foca em consultas e revisões explícitas do padrão.
metadata:
  version: "2.0.0"
  author: "Maxwell da Silva Oliveira"
  contact: "contato@msbrasil.inf.br"
  git: "https://github.com/maxwbh"
  organization: "M&S do Brasil LTDA"
  site: "https://msbrasil.inf.br"
  changelog: |
    v2.0.0: Breaking — divisão de oracle-sql-helper-ptbr v1.6.0 em 6 skills especializadas. Esta skill cobre Trivadis Guidelines 4.4 — nomenclatura, estrutura e revisão de código. Instale as 6 irmãs para cobertura completa da stack Oracle.
    v1.6.0: (oracle-sql-helper-ptbr) Novo reference ords-data-dictionary-ptbr.md — USER_ORDS_*/DBA_ORDS_*, depreciacao OAUTH/ORDS_SECURITY, evolucao 18.x-25.x.
    v1.5.0: (oracle-sql-helper-ptbr) Novo reference apex-data-dictionary-ptbr.md — hierarquia APEX_APPLICATION_*/APEX_APPL_*/APEX_WORKSPACE_*, versoes 19-26.1.
    v1.4.0: (oracle-sql-helper-ptbr) Remocao de clientes reais. Autoria M&S do Brasil LTDA.
    v1.3.0: (oracle-sql-helper-ptbr) Novo reference data-dictionary-ptbr.md — hierarquia Oracle, matriz edicao x tecnologia, evolucao 11g-26ai.
  tags:
    - "oracle"
    - "trivadis"
    - "coding-standards"
    - "naming-conventions"
    - "plsql"
    - "code-review"
  category: "development"
  language: "pt-BR"
  icon: "📐"
---

# oracle-trivadis-ptbr — v2.0.0

Trivadis PL/SQL Guidelines 4.4 — padrão de nomenclatura, estrutura de código e checklist de revisão.

**Desenvolvido por:** Maxwell da Silva Oliveira — [M&S do Brasil LTDA](https://msbrasil.inf.br)

## Áreas cobertas

| Área | Reference |
|---|---|
| **Trivadis Guidelines 4.4** | `references/plsql-trivadis-guidelines.md` |

> **Referência cruzada:** Esta skill documenta o padrão. As skills `oracle-plsql-ptbr`, `oracle-apex-ptbr`, `oracle-ords-ptbr`, `oracle-dba-ptbr` e `oracle-tuning-ptbr` aplicam Trivadis automaticamente em todo código gerado.

## Quando ativar

- "Esse código segue Trivadis?" — revisão explícita de padrão
- "Qual prefixo usar para essa variável/cursor/constante?"
- "Como nomear essa tabela/coluna/package em PT-BR?"
- Checklist pré-deploy / pré-GMUD: validar naming antes de subir para produção
- Auditoria de código legado: identificar desvios do padrão
- Dúvidas sobre convenções: exceções locais vs globais, packages nativos Oracle em inglês, status values em PT-BR

**Não usar** para: geração de código PL/SQL (→ oracle-plsql-ptbr), APEX, ORDS, DBA ops, tuning.

## Prefixos canônicos Trivadis

| Prefixo | Uso | Exemplo |
|---|---|---|
| `g_` | Variável global (package) | `g_ultima_execucao` |
| `gc_` | Constante global (package) | `gc_nome_pacote` |
| `l_` | Variável local | `l_total_pago` |
| `lc_` | Constante local | `lc_nome_unidade` |
| `p_` | Parâmetro | `p_id_fatura` |
| `r_` | Record | `r_fatura` |
| `t_` | Type (collection, record) | `t_lista_ids` |
| `co_` | Cursor | `co_faturas_pendentes` |
| `e_` | Exception user-defined | `e_estado_invalido` |

## Checklist de revisão — o que verificar

1. **Naming:** variáveis, procedures, functions, tabelas e colunas em PT-BR (exceto keywords Oracle, pacotes nativos, prefixos Trivadis)
2. **Prefixos Trivadis:** `g_`, `gc_`, `l_`, `lc_`, `p_`, `r_`, `t_`, `co_`, `e_` aplicados corretamente
3. **Keywords em inglês:** `BEGIN`, `END`, `EXCEPTION`, `BULK COLLECT`, `FORALL`, `MERGE INTO` nunca traduzidos
4. **Pacotes nativos em inglês:** `DBMS_LOB`, `APEX_JSON`, `UTL_HTTP`, `DBMS_STATS` nunca traduzidos
5. **`lc_nome_unidade`** declarado em toda procedure pública
6. **`gc_nome_pacote`** declarado no package body
7. **Comentários em PT-BR** — explicam o PORQUÊ, não o QUÊ
8. **Status values em PT-BR:** `'PENDENTE'`, `'PAGO'`, `'CANCELADO'`, `'ATIVO'`, `'PROCESSADO'`
9. **`WHEN OTHERS THEN NULL`** ausente — sempre propagar com contexto
10. **`DBMS_OUTPUT`** ausente em produção — substituído por Logger

## O que fica em inglês obrigatoriamente

| Categoria | Exemplos |
|---|---|
| Keywords SQL/PL/SQL | `BEGIN`, `END`, `EXCEPTION`, `BULK COLLECT`, `FORALL`, `RETURN`, `IS`, `AS` |
| Pacotes Oracle nativos | `DBMS_LOB`, `DBMS_OUTPUT`, `DBMS_STATS`, `APEX_JSON`, `UTL_HTTP` |
| Funções built-in | `SYSDATE`, `NVL`, `COALESCE`, `TO_DATE`, `INSTR`, `SUBSTR` |
| Variáveis sistema APEX | `:APP_USER`, `:APP_SESSION`, `:APP_ID` |
| Hints | `/*+ APPEND */`, `/*+ PARALLEL */`, `/*+ INDEX */` |
| Prefixos Trivadis | `g_`, `gc_`, `l_`, `lc_`, `p_`, `r_`, `t_`, `co_`, `e_` |

## Referências cruzadas

| Precisa de | Skill |
|---|---|
| Geração de código PL/SQL, packages | **oracle-plsql-ptbr** |
| Código dentro de APEX processes | **oracle-apex-ptbr** |
| Código dentro de ORDS handlers | **oracle-ords-ptbr** |
| Scripts DBA com padrão Trivadis | **oracle-dba-ptbr** |
