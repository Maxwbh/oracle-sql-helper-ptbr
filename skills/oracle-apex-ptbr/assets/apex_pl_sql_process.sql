--==============================================================================
-- Template: APEX PL/SQL Process e AJAX Callback
--
-- Cobre dois cenários:
--   1. Page Process (executa no Submit/Load)
--   2. AJAX Callback (chamado via apex.server.process do JavaScript)
--==============================================================================


--==============================================================================
-- 1. PAGE PROCESS — Tipo: Execute PL/SQL Code
--
-- Configuração:
--   Type:                   Execute PL/SQL Code
--   Point:                  Processing — After Submit
--   Server-side Condition:  Type: Request = Expression 1
--                          Expression 1: SALVAR_FATURA
--==============================================================================

DECLARE
  l_nome_unidade CONSTANT VARCHAR2(60) := 'PAGINA_10_PROC_SALVAR_FATURA';
  l_id_fatura   NUMBER;
  l_eh_novo       BOOLEAN;
BEGIN
  -- Determina se é novo ou edição
  l_eh_novo := (:P10_ID_FATURA IS NULL);
  
  IF l_eh_novo THEN
    -- INSERT
    INSERT INTO faturas (
      id_cliente,
      numero_fatura,
      data_emissao,
      data_vencimento,
      valor,
      status,
      criado_em,
      criado_por
    ) VALUES (
      :P10_ID_CLIENTE,
      :P10_NUMERO_FATURA,
      TO_DATE(:P10_DATA_EMISSAO, 'DD/MM/YYYY'),
      TO_DATE(:P10_DATA_VENCIMENTO, 'DD/MM/YYYY'),
      TO_NUMBER(:P10_VALOR, '999G999G999D99', 'NLS_NUMERIC_CHARACTERS=,.'),
      'PENDENTE',
      SYSDATE,
      :APP_USER
    ) RETURNING id INTO l_id_fatura;
    
    :P10_ID_FATURA := l_id_fatura;
    
    -- Mensagem de sucesso (mostrada após reload pela APEX)
    APEX_APPLICATION.g_print_success_message := 
      '<span class="t-Icon icon-check"></span> Fatura criada com sucesso (ID ' || l_id_fatura || ')';
  ELSE
    -- UPDATE
    UPDATE faturas
       SET id_cliente    = :P10_ID_CLIENTE,
           numero_fatura = :P10_NUMERO_FATURA,
           data_emissao   = TO_DATE(:P10_DATA_EMISSAO, 'DD/MM/YYYY'),
           data_vencimento       = TO_DATE(:P10_DATA_VENCIMENTO, 'DD/MM/YYYY'),
           valor         = TO_NUMBER(:P10_VALOR, '999G999G999D99', 
                                      'NLS_NUMERIC_CHARACTERS=,.'),
           atualizado_em     = SYSDATE,
           atualizado_por     = :APP_USER
     WHERE id = :P10_ID_FATURA;

    IF SQL%ROWCOUNT = 0 THEN
      raise_application_error(-20101,
        'Fatura ' || :P10_ID_FATURA || ' não encontrada para atualização');
    END IF;

    APEX_APPLICATION.g_print_success_message := 
      '<span class="t-Icon icon-check"></span> Fatura atualizada com sucesso';
  END IF;
  
  -- COMMIT é gerenciado pela APEX (não comite explicitamente em Page Process)
  
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    -- Mensagem amigável para violação de unicidade
    APEX_ERROR.add_error(
      p_mensagem          => 'Já existe uma fatura com este número.',
      p_display_location => APEX_ERROR.c_inline_with_field_and_notif,
      p_page_item_name   => 'P10_NUMERO_FATURA'
    );
  
  WHEN OTHERS THEN
    APEX_DEBUG.error('Erro em ' || l_nome_unidade || ': ' || SQLERRM);
    APEX_ERROR.add_error(
      p_mensagem          => 'Erro ao salvar fatura: ' || SQLERRM,
      p_display_location => APEX_ERROR.c_inline_in_notification
    );
END;


--==============================================================================
-- 2. AJAX CALLBACK — Tipo: AJAX Callback
--
-- Configuração:
--   Object Type:          AJAX Callback
--   Name:                 GET_CUSTOMER_BALANCE
--   Source Type:          PL/SQL
--
-- Chamada do JavaScript (no client):
--
--   apex.server.process('GET_CUSTOMER_BALANCE', {
--     x01: $v('P10_ID_CLIENTE')
--   }, {
--     dataType: 'json',
--     success: function(data) {
--       if (data.error) {
--         apex.message.alert('Erro: ' + data.error);
--         return;
--       }
--       $('#balance-display').text(data.balance_formatted);
--     }
--   });
--==============================================================================

DECLARE
  l_nome_unidade  CONSTANT VARCHAR2(60) := 'AJAX_GET_CUSTOMER_BALANCE';
  l_saldo    NUMBER;
  l_cliente   clientes%ROWTYPE;
