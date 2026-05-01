# PL/SQL — Trivadis Guidelines 4.4

Detalhes dos padrões Trivadis para Oracle PL/SQL. Use esta referência quando precisar revisar código alheio, justificar uma escolha em code review, ou aplicar padrão consistente em código novo.

## Por que Trivadis 4.4

Trivadis Guidelines é o padrão de facto para Oracle PL/SQL profissional, mantido pela Trivadis (consultoria suíça). A versão 4.4 (2017) é a mais ampla adotada no mercado brasileiro. Característica: convenções rígidas mas justificadas, foco em manutenibilidade.

Documento original: https://trivadis.github.io/plsql-and-sql-coding-guidelines/v4.4/

## Naming conventions completas

### Variáveis

| Prefixo | Escopo | Exemplo |
|---|---|---|
| `g_` | Variável de pacote (global) | `g_id_usuario NUMBER;` |
| `gc_` | Constante de pacote | `gc_max_tentativas CONSTANT NUMBER := 3;` |
| `gco_` | Variável de contexto | `gco_idioma_sessao VARCHAR2(10);` |
| `l_` | Variável local | `l_qtd NUMBER;` |
| `lc_` | Constante local | `lc_idioma_default CONSTANT VARCHAR2(2) := 'PT';` |
| `p_` | Parâmetro | `p_id_funcionario IN NUMBER` |
| `r_` | Record | `r_funcionario funcionarios%ROWTYPE;` |
| `t_` | Type definition | `TYPE t_lista_ids IS TABLE OF NUMBER;` |
| `co_` | Cursor | `CURSOR co_ativos IS SELECT ...` |
| `e_` | Exception | `e_estado_invalido EXCEPTION;` |

> **Importante:** os prefixos (`g_`, `gc_`, `l_`, etc.) são parte do padrão Trivadis e **mantêm-se em inglês**. Apenas o nome após o prefixo é em PT-BR.

### Procedures e Functions

- **Verbo no infinitivo:** `processar_fatura`, `validar_cpf`, `enviar_notificacao`
- **Sem prefixos redundantes:** evite `executar_processo`, `rodar_limpeza`
- **Function vs Procedure:**
  - Function: retorna valor único, nome geralmente é substantivo do retorno (`obter_valor_total`)
  - Procedure: ação que pode ter side effects, nome é verbo (`processar_pagamento`)

### Packages

- **Sufixo `_pkg`:** recomendado mas não obrigatório
- **Singular:** `pagamento_pkg`, não `pagamentos_pkg`
- **Domínio bem definido:** package de pagamento não cuida de NFSe; cada package tem responsabilidade única

### Tabelas e colunas

Trivadis foca em PL/SQL, mas aplicar consistência ajuda:

- **Tabelas em minúsculas, plural:** `funcionarios`, `faturas`, `clientes`
- **PK simples como `id`:** `funcionarios.id`, `faturas.id` (padrão moderno) ou `id_funcionario`, `id_fatura` (padrão tradicional)
- **FK com nome explícito:** `id_cliente`, `id_funcionario` (deixa o relacionamento óbvio)
- **Booleanos como CHAR(1):** `ativo CHAR(1) CHECK (ativo IN ('S','N'))` (Oracle não tem BOOLEAN em SQL puro)

## Estrutura de package

### Header (SPEC)

```sql
CREATE OR REPLACE PACKAGE example_pkg AS
  /**
   * Package responsável por processar exemplos.
   *
   * Convenção: uma frase descrevendo a responsabilidade do package.
   * Linhas adicionais para detalhes importantes (regras de negócio,
   * dependências externas, observações de uso).
   */

  -- ============================================================
  -- Tipos públicos
  -- ============================================================
  TYPE t_id_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

  -- ============================================================
  -- Constantes públicas (raras — geralmente private)
  -- ============================================================
  gc_max_records CONSTANT NUMBER := 1000;

  -- ============================================================
  -- Exceptions públicas (uso por callers)
  -- ============================================================
  e_invalid_state EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_invalid_state, -20100);

  -- ============================================================
  -- Procedures e Functions públicas
  -- ============================================================

  /**
   * Processa um exemplo.
   *
   * @param p_id           ID do exemplo a processar
   * @param p_force_update Se Y, força atualização mesmo se already processed
   *
   * @raises e_invalid_state Se o exemplo está em estado inválido
   */
  PROCEDURE process_example(
    p_id           IN NUMBER,
    p_force_update IN VARCHAR2 DEFAULT 'N'
  );

  FUNCTION obter_status(
    p_id IN NUMBER
  ) RETURN VARCHAR2;

END example_pkg;
/
```

### Body (BODY)

