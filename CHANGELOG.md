# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e este projeto adere a [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [v6] — 2026-04-30

### Adicionado
- Princípio canônico **#9**: Triggers não contêm regra de negócio
- Princípio canônico **#10**: Quando usar trigger, sempre compound trigger
- Princípio canônico **#11**: EBR para mudanças de schema com zero downtime
- Template novo: `assets/triggers_canonicos.sql` (compound trigger pattern, audit triggers, surrogate keys, cross-edition triggers para EBR, 7 anti-patterns documentados)
- Reference nova: `references/ebr-editioning-views.md` (Edition-Based Redefinition, editioning views, cross-edition triggers, procedimento canônico de deploy)
- Gatilhos da skill incluem agora: `compound trigger`, `EBR`, `edition`, `editioning view`, `cross-edition trigger`, `trigger pra auditar`, `deploy sem downtime`

### Modificado
- `assets/README.md` atualizado para incluir `triggers_canonicos.sql` na seção PL/SQL
- `SKILL.md` description expandida para mencionar EBR como nova área coberta

### Inspirado em
- Adoção pontual de regras Insum G-7720 e G-7730 (triggers sem business logic, compound triggers obrigatórios)
- Mantém base Trivadis 4.4 — não migra para naming Insum (`co_` em vez de `k_`, `p_` para todos parâmetros)

## [v5] — 2026-03

### Modificado
- **Inversão completa de naming inglês → PT-BR** em todos os 21 templates e 5 references
- Mapeamento PT-BR aplicado: `customers→clientes`, `invoices→faturas`, `documents→documentos`, `payments→pagamentos`, `users→usuarios`, `employees→funcionarios`, `event_log→log_eventos`, `audit_log→log_auditoria`, `process_queue→fila_processamento`, `created_at/by→criado_em/por`, `atualizado_em/por`, `ativo`, `excluido_em`
- Status values em PT-BR: `PENDENTE`, `PAGO`, `CANCELADO`, `ATIVO`, `PROCESSADO`, `VENCIDO`, `ALERTA`
- Naming code: `gc_nome_pacote`, `lc_nome_unidade`, `l_qtd`, `l_total`, `l_status_atual`, `l_id_fatura`, `l_id_cliente`, `t_lista_ids`, `r_resumo`, `co_faturas_pendentes`, `e_estado_invalido`, `p_id_fatura`
- APEX items: `P10_ID_CLIENTE`, `P10_NOME_CLIENTE`, `P10_TOTAL_DEVIDO`, etc.

### Mantido em inglês
- Keywords SQL/PL/SQL (BEGIN, END, EXCEPTION, BULK COLLECT, MERGE INTO, etc.)
- Pacotes Oracle nativos (DBMS_*, UTL_*, OWA_*, APEX_*)
- Bind variables sistema (:APP_USER, :APP_SESSION)
- Hints (/*+ APPEND */, /*+ PARALLEL */)
- Prefixos Trivadis (g_, gc_, l_, lc_, p_, r_, t_, co_, e_)

## [v4] — 2026-03

### Adicionado
- Princípio canônico **#0**: SQL puro antes de PL/SQL (princípio Tim Hall via Oracle-Base)
- Princípio canônico **#8**: NOCOPY para LOBs e collections grandes em IN OUT/OUT
- Template novo: `assets/dml_alternatives_to_plsql.sql` (MERGE em vez de loop, DBMS_ERRLOG em vez de FORALL SAVE EXCEPTIONS, multitable INSERT, External Tables, INSERT SELECT com APPEND/PARALLEL)
- Template novo: `assets/nocopy_for_lobs.sql` (NOCOPY hint para BLOB/CLOB > 100KB, cenário de PDF pages 15/49)
- Anti-patterns expandidos: 21 → 33

### Modificado
- Auditoria rigorosa contra Oracle-Base (Tim Hall) e documentação Oracle oficial
- 7 anti-slop cases (era 5)

## [v3] — 2026-03

### Adicionado
- 5 templates novos em assets/
- 7 princípios canônicos formalizados
- 12 operações de risco documentadas
- 21 antipatterns com correções

### Modificado
- Auditoria rigorosa contra documentação Oracle 19c oficial

## [v2] — 2026-03

### Adicionado
- Integração com Logger (OraOpenSource) — `assets/logger_integration.sql`
- DBMS_ASSERT em endpoints ORDS para proteção SQL injection
- APEX_BACKGROUND_PROCESS específico para APEX 24.2 — `assets/apex_long_running_job.sql`

## [v1] — 2026-03

### Adicionado
- Versão inicial da skill
- 16 templates SQL cobrindo PL/SQL, APEX, ORDS, DBA, performance
- 5 references com conceitos e padrões
- 8 princípios canônicos iniciais
- Padrão Trivadis 4.4 como base
