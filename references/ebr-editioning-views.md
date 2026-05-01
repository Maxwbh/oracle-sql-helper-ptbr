# Edition-Based Redefinition (EBR) — Reference

Conceitos e padrões para zero-downtime application upgrade no Oracle Database.

EBR está disponível desde Oracle 11g R2 e funciona em **todas as editions** (Standard, Enterprise) sem licença adicional. "EBR is available for use in all editions of Oracle Database without the need to license it".

## Conceito

EBR permite upgrade do componente database de uma aplicação enquanto ela está em uso, mantendo a aplicação disponível durante todo o processo. "Allow arbitrary changes to a set of artifacts implementing application's database of record. Utilize both pre-upgrade and post-upgrade applications simultaneously (hot rollover). Maintain uninterrupted availability of the application across editions (live operation)".

Mecanismo:
1. Sessões existentes continuam usando edition antiga
2. Mudanças são instaladas em nova edition (isoladas)
3. Novas sessões usam edition nova
4. Quando todas sessões antigas terminam, edition antiga é retirada

## Componentes-chave

### Edition

Espaço nomeado, isolado, dentro do schema. "Editions are nonschema objects; as such, they do not have owners. Editions are created in a single namespace, and multiple editions can coexist in the database. The database must have at least one edition. Every newly created or upgraded Oracle Database starts with one edition named ora$base".

```sql
-- Criar edition filha
CREATE EDITION app_v2 AS CHILD OF ora$base;

-- Mudar edition da sessão
ALTER SESSION SET EDITION = app_v2;

-- Mudar default edition do banco (afeta novas sessões)
ALTER DATABASE DEFAULT EDITION = app_v2;

-- Retirar edition antiga (quando ninguém mais usa)
DROP EDITION ora$base CASCADE;
```

### Editioning View

"These views are EDITIONING enabled. New editions can contain new versions of the view (changing projections, joins, or underlying logic) without altering the base table structure".

A tabela física fica oculta atrás da editioning view. Cada edition tem sua própria versão da view, projetando colunas diferentes da mesma tabela base.

```sql
-- Tabela base (ficará "oculta" atrás de editioning views)
CREATE TABLE "_clientes" (
  id_cliente      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cpf             VARCHAR2(11),
  nome_completo   VARCHAR2(200),  -- coluna antiga
  primeiro_nome   VARCHAR2(100),  -- coluna nova
  sobrenome       VARCHAR2(100)   -- coluna nova
);

-- Editioning view na edition antiga: expõe nome_completo
CREATE OR REPLACE EDITIONING VIEW clientes AS
SELECT id_cliente, cpf, nome_completo
  FROM "_clientes";

-- Editioning view na edition nova: expõe primeiro_nome + sobrenome
ALTER SESSION SET EDITION = app_v2;
CREATE OR REPLACE EDITIONING VIEW clientes AS
SELECT id_cliente, cpf, primeiro_nome, sobrenome
  FROM "_clientes";
```

Convenção de naming Insum/Oracle: tabela base com underscore + lowercase (`"_clientes"`); view com nome "limpo" (`clientes`). "When naming tables that will be covered by editioning views, it is preferable to name the covered table in lower case begining with an underscore".

### Cross-Edition Trigger