```sql
CREATE OR REPLACE PACKAGE BODY example_pkg AS
  -- ============================================================
  -- Constantes privadas
  -- ============================================================
  gc_nome_pacote CONSTANT VARCHAR2(30) := 'EXAMPLE_PKG';

  -- ============================================================
  -- Variáveis globais (cuidado: persistem entre chamadas na sessão)
  -- ============================================================
  g_cache_initialized BOOLEAN := FALSE;

  -- ============================================================
  -- Forward declarations (para procedures privadas usadas antes de declaradas)
  -- ============================================================
  PROCEDURE validate_state(p_id IN NUMBER);

  -- ============================================================
  -- Procedures e Functions
  -- ============================================================

  PROCEDURE process_example(
    p_id           IN NUMBER,
    p_force_update IN VARCHAR2 DEFAULT 'N'
  ) IS
    lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.process_example';
    l_status     VARCHAR2(20);
  BEGIN
    -- Valida estado antes de processar
    validate_state(p_id);

    -- Lógica principal
    SELECT status INTO l_status FROM examples WHERE id = p_id;

    IF l_status = 'PROCESSADO' AND p_force_update = 'N' THEN
      RETURN;  -- já processado, no-op
    END IF;

    UPDATE examples SET status = 'PROCESSADO', processed_at = SYSDATE
     WHERE id = p_id;

    COMMIT;

  EXCEPTION
    WHEN e_invalid_state THEN
      raise_application_error(-20100,
        'Estado inválido em ' || lc_nome_unidade || ' para ID ' || p_id);
    WHEN OTHERS THEN
      ROLLBACK;
      raise_application_error(-20999,
        'Erro inesperado em ' || lc_nome_unidade || ': ' || SQLERRM);
  END process_example;


  FUNCTION obter_status(
    p_id IN NUMBER
  ) RETURN VARCHAR2 IS
    l_status VARCHAR2(20);
  BEGIN
    SELECT status INTO l_status FROM examples WHERE id = p_id;
    RETURN l_status;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END obter_status;


  PROCEDURE validate_state(p_id IN NUMBER) IS
    l_state VARCHAR2(20);
  BEGIN
    SELECT state INTO l_state FROM examples WHERE id = p_id;
    IF l_state NOT IN ('VALID', 'PENDENTE') THEN
      RAISE e_invalid_state;
    END IF;
  END validate_state;

END example_pkg;
/
```

## Exception handling

### Padrão completo

Todo procedure tem três blocos de exception:

```sql
EXCEPTION
  WHEN e_specific_known THEN
    -- Logging contextual + re-raise específico
    raise_application_error(-20001,
      'Contexto específico em ' || lc_nome_unidade || ': ' || ...);

  WHEN NO_DATA_FOUND THEN
    -- Tratamento esperado (pode ser RETURN NULL, default value, etc.)
    NULL;

  WHEN OTHERS THEN
    -- Captura último, com ROLLBACK se houve DML
    ROLLBACK;
    raise_application_error(-20999,
      'Erro inesperado em ' || lc_nome_unidade || ': ' || SQLERRM);
END;
```

### Constante `lc_nome_unidade`

Cada procedure tem uma constante local com nome canônico para logging:

```sql
PROCEDURE processar_pagamento IS
  lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.processar_pagamento';
BEGIN
  ...
EXCEPTION
  WHEN OTHERS THEN
    log_error(lc_nome_unidade, SQLERRM);
    RAISE;
END;
```

Permite rastrear exatamente onde o erro ocorreu sem depender de stack trace.

### Quando NÃO capturar exceptions

- Não suprima erros que indiquem bug (NO_DATA_FOUND inesperado, ZERO_DIVIDE)
- Não engula `WHEN OTHERS THEN NULL` (anti-pattern absoluto)
- Não capture exception só para re-raise sem adicionar contexto

```sql
-- ANTIPATTERN
EXCEPTION
  WHEN OTHERS THEN NULL;

-- ANTIPATTERN
EXCEPTION
  WHEN OTHERS THEN RAISE;  -- não adicionou nada

-- BOM
EXCEPTION
  WHEN OTHERS THEN
    raise_application_error(-20999, 'Erro em ' || lc_nome_unidade || ': ' || SQLERRM);
```

## Cursores

### Implícito (preferencial para casos simples)

```sql
SELECT col1, col2 INTO l_var1, l_var2 FROM tab WHERE id = p_id;
```

Usa `NO_DATA_FOUND` / `TOO_MANY_ROWS` automaticamente.

### Explícito (para múltiplas linhas com lógica)

```sql
DECLARE
  CURSOR co_active_users IS
    SELECT id_usuario, last_login FROM usuarios WHERE status = 'A';
  r_user co_active_users%ROWTYPE;
BEGIN
  OPEN co_active_users;
  LOOP
    FETCH co_active_users INTO r_user;
    EXIT WHEN co_active_users%NOTFOUND;

    -- Lógica
  END LOOP;
  CLOSE co_active_users;
END;
```

