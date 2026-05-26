--==============================================================================
-- Template: Triggers Canônicos
--
-- Cobre: compound trigger pattern, audit triggers (criado_em/criado_por,
-- atualizado_em/atualizado_por), surrogate keys, anti-patterns de business
-- logic em triggers.
--
-- Princípios canônicos aplicados:
--   #9: Triggers não contêm regra de negócio
--   #10: Quando usar trigger, sempre compound trigger
--
-- Referência: padrão Trivadis 4.4 + adoções de Insum (G-7720, G-7730).
--==============================================================================


--==============================================================================
-- 1. Compound trigger — estrutura canônica
--
-- COMPOUND TRIGGER consolida BEFORE/AFTER/STATEMENT/ROW em um só objeto.
-- Elimina mutating table errors, permite estado entre fases.
-- É a forma RECOMENDADA desde 11g.
--==============================================================================

CREATE OR REPLACE TRIGGER tr_faturas_audit
FOR INSERT OR UPDATE OR DELETE ON faturas
COMPOUND TRIGGER

  -- Estado compartilhado entre fases (escopo: 1 statement DML)
  TYPE t_lista_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  l_ids_alterados t_lista_ids;
  l_qtd PLS_INTEGER := 0;

  --------------------------------------------------------------------
  BEFORE STATEMENT IS
  --------------------------------------------------------------------
  BEGIN
    -- Reset de estado a cada statement (importante em loops PL/SQL)
    l_ids_alterados.delete;
    l_qtd := 0;
  END BEFORE STATEMENT;

  --------------------------------------------------------------------
  BEFORE EACH ROW IS
  --------------------------------------------------------------------
  BEGIN
    -- Auditoria de criação
    IF INSERTING THEN
      :NEW.criado_em  := SYSTIMESTAMP;
      :NEW.criado_por := NVL(SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER'), USER);
      :NEW.atualizado_em  := :NEW.criado_em;
      :NEW.atualizado_por := :NEW.criado_por;
    END IF;

    -- Auditoria de atualização
    IF UPDATING THEN
      :NEW.atualizado_em  := SYSTIMESTAMP;
      :NEW.atualizado_por := NVL(SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER'), USER);

      -- Preserva campos imutáveis (audit trail de criação)
      :NEW.criado_em  := :OLD.criado_em;
      :NEW.criado_por := :OLD.criado_por;
    END IF;
  END BEFORE EACH ROW;

  --------------------------------------------------------------------
  AFTER EACH ROW IS
  --------------------------------------------------------------------
  BEGIN
    -- Coleta IDs para processamento agregado em AFTER STATEMENT
    -- Evita mutating table — não consultamos a tabela aqui
    IF INSERTING OR UPDATING THEN
      l_qtd := l_qtd + 1;
      l_ids_alterados(l_qtd) := :NEW.id_fatura;
    END IF;
  END AFTER EACH ROW;

  --------------------------------------------------------------------
  AFTER STATEMENT IS
  --------------------------------------------------------------------
  BEGIN
    -- Processamento agregado: chama package que faz o trabalho
    -- Trigger NÃO contém a lógica — apenas notifica
    IF l_qtd > 0 THEN
      auditoria_pkg.registrar_alteracao_faturas(
        p_ids        => l_ids_alterados,
        p_operacao   => CASE WHEN INSERTING THEN 'INSERT' ELSE 'UPDATE' END
      );
    END IF;
  END AFTER STATEMENT;

END tr_faturas_audit;
/


--==============================================================================
-- 2. Surrogate key trigger (quando IDENTITY não está disponível ou em legacy)
--
-- Em 12c+, prefira GENERATED ALWAYS AS IDENTITY na declaração da coluna.
-- Trigger só é necessário em código legado pré-12c.
--==============================================================================

-- Forma moderna (preferir):
CREATE TABLE pagamentos (
  id_pagamento  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_fatura     NUMBER NOT NULL,
  valor         NUMBER(10,2),
  pago_em       TIMESTAMP DEFAULT SYSTIMESTAMP,
  criado_por    VARCHAR2(50)
);

-- Forma legada com sequence + trigger (apenas quando necessário):
CREATE SEQUENCE seq_pagamentos START WITH 1 NOCACHE NOORDER;

CREATE OR REPLACE TRIGGER tr_pagamentos_pk
BEFORE INSERT ON pagamentos
FOR EACH ROW
BEGIN
  IF :NEW.id_pagamento IS NULL THEN
    :NEW.id_pagamento := seq_pagamentos.NEXTVAL;
  END IF;
END tr_pagamentos_pk;
/


--==============================================================================
-- 3. Trigger de auditoria genérica para múltiplas tabelas
--
-- Padrão: package centraliza a lógica; triggers individuais só notificam.
--==============================================================================

CREATE OR REPLACE PACKAGE auditoria_pkg AS

  PROCEDURE registrar_alteracao_faturas (
    p_ids       IN auditoria_pkg.t_lista_ids,
    p_operacao  IN VARCHAR2
  );

  PROCEDURE registrar_alteracao_clientes (
    p_id_cliente  IN NUMBER,
    p_operacao    IN VARCHAR2,
    p_dados_old   IN VARCHAR2,
    p_dados_new   IN VARCHAR2
  );

  TYPE t_lista_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

END auditoria_pkg;
/


--==============================================================================
-- 4. EBR — cross-edition trigger (template conceitual)
--
-- Cross-edition triggers são o ÚNICO caso onde lógica de transformação
-- de dados em trigger é justificável (princípio #9 abre exceção para EBR).
--
-- São usados durante migração de schema entre editions, mantendo
-- compatibilidade entre versão antiga e nova da aplicação.
--==============================================================================

-- Cenário: coluna `nome` está sendo dividida em `primeiro_nome` + `sobrenome`.
-- Edition antiga vê `nome`; edition nova vê os dois campos separados.
-- Forward cross-edition trigger mantém os campos novos sincronizados quando
-- a edition antiga grava em `nome`.

CREATE OR REPLACE TRIGGER tr_clientes_fwd_xed
BEFORE INSERT OR UPDATE OF nome ON clientes
FOR EACH ROW
FORWARD CROSSEDITION
DISABLE  -- habilitada apenas durante migração
DECLARE
  l_pos PLS_INTEGER;
BEGIN
  -- Só atua quando a edition antiga grava em :NEW.nome
  l_pos := INSTR(:NEW.nome, ' ');
  IF l_pos > 0 THEN
    :NEW.primeiro_nome := SUBSTR(:NEW.nome, 1, l_pos - 1);
    :NEW.sobrenome     := SUBSTR(:NEW.nome, l_pos + 1);
  ELSE
    :NEW.primeiro_nome := :NEW.nome;
    :NEW.sobrenome     := NULL;
  END IF;
END tr_clientes_fwd_xed;
/

-- Reverse cross-edition trigger faz o inverso: edition nova grava em
-- primeiro_nome + sobrenome, trigger reconstrói `nome` para edition antiga.

CREATE OR REPLACE TRIGGER tr_clientes_rev_xed
BEFORE INSERT OR UPDATE OF primeiro_nome, sobrenome ON clientes
FOR EACH ROW
REVERSE CROSSEDITION
DISABLE
BEGIN
  :NEW.nome := TRIM(:NEW.primeiro_nome || ' ' || :NEW.sobrenome);
END tr_clientes_rev_xed;
/

-- Detalhes completos do uso de cross-edition triggers em
-- references/ebr-editioning-views.md


--==============================================================================
-- 5. Anti-patterns
--==============================================================================

/*
ANTI-PATTERN 1: Business logic em trigger (CRÍTICO)

  -- ERRADO: regra de negócio escondida em trigger
  CREATE OR REPLACE TRIGGER tr_faturas_calcular
  BEFORE INSERT OR UPDATE ON faturas
  FOR EACH ROW
  DECLARE
    l_taxa NUMBER;
    l_desconto NUMBER;
  BEGIN
    -- Cálculo complexo de imposto
    SELECT taxa INTO l_taxa
      FROM regras_fiscais WHERE estado = :NEW.estado_uf;

    -- Aplicação de desconto baseado em histórico
    SELECT NVL(SUM(valor), 0) INTO l_desconto
      FROM pagamentos
     WHERE id_cliente = :NEW.id_cliente
       AND pago_em >= ADD_MONTHS(SYSDATE, -12);

    IF l_desconto > 100000 THEN
      :NEW.valor := :NEW.valor * 0.95;  -- desconto fidelidade
    END IF;

    :NEW.valor_imposto := :NEW.valor * l_taxa / 100;
  END;
  /

  Problemas:
  - Lógica fica escondida; quem lê faturas_pkg não vê
  - Quebra em bulk INSERT (FORALL não pode ser revertido facilmente)
  - Mutating table se quiser ler outras linhas de faturas
  - Performance: 1 query por linha em vez de DML único
  - Difícil de testar isoladamente

  -- CORRETO: lógica em package, chamada explícita
  CREATE OR REPLACE PACKAGE faturas_pkg AS
    PROCEDURE criar_fatura (
      p_id_cliente  IN NUMBER,
      p_valor       IN NUMBER,
      p_estado_uf   IN VARCHAR2,
      p_id_fatura   OUT NUMBER
    );
  END faturas_pkg;
  /

  -- O caller chama faturas_pkg.criar_fatura, que aplica regras claramente.


ANTI-PATTERN 2: Triggers separados em vez de compound

  -- ERRADO: 3 triggers separados, estado compartilhado via package global
  CREATE TRIGGER tr_faturas_bs ... BEFORE STATEMENT
  CREATE TRIGGER tr_faturas_br ... BEFORE EACH ROW
  CREATE TRIGGER tr_faturas_as ... AFTER STATEMENT

  -- CORRETO: COMPOUND TRIGGER único, estado local


ANTI-PATTERN 3: Trigger encadeado / cascading

  -- ERRADO: trigger A insere em B; trigger B insere em C; trigger C atualiza A
  -- Resultado: loop infinito, dificílimo de debugar

  -- CORRETO: chamada explícita via package, controle de fluxo claro


ANTI-PATTERN 4: SELECT na própria tabela do trigger (mutating table)

  -- ERRADO em FOR EACH ROW
  CREATE TRIGGER tr_faturas_check
  BEFORE INSERT ON faturas
  FOR EACH ROW
  DECLARE
    l_total NUMBER;
  BEGIN
    SELECT SUM(valor) INTO l_total FROM faturas WHERE ...;  -- ORA-04091
  END;

  -- CORRETO: COMPOUND TRIGGER coleta IDs em AFTER EACH ROW,
  -- consulta agregada em AFTER STATEMENT


ANTI-PATTERN 5: Trigger fazendo COMMIT ou ROLLBACK

  -- ERRADO: rompe transação do caller
  CREATE TRIGGER tr_log_audit
  AFTER INSERT ON faturas
  FOR EACH ROW
  DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO log_audit ...;
    COMMIT;  -- caller não controla mais a transação
  END;

  -- AUTONOMOUS_TRANSACTION em trigger é code smell. Prefira:
  -- - Logger framework (que já gerencia autonomous internally)
  -- - Package que processa o evento de forma síncrona
  -- - DBMS_AQ para fila assíncrona


ANTI-PATTERN 6: Validação de regra de domínio em trigger

  -- ERRADO
  CREATE TRIGGER tr_faturas_valid
  BEFORE INSERT OR UPDATE ON faturas
  FOR EACH ROW
  BEGIN
    IF :NEW.valor < 0 THEN
      raise_application_error(-20100, 'Valor não pode ser negativo');
    END IF;
    IF :NEW.data_vencimento < SYSDATE THEN
      raise_application_error(-20101, 'Vencimento no passado');
    END IF;
  END;

  -- CORRETO:
  -- 1. CHECK constraint na tabela:
  --    ALTER TABLE faturas ADD CONSTRAINT ck_faturas_valor_pos CHECK (valor >= 0);
  -- 2. Validação de regra complexa em package: faturas_pkg.validar_fatura()
  --    chamado pelo caller ANTES do INSERT.


ANTI-PATTERN 7: Trigger lendo SYS_CONTEXT mal documentado

  -- Cuidado com USER vs CLIENT_IDENTIFIER vs OS_USER
  -- USER: schema atual do banco (ex: APP_OWNER); igual para todos os usuários da app
  -- CLIENT_IDENTIFIER: setado pela aplicação via DBMS_SESSION.SET_IDENTIFIER
  --                    (ex: usuário APEX, identidade do consumidor REST)
  -- OS_USER: sistema operacional (raramente útil em apps web)

  -- BOM (com fallback explícito):
  :NEW.criado_por := NVL(SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER'), USER);
*/


--==============================================================================
-- 6. Decisão rápida
--==============================================================================

/*
PRECISA TRIGGER?

  Auditoria simples (criado_em/criado_por)?           → COMPOUND TRIGGER
  Surrogate key em sistema legado pré-12c?            → BEFORE INSERT FOR EACH ROW
  Migração de schema com EBR (cross-edition)?         → CROSSEDITION TRIGGER
  Validação de regra de domínio?                      → CHECK CONSTRAINT ou package
  Cálculo de campo derivado?                          → VIRTUAL COLUMN ou package
  Cascade de operações em outra tabela?               → Package, NÃO trigger
  Processamento assíncrono?                           → DBMS_AQ + scheduler job
  Logging?                                            → Logger framework

REGRA GERAL:
  - Trigger faz NO MÁXIMO: setar campos de auditoria, gerar ID, notificar package
  - Trigger NUNCA faz: lógica de domínio, COMMIT, SELECT na própria tabela,
    decisões de negócio, transformações complexas (exceto cross-edition em EBR)
*/
