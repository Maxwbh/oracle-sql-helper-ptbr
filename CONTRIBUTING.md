# Como Contribuir

Obrigado pelo interesse em melhorar o `oracle-sql-helper-ptbr`!

## Tipos de contribuição bem-vindos

### 1. Reportar bugs / inconsistências em templates

Se você usou um template e ele não funcionou em sua instalação Oracle 19c, abra issue com:

- Versão exata do Oracle (`SELECT banner FROM v$version;`)
- Edition (Standard / Enterprise) e options instaladas
- Template afetado (ex: `assets/bulk_processing_template.sql`)
- Erro recebido (ORA-XXXXX e mensagem completa)
- Trecho mínimo reproduzível

### 2. Sugerir anti-patterns adicionais

A skill cobre vários anti-patterns clássicos. Se você identificou um que não está documentado, abra issue com:

- Descrição do anti-pattern
- Exemplo "errado" mínimo
- Exemplo "correto" sugerido
- Justificativa técnica (referência a Trivadis, Oracle-Base, MOS Note se possível)

### 3. Propor novos templates

Antes de propor template novo, verifique se a área não está coberta:

- PL/SQL: 9 templates
- APEX 24.2: 6 templates
- ORDS: 2 templates
- DBA operacional: 3 templates
- Performance: 2 templates
- EBR: 1 reference (sem template — usa templates PL/SQL existentes)

Se há lacuna real, abra issue descrevendo:

- Cenário de uso
- Por que os templates atuais não cobrem
- Esboço do template proposto

### 4. Sugerir adições/correções em references

References são markdown — fácil de revisar. PRs diretas são bem-vindas para:

- Correções de erros técnicos
- Atualização de links quebrados
- Inclusão de exemplos esclarecedores
- Adições de seções "anti-patterns"

## Padrões a seguir em PRs

### Naming

- Comentários e nomes de domínio em PT-BR
- Keywords Oracle e pacotes nativos em inglês obrigatoriamente
- Prefixos Trivadis em inglês: `g_`, `gc_`, `l_`, `lc_`, `p_`, `r_`, `t_`, `co_`, `e_`
- Não use naming Insum (`k_` para constantes, `_in`/`_out` para parâmetros) — esta skill é Trivadis 4.4

### Estrutura de templates

Templates SQL devem seguir o padrão dos existentes:

```sql
--==============================================================================
-- Template: <nome>
--
-- Cobre: <breve descrição>
-- Pré-requisito: <oracle 19c+ / 23ai+ / etc.>
-- Princípios aplicados: #X, #Y
--==============================================================================

-- 1. Setup inicial
...

-- 2. Caso principal
...

-- 3. Variações
...

--==============================================================================
-- N. Anti-patterns
--==============================================================================

/*
ANTI-PATTERN 1: ...
  Errado:
    ...
  Correto:
    ...
*/
```

### References

References em markdown devem ter:

- Conceito explicado em 1-2 parágrafos
- Tabela comparativa quando aplicável
- Exemplos de código curtos (não copiar templates inteiros)
- Seção "Quando usar" / "Quando não usar"
- Seção "Anti-patterns"
- Links para documentação oficial Oracle

## Processo de PR

1. Fork o repositório
2. Crie branch descritiva: `feat/template-cross-edition-trigger` ou `fix/typo-bulk-processing`
3. Faça as mudanças seguindo padrões acima
4. Atualize `CHANGELOG.md` com seu add/fix
5. Atualize `assets/README.md` se template novo, ou `SKILL.md` se princípio novo
6. Abra PR com descrição clara do problema e da solução
7. Aguarde review

## O que NÃO é aceito

- PRs que migram naming para Insum (`k_`, `_in`, `_out`) — esta skill é Trivadis 4.4 deliberadamente
- PRs que adicionam features 23ai/26ai (use `oracle-26ai-helper-ptbr` para isso)
- PRs que traduzem keywords Oracle ou pacotes nativos para PT-BR (DBMS_LOB → PCT_LOB → não)
- PRs sem justificativa técnica (referência a Oracle-Base, MOS Note, blog Tim Hall, etc.)
- Code dumps massivos sem teste prévio em ambiente Oracle real

## Código de Conduta

Seja respeitoso. Discussões técnicas são sobre código, não sobre pessoas. Todas as linguagens (PT-BR, EN, ES) são bem-vindas em issues, embora o conteúdo da skill seja em PT-BR.

## Contato

Issues no GitHub são o canal principal. Para discussões mais longas, abra Discussion (se habilitado no repo).