### Cursor FOR loop (sintaxe limpa, evita BULK)

```sql
FOR r_user IN (SELECT id_usuario, last_login FROM usuarios WHERE status = 'A') LOOP
  -- Lógica
END LOOP;
```

**Apenas para lógica leve.** Para operações em volume, use BULK.

## Bulk processing

Quando processar muitas linhas, **sempre** use bulk:

```sql
DECLARE
  TYPE t_id_tab IS TABLE OF usuarios.id_usuario%TYPE;
  l_user_ids t_id_tab;
BEGIN
  -- BULK COLLECT
  SELECT id_usuario BULK COLLECT INTO l_user_ids
    FROM usuarios
   WHERE status = 'A';

  -- FORALL para DML
  FORALL i IN l_user_ids.FIRST..l_user_ids.LAST
    UPDATE usuarios SET last_processed = SYSDATE
     WHERE id_usuario = l_user_ids(i);

  COMMIT;
END;
```

### LIMIT em BULK COLLECT

Para tabelas grandes, processe em chunks:

```sql
DECLARE
  CURSOR co_users IS SELECT id_usuario FROM usuarios WHERE status = 'A';
  TYPE t_id_tab IS TABLE OF NUMBER;
  l_ids t_id_tab;
  lc_limit CONSTANT PLS_INTEGER := 1000;
BEGIN
  OPEN co_users;
  LOOP
    FETCH co_users BULK COLLECT INTO l_ids LIMIT lc_limit;
    EXIT WHEN l_ids.COUNT = 0;

    FORALL i IN l_ids.FIRST..l_ids.LAST
      UPDATE other_tab SET ... WHERE id = l_ids(i);

    COMMIT;
  END LOOP;
  CLOSE co_users;
END;
```

## Transações

### Princípios

- **Uma unidade lógica = uma transação.** Não commit dentro de loop sem razão.
- **Procedures não comitam por default.** Caller decide quando commitar (autonomous transaction é exceção).
- **ROLLBACK em exception handler:** se a procedure fez DML, rollback antes de re-raise.

### Autonomous transaction

Use **apenas** para logging/auditoria que precisa persistir mesmo se transação principal falhar:

```sql
PROCEDURE registrar_evento(p_msg IN VARCHAR2) IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO log_eventos(msg, criado_em) VALUES (p_msg, SYSDATE);
  COMMIT;  -- obrigatório em autonomous
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    NULL;  -- log de log não deve quebrar fluxo principal
END;
```

## Comentários

### Comentário de package/procedure (Javadoc-like)

```sql
/**
 * Processa pagamento de uma fatura.
 *
 * Aplica regras de multa e juros conforme tabela de configuração.
 * Atualiza status para PAID e cria registro em payment_history.
 *
 * @param p_id_fatura  ID da fatura
 * @param p_payment_dt  Data do pagamento (default SYSDATE)
 *
 * @raises e_invoice_not_found  Fatura não existe
 * @raises e_already_paid       Fatura já foi paga
 */
PROCEDURE processar_pagamento(
  p_id_fatura IN NUMBER,
  p_payment_dt IN DATE DEFAULT SYSDATE
);
```

### Comentário inline

Explica **por quê**, nunca **o quê**:

```sql
-- RUIM
l_total := l_total + r.valor;  -- soma o valor

-- BOM
l_total := l_total + r.valor;  -- soma apenas se categoria = "operacional" (regra fiscal IRPJ)
```

### Comentário de bloco

```sql
-- ============================================================
-- Validação de elegibilidade
--
-- Regras conforme NORMA-2024-15:
--   1. Cliente deve estar ativo há > 12 meses
--   2. Não pode ter pendência fiscal aberta
--   3. Volume mensal > limite mínimo (parametrizável)
-- ============================================================
```

## Antipatterns Trivadis-explicit

| Antipattern | Por quê é ruim |
|---|---|
| SQL dinâmico com concatenação | SQL injection + hard parse |
| Loop linha-a-linha em grandes volumes | Performance terrível |
| `WHEN OTHERS THEN NULL` | Mascara bugs |
| Variáveis globais sem necessidade | Side effects difíceis de rastrear |
| Comentário que repete o código | Ruído visual |
| Nomes em português abreviados | `proc_p_p` ilegível 1 mês depois |
| `GOTO` | Sempre há alternativa estruturada |
| Triggers com lógica complexa | Vire procedure, chame do trigger |

## Linkagem com outros recursos

- Para padrões APEX específicos → `apex-patterns.md`
- Para ORDS → `ords-rest-services.md`
- Para issues operacionais (lock, sessão) → `dba-operations.md`
- Para análise de performance → `performance-tuning.md`
- Templates prontos → `assets/package_header.sql`, `assets/package_body.sql`, etc.