BEGIN
  -- Valida parâmetro recebido via X01
  IF APEX_APPLICATION.G_X01 IS NULL THEN
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'ID do cliente é obrigatório');
    APEX_JSON.close_object;
    RETURN;
  END IF;

  -- Busca dados do cliente
  SELECT * INTO l_cliente
    FROM clientes
   WHERE id = APEX_APPLICATION.G_X01;

  -- Calcula balance (saldo pendente)
  SELECT NVL(SUM(valor), 0)
    INTO l_saldo
    FROM faturas
   WHERE id_cliente = l_cliente.id
     AND status IN ('PENDENTE', 'VENCIDO');

  -- Retorna JSON estruturado
  APEX_JSON.open_object;
  APEX_JSON.write('id_cliente', l_cliente.id);
  APEX_JSON.write('nome_cliente', l_cliente.nome);
  APEX_JSON.write('balance', l_saldo);
  APEX_JSON.write('balance_formatted', 
    'R$ ' || TO_CHAR(l_saldo, 'FM999G999G999D90', 'NLS_NUMERIC_CHARACTERS=,.'));
  APEX_JSON.close_object;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Cliente não encontrado');
    APEX_JSON.close_object;
  
  WHEN OTHERS THEN
    APEX_DEBUG.error('Erro em ' || l_nome_unidade || ': ' || SQLERRM);
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Erro inesperado: ' || SQLERRM);
    APEX_JSON.close_object;
END;


--==============================================================================
-- 3. VALIDATION — Tipo: PL/SQL Function (returning Error Text)
--
-- Configuração:
--   Type:                 PL/SQL Function (returning Error Text)
--   Validation Point:     After Submit
--   Always Execute:       No
--   Server-side Condition: Type: Request = Expression 1
--                         Expression 1: SALVAR_FATURA
--==============================================================================

DECLARE
  l_qtd NUMBER;
BEGIN
  -- Validação 1: número da fatura único
  SELECT COUNT(*) INTO l_qtd
    FROM faturas
   WHERE numero_fatura = :P10_NUMERO_FATURA
     AND id <> NVL(:P10_ID_FATURA, 0);  -- exclui o próprio em edição
  
  IF l_qtd > 0 THEN
    RETURN 'Já existe uma fatura com este número.';
  END IF;
  
  -- Validação 2: data de vencimento posterior à emissão
  IF TO_DATE(:P10_DATA_VENCIMENTO, 'DD/MM/YYYY') < TO_DATE(:P10_DATA_EMISSAO, 'DD/MM/YYYY') THEN
    RETURN 'Data de vencimento não pode ser anterior à data de emissão.';
  END IF;
  
  -- Validação 3: valor positivo
  IF TO_NUMBER(:P10_VALOR, '999G999G999D99', 'NLS_NUMERIC_CHARACTERS=,.') <= 0 THEN
    RETURN 'Valor da fatura deve ser maior que zero.';
  END IF;
  
  -- Validação 4: cliente está ativo
  SELECT COUNT(*) INTO l_qtd
    FROM clientes
   WHERE id = :P10_ID_CLIENTE
     AND ativo = 'Y';
  
  IF l_qtd = 0 THEN
    RETURN 'Cliente selecionado não está ativo.';
  END IF;
  
  -- Tudo OK
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RETURN 'Erro ao validar dados: ' || SQLERRM;
END;


--==============================================================================
-- 4. COMPUTATION — Tipo: PL/SQL Expression
--
-- Configuração:
--   Item:                 P10_NUMERO_FATURA
--   Computation Point:    Before Header
--   Computation Type:     PL/SQL Expression
--   Server-side Condition: P10_ID_FATURA IS NULL  (só executa em "novo")
--==============================================================================

-- PL/SQL Expression (uma linha):
TO_CHAR(SYSDATE, 'YYYY') || '-' || LPAD(faturas_seq.NEXTVAL, 6, '0')

-- Resultado: '2024-000123'


--==============================================================================
-- Convenções importantes
--==============================================================================

/*
1. Mensagens em PT-BR para o usuário final (UX)
   - APEX_ERROR.add_error e APEX_APPLICATION.g_print_success_message

2. Logs/debug em PT-BR também
   - APEX_DEBUG.error / APEX_DEBUG.message
   - Visíveis em Debug View do APEX

3. NÃO comite explicitamente em Page Process
   - APEX gerencia transação
   - COMMIT explícito quebra fluxo "Branch on success/error"

4. AJAX Callback DEVE retornar JSON consistente
   - Sempre retorna objeto, mesmo em erro
   - Use propriedade "error" para sinalizar falha
   - JS deve checar data.error antes de processar resultado

5. Nunca confie em items hidden sem Value Protected
   - Cliente malicioso pode alterar via DevTools
   - Re-valide IDs no server-side
*/