Único caso onde lógica de transformação em trigger é justificável (princípio canônico #9 abre exceção para EBR).

Mantém dados sincronizados entre versões antiga e nova durante a janela de coexistência:

- **Forward cross-edition**: edition antiga grava → trigger preenche colunas novas
- **Reverse cross-edition**: edition nova grava → trigger preenche colunas antigas

Templates em `assets/triggers_canonicos.sql` seção 4.

## Tipos de objetos editionable

### Editionable (têm versões por edition)
- PL/SQL: Package, Procedure, Function, Type
- View, Synonym
- Trigger
- Library

### Non-editionable (compartilhadas entre editions)
- **Table** (mas pode ser coberta por editioning view)
- Index, Constraint
- Materialized View
- Sequence
- Public synonym
- User/role/grant

"Tables / Indexes / Mviews / Public synonyms are Non-Editionable because changes to table structures are not editionable directly". A solução para tabelas é a editioning view + cross-edition triggers.

## Quando usar EBR

✓ **Sistema 24/7 sem janela de manutenção** (hospital, banco, governo crítico)
✓ **APEX em produção com alta concorrência** (deploy não pode parar usuários ativos)
✓ **Múltiplas aplicações compartilhando schema** (uma muda, outras não podem quebrar)
✓ **Canary releases** (testar nova edition com subset de usuários)
✓ **A/B testing de mudanças de schema**

✗ **Aplicação com janela de manutenção tolerável** (overhead de EBR não compensa)
✗ **Equipe sem disciplina de schema** (EBR exige rigor)
✗ **Schema em rápida evolução com muitas tabelas mudando** (cross-edition triggers viram inferno)

## Análise de adoção em ambiente típico

### Cenário hipotético
- Instituição com sistema crítico em horário comercial
- APEX em produção atendendo usuários internos e/ou externos
- Janela de manutenção: noturna ou fim de semana, atualmente tolerada
- Equipe DBA: pode não ter experiência prévia com EBR

### Custos
- Refatorar tabelas para usar editioning views: trabalho one-time significativo
- Cross-edition triggers durante migrações: complexidade nova
- Disciplina de release: cada deploy vira processo de 4-6 etapas
- Treinamento DBA: necessário antes de adotar

### Benefícios
- Zero downtime em deploy de PL/SQL e views (a maioria das mudanças)
- Rollback rápido (basta voltar default edition)
- Testar mudanças com sessão isolada (`ALTER SESSION SET EDITION = ...`) antes de tornar default
- Conformidade com requisitos de uptime em sistemas críticos

### Recomendação genérica
- **Curto prazo** (próximos meses): manter modelo atual (janela de manutenção)
- **Médio prazo** (6-12 meses): adotar EBR para módulos críticos novos
  - Começar com 1 schema dedicado ao novo módulo
  - Não tentar migrar schemas legados existentes (custo > benefício)
- **Longo prazo**: avaliar migração completa se janela de manutenção virar restrição

## Procedimento canônico — deploy via EBR

```sql
-- 1. Criar edition filha
CREATE EDITION app_v2 AS CHILD OF app_v1;

-- 2. Conceder USE
GRANT USE ON EDITION app_v2 TO app_owner, app_user;

-- 3. Mudar sessão de deploy para edition nova
ALTER SESSION SET EDITION = app_v2;

-- 4. Aplicar mudanças (PL/SQL, views) na edition nova
-- Apenas objetos editionable são afetados
CREATE OR REPLACE PACKAGE faturas_pkg AS ...;
CREATE OR REPLACE EDITIONING VIEW faturas AS ...;

-- 5. Se mudanças incluem estrutura de tabela:
--    a. Adicionar colunas novas (DDL "online" no Oracle 12+)
--    b. Criar editioning view na edition nova com colunas novas
--    c. Habilitar cross-edition triggers (forward + reverse)
--    d. Migrar dados existentes via DBMS_PARALLEL_EXECUTE
ALTER TABLE "_faturas" ADD (nova_coluna VARCHAR2(100));

-- 6. Testar nova edition com sessão isolada
ALTER SESSION SET EDITION = app_v2;
-- ... testes ...

-- 7. Tornar nova edition default (afeta novas sessões)
ALTER DATABASE DEFAULT EDITION = app_v2;

-- 8. Aguardar sessões antigas terminarem
SELECT username, session_id, session_edition_name
  FROM v$session
 WHERE username IN ('APP_USER', 'APP_OWNER');

-- 9. Quando ninguém mais está em app_v1, retirar
REVOKE USE ON EDITION app_v1 FROM PUBLIC;
DROP EDITION app_v1 CASCADE;
```

## Limitações

"Cannot be used for changes requiring table modifications (adding/dropping columns, constraints) without additional techniques like Cross-Edition Triggers or Online Table Redefinition".

- Tabelas não são editionable diretamente — exigem editioning view
- DROP de coluna requer cleanup em fase posterior (não imediata)
- Recomendado: "keeping no more than 25 editions before enacting a manual clean up cycle"
- Sessões long-running atrasam retirada da edition antiga
- Em CDB, scope de edition é o PDB (não cross-PDB)
- RAC: EBR funciona em uma instance; rolling upgrades de RAC é assunto separado

## Anti-patterns EBR

| Antipattern | Problema | Solução |
|---|---|---|
| Aplicação acessa tabela base diretamente | Quebra isolamento entre editions | Sempre via editioning view |
| Cross-edition trigger com lógica de negócio | Vira código duplicado entre versões | Apenas transformação simples de dados |
| Não retirar editions antigas | Acúmulo > 25 degrada performance | Cleanup periódico via `DBMS_EDITIONS_UTILITIES.CLEAN_UNUSABLE_EDITIONS` |
| Esquecer GRANT USE em nova edition | Aplicação não enxerga edition nova | `GRANT USE ON EDITION x TO y` é obrigatório |
| Misturar schema editions-enabled e não-enabled | Inconsistência | Decida por schema; planeje migração antes |
| Reverse cross-edition trigger esquecido habilitado após cutover | Performance degradada permanente | Disable + drop como parte do procedimento |

## Privilégios necessários

```sql
-- Para criar/dropar editions
GRANT CREATE ANY EDITION, DROP ANY EDITION TO app_admin;

-- Para usar uma edition
GRANT USE ON EDITION app_v2 TO app_user;

-- Para schema poder ter editioning views
ALTER USER app_owner ENABLE EDITIONS;
```

## Recursos

- Manual oficial: [Using Edition-Based Redefinition](https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/editions.html) (capítulo 24 do Database Development Guide 19c, capítulo 19 em versões anteriores)
- White paper: [EBR Technical Deep Dive](https://www.oracle.com/a/tech/docs/ebr-technical-deep-dive-overview.pdf)
- FAQ: [EBR Frequently Asked Questions](https://www.oracle.com/a/tech/docs/ebr-faq.pdf)
- Oracle MAA: [Edition-Based Redefinition - Zero Downtime Application Upgrades](https://blogs.oracle.com/maa/edition-based-redefinition-a-solution-for-zero-downtime-application-upgrades)
- Oracle-Base: artigos de Tim Hall sobre EBR (cobertura prática)

## Considerações para 26ai

EBR continua funcionando em 26ai sem mudanças significativas. Pontos relevantes:
- Em CDB (multitenant obrigatório em 26ai), scope da edition é o PDB
- JSON Relational Duality views podem ser cobertas por editioning views? **Provavelmente não diretamente** (são views especiais); confirmar caso a caso
- AI Vector Search columns em tabelas: tabela base + editioning view continua sendo padrão
