--==============================================================================
-- Package BODY: <NOME_PACOTE>_PKG
-- Implementação dos métodos declarados na SPEC.
-- 
-- Padrões:
--   - gc_nome_pacote CONSTANT como identificador para logging/exceptions
--   - lc_nome_unidade por procedure (escopo local) compondo gc_nome_pacote + nome
--   - Exception handler padrão em todo procedure público
--   - Forward declarations para procedures privadas usadas antes de declaradas
--==============================================================================

CREATE OR REPLACE PACKAGE BODY <nome_pacote>_pkg AS

  --============================================================================
  -- Constantes privadas
  --============================================================================
  
  -- Identificador do package para logging/exceptions
  gc_nome_pacote CONSTANT VARCHAR2(30) := '<NOME_PACOTE>_PKG';

  -- Status válidos do domínio
  gc_status_pendente  CONSTANT VARCHAR2(1) := 'P';
  gc_status_ativo     CONSTANT VARCHAR2(1) := 'A';
  gc_status_concluido CONSTANT VARCHAR2(1) := 'C';

  --============================================================================
  -- Variáveis globais (use com parcimônia — persistem na sessão)
  --============================================================================
  
  g_cache_inicializado BOOLEAN := FALSE;

  --============================================================================
  -- Forward declarations (procedures privadas usadas antes de declaradas)
  --============================================================================
  
  PROCEDURE validar_estado_registro (p_id IN NUMBER);
  PROCEDURE registrar_evento (p_mensagem IN VARCHAR2);

  --============================================================================
  -- Procedures e Functions públicas
  --============================================================================

  -----------------------------------------------------------------------------
  -- processar_registro
  -----------------------------------------------------------------------------
  PROCEDURE processar_registro (
    p_id            IN NUMBER,
    p_forcar_update IN VARCHAR2 DEFAULT 'N'
  ) IS
    -- Identificador único da unidade para logging
    lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.processar_registro';
    
    l_status_atual VARCHAR2(1);
    l_qtd          NUMBER;
  BEGIN
    -- Validação de pré-condições
    IF p_id IS NULL THEN
      raise_application_error(-20102,
        'Parâmetro p_id é obrigatório em ' || lc_nome_unidade);
    END IF;

    IF p_forcar_update NOT IN ('Y', 'N') THEN
      raise_application_error(-20103,
        'p_forcar_update deve ser Y ou N em ' || lc_nome_unidade);
    END IF;

    -- Verifica existência (NO_DATA_FOUND tratado embaixo)
    SELECT status INTO l_status_atual
      FROM registros
     WHERE id = p_id;

    -- Valida estado consistente
    validar_estado_registro(p_id);

    -- No-op se já processado e não está forçando
    IF l_status_atual = gc_status_concluido AND p_forcar_update = 'N' THEN
      registrar_evento(lc_nome_unidade || ': registro ' || p_id || ' já processado, sem ação');
      RETURN;
    END IF;

    -- Operação principal (usa bind variable implícito em PL/SQL)
    UPDATE registros
       SET status         = gc_status_concluido,
           processado_em  = SYSDATE,
           processado_por = USER
     WHERE id = p_id;

    -- Confirma atualização
    IF SQL%ROWCOUNT = 0 THEN
      raise_application_error(-20104,
        'Nenhuma linha atualizada em ' || lc_nome_unidade || ' para ID ' || p_id);
    END IF;

    registrar_evento(lc_nome_unidade || ': registro ' || p_id || ' processado com sucesso');

    COMMIT;

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      raise_application_error(-20101,
        'Registro não encontrado em ' || lc_nome_unidade || ': ID = ' || p_id);
    
    WHEN e_estado_invalido THEN
      ROLLBACK;
      raise_application_error(-20100,
        'Estado inválido em ' || lc_nome_unidade || ' para ID ' || p_id);
    
    WHEN OTHERS THEN
      ROLLBACK;
      registrar_evento(lc_nome_unidade || ': ERRO INESPERADO - ' || SQLERRM);
      raise_application_error(-20999,
        'Erro inesperado em ' || lc_nome_unidade || ': ' || SQLERRM);
  END processar_registro;


  -----------------------------------------------------------------------------
  -- obter_status
  -----------------------------------------------------------------------------
  FUNCTION obter_status (
    p_id IN NUMBER
  ) RETURN VARCHAR2 IS
    l_status VARCHAR2(1);
  BEGIN
    SELECT status INTO l_status
      FROM registros
     WHERE id = p_id;
    
    RETURN l_status;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- Função obter_* retorna NULL para não-encontrado (vs. procedure que faz raise)
      RETURN NULL;
  END obter_status;


  -----------------------------------------------------------------------------
  -- obter_resumo
  -----------------------------------------------------------------------------
  FUNCTION obter_resumo (
    p_data_inicio IN DATE,
    p_data_fim    IN DATE
  ) RETURN r_resumo IS
    lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.obter_resumo';
    r_resultado r_resumo;
  BEGIN
    -- Valida intervalo
    IF p_data_inicio IS NULL OR p_data_fim IS NULL THEN
      raise_application_error(-20102,
        'Datas são obrigatórias em ' || lc_nome_unidade);
    END IF;

    IF p_data_inicio > p_data_fim THEN
      raise_application_error(-20105,
        'Data inicial não pode ser maior que final em ' || lc_nome_unidade);
    END IF;

    -- Coleta agregados em uma única query (eficiente)
    SELECT COUNT(*),
           NVL(SUM(valor), 0),
           MAX(processado_em)
      INTO r_resultado.qtd_total,
           r_resultado.valor_total,
           r_resultado.ultimo_processado
      FROM registros
     WHERE processado_em BETWEEN p_data_inicio AND p_data_fim
       AND status = gc_status_concluido;

    RETURN r_resultado;
  EXCEPTION
    WHEN OTHERS THEN
      raise_application_error(-20999,
        'Erro inesperado em ' || lc_nome_unidade || ': ' || SQLERRM);
  END obter_resumo;


  --============================================================================
  -- Procedures e Functions privadas
  --============================================================================

  -----------------------------------------------------------------------------
  -- validar_estado_registro
  -- Verifica se o registro está em estado que permite processamento.
  -----------------------------------------------------------------------------
  PROCEDURE validar_estado_registro (p_id IN NUMBER) IS
    lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.validar_estado_registro';
    l_estado VARCHAR2(1);
  BEGIN
    SELECT estado INTO l_estado
      FROM registros
     WHERE id = p_id;

    IF l_estado NOT IN (gc_status_pendente, gc_status_ativo) THEN
      RAISE e_estado_invalido;
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE e_nao_encontrado;
  END validar_estado_registro;


  -----------------------------------------------------------------------------
  -- registrar_evento
  -- Registra evento em tabela de log (autonomous transaction para
  -- persistir mesmo se transação principal sofrer rollback).
  -----------------------------------------------------------------------------
  PROCEDURE registrar_evento (p_mensagem IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO log_eventos (criado_em, nome_pacote, mensagem)
    VALUES (SYSTIMESTAMP, gc_nome_pacote, p_mensagem);
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      -- Log de log não deve quebrar fluxo principal
      ROLLBACK;
  END registrar_evento;


END <nome_pacote>_pkg;
/
