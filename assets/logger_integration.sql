--==============================================================================
-- Template: Integração com Logger (OraOpenSource)
--
-- Logger é o framework padrão de logging para PL/SQL produção:
-- https://github.com/OraOpenSource/Logger
--
-- Este template assume Logger instalado no schema LOGGER (padrão).
-- Substitua pelo schema usado na instalação local se diferente.
--
-- Vantagens sobre DBMS_OUTPUT:
--   - Persiste em tabela LOGGER_LOGS (auditável, queryable)
--   - Níveis configuráveis (DEBUG/INFO/WARN/ERROR/PERMANENT)
--   - Captura context: timestamp, user, module, action, call stack
--   - Performance: pode ser desabilitado em produção sem alterar código
--   - Suporta named scopes para rastrear fluxo
--==============================================================================


--==============================================================================
-- 1. Instalação (executar UMA vez no banco, como DBA)
--==============================================================================

/*
1. Baixar release: https://github.com/OraOpenSource/Logger/releases
2. Descompactar
3. Conectar como DBA, executar:
   @logger_install.sql LOGGER LOGGER USERS

   Parâmetros:
     - LOGGER: schema owner
     - LOGGER: senha
     - USERS: tablespace

4. Conceder execute aos schemas que vão usar:
   GRANT EXECUTE ON logger TO app_owner;
   GRANT SELECT ON logger.logger_logs_5_min TO app_owner;

5. Verificar instalação:
   SELECT logger.version FROM dual;
*/


--==============================================================================
-- 2. Configurar nível de log do schema
--==============================================================================

-- Níveis (do mais ao menos verboso):
--   DEBUG       → log tudo (use em desenvolvimento)
--   INFORMATION → INFO + WARN + ERROR + PERMANENT (produção típica)
--   WARNING     → WARN + ERROR + PERMANENT
--   ERROR       → só ERROR + PERMANENT
--   OFF         → desabilitado completamente

-- Setar nível para uma sessão de cliente
EXEC LOGGER.set_level('DEBUG', 'APP_DEV');

-- Setar nível default global
EXEC LOGGER.set_level('INFORMATION');

-- Ver configuração atual
SELECT * FROM logger.logger_prefs;


--==============================================================================
-- 3. Padrão básico de uso em procedure PL/SQL
--==============================================================================

CREATE OR REPLACE PACKAGE BODY pagamento_pkg AS
  
  gc_nome_pacote CONSTANT VARCHAR2(30) := 'PAGAMENTO_PKG';

  PROCEDURE processar_pagamento (
    p_id_fatura IN NUMBER,
    p_valor     IN NUMBER
  ) IS
    lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.processar_pagamento';
    
    -- Scope para Logger: agrupa logs do mesmo fluxo
    l_scope          VARCHAR2(60) := lc_nome_unidade;
    l_params         logger.tab_param;
    l_status_fatura  VARCHAR2(20);
  BEGIN
    -- Adiciona parâmetros ao log para debugging
    logger.append_param(l_params, 'p_id_fatura', p_id_fatura);
    logger.append_param(l_params, 'p_valor', p_valor);
    
    -- INFO: marco de entrada na procedure
    logger.log('Iniciando processamento', l_scope, NULL, l_params);

    -- Validação
    SELECT status INTO l_status_fatura
      FROM faturas
     WHERE id = p_id_fatura;

    IF l_status_fatura = 'PAGO' THEN
      -- WARN: situação anômala mas não fatal
      logger.log_warn(
        'Tentativa de pagamento em fatura já paga: ' || p_id_fatura,
        l_scope, NULL, l_params
      );
      raise_application_error(-20100, 'Fatura ' || p_id_fatura || ' já paga');
    END IF;

    -- Processamento
    UPDATE faturas
       SET status     = 'PAGO',
           pago_em    = SYSDATE,
           valor_pago = p_valor
     WHERE id = p_id_fatura;

    -- DEBUG: detalhes que só importam em troubleshoot
    logger.log_information(
      'Fatura atualizada. Linhas afetadas: ' || SQL%ROWCOUNT,
      l_scope
    );

    COMMIT;

    -- INFO: marco de sucesso
    logger.log('Pagamento processado com sucesso', l_scope, NULL, l_params);

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- Logger captura SQLERRM automaticamente em log_error
      logger.log_error(
        'Fatura não encontrada: ' || p_id_fatura,
        l_scope, NULL, l_params
      );
      raise_application_error(-20101, 'Fatura ' || p_id_fatura || ' não encontrada');
    
    WHEN OTHERS THEN
      ROLLBACK;
      -- log_error captura: SQLERRM, SQLCODE, call stack, error stack
      logger.log_error(
        'Erro inesperado em ' || lc_nome_unidade,
        l_scope, NULL, l_params
      );
      raise_application_error(-20999, 'Erro: ' || SQLERRM);
  END processar_pagamento;

END pagamento_pkg;
/


--==============================================================================
-- 4. Funções principais do Logger
--==============================================================================

/*
LOGGER.log(p_text, p_scope, p_extra, p_params)
  - Log nível INFO (padrão em produção)
  
LOGGER.log_information(p_text, p_scope, p_extra, p_params)
  - Idêntico a logger.log

LOGGER.log_warning(p_text, p_scope, p_extra, p_params)
  - Nível WARN — situações anômalas mas não fatais

LOGGER.log_error(p_text, p_scope, p_extra, p_params)
  - Nível ERROR — captura automaticamente:
      * SQLERRM, SQLCODE
      * Call stack (DBMS_UTILITY.format_call_stack)
      * Error stack (DBMS_UTILITY.format_error_stack)
      * Backtrace (DBMS_UTILITY.format_error_backtrace)

LOGGER.log_permanent(p_text, p_scope, p_extra, p_params)
  - Nível PERMANENT — sempre logado, mesmo em level OFF
  - Use para eventos críticos de auditoria (login admin, transações financeiras)

PARÂMETROS:
  p_text   VARCHAR2  - Mensagem
  p_scope  VARCHAR2  - Identificador do fluxo (use lc_nome_unidade)
  p_extra  CLOB      - Detalhes longos (JSON, XML, payloads)
  p_params logger.tab_param - Lista de parâmetros (key/value)
*/


--==============================================================================
-- 5. Logger.append_param — anexar parâmetros estruturados
--==============================================================================

DECLARE
  l_params logger.tab_param;
BEGIN
  -- Tipos primitivos
  logger.append_param(l_params, 'id_fatura', 12345);
  logger.append_param(l_params, 'nome_cliente', 'João Silva');
  logger.append_param(l_params, 'valor', 1500.50);
  logger.append_param(l_params, 'esta_vencida', TRUE);
  logger.append_param(l_params, 'data_vencimento', SYSDATE);

  logger.log('Processando fatura', 'TEST.exemplo', NULL, l_params);
END;
/

-- No log fica registrado:
--   id_fatura: 12345
--   nome_cliente: João Silva
--   valor: 1500.5
--   esta_vencida: TRUE
--   data_vencimento: 30/04/2024 14:30:00


--==============================================================================
-- 6. Logger em ORDS handlers
--==============================================================================

/*
Em ORDS, o Logger captura automaticamente o usuário REST autenticado.
Use scope = 'API.<recurso>.<método>' para filtragem fácil.
*/

ORDS.define_handler(
  p_module_name    => 'faturas.v1',
  p_pattern        => 'fatura/:id',
  p_method         => 'PUT',
  p_source_type    => ORDS.source_type_plsql,
  p_source         => q'[
DECLARE
  l_scope  VARCHAR2(60) := 'API.fatura.PUT';
  l_params logger.tab_param;
BEGIN
  logger.append_param(l_params, 'id', :id);
  logger.append_param(l_params, 'valor', :valor);
  logger.log('PUT /fatura/' || :id, l_scope, NULL, l_params);

  UPDATE faturas SET valor = :valor WHERE id = :id;

  IF SQL%ROWCOUNT = 0 THEN
    logger.log_warning('Fatura não encontrada: ' || :id, l_scope, NULL, l_params);
    OWA_UTIL.status_line(404);
    OWA_UTIL.http_header_close;
    RETURN;
  END IF;

  COMMIT;
  
  logger.log('Atualizado com sucesso', l_scope, NULL, l_params);
  OWA_UTIL.status_line(200);
  OWA_UTIL.http_header_close;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    logger.log_error('Erro em ' || l_scope, l_scope, NULL, l_params);
    OWA_UTIL.status_line(500);
    OWA_UTIL.http_header_close;
END;
]'
);


--==============================================================================
-- 7. Logger em APEX
--==============================================================================

-- Page Process (Submit)
DECLARE
  l_scope  VARCHAR2(60) := 'APEX.PAGINA10.PROC_SALVAR';
  l_params logger.tab_param;
BEGIN
  logger.append_param(l_params, 'id_fatura', :P10_ID_FATURA);
  logger.append_param(l_params, 'usuario_apex', :APP_USER);
  logger.append_param(l_params, 'sessao_apex', :APP_SESSION);
  
  logger.log('Início processamento save', l_scope, NULL, l_params);

  -- Lógica do save...
  
  logger.log('Save concluído', l_scope);
EXCEPTION
  WHEN OTHERS THEN
    logger.log_error('Erro em save', l_scope, NULL, l_params);
    APEX_ERROR.add_error(
      p_message          => 'Erro ao salvar — verifique logs',
      p_display_location => APEX_ERROR.c_inline_in_notification
    );
END;


--==============================================================================
-- 8. Consultar logs
--==============================================================================

-- Logs dos últimos 5 minutos (view otimizada)
SELECT time_stamp, logger_level, scope, text, extra
  FROM logger.logger_logs_5_min
 WHERE scope LIKE 'PAGAMENTO_PKG.%'
 ORDER BY time_stamp DESC;

-- Logs com filtro mais amplo
SELECT id, time_stamp, logger_level, scope, text,
       call_stack, error_stack
  FROM logger.logger_logs
 WHERE time_stamp > SYSDATE - 1/24  -- última hora
   AND logger_level = 'ERROR'
 ORDER BY time_stamp DESC;

-- Logs de uma sessão específica (rastrear fluxo)
SELECT time_stamp, logger_level, scope, text
  FROM logger.logger_logs
 WHERE client_identifier = 'APP_USUARIO_123'
   AND time_stamp > SYSDATE - 1
 ORDER BY time_stamp;


--==============================================================================
-- 9. Manutenção
--==============================================================================

-- Purgar logs antigos (Logger não auto-purga)
EXEC LOGGER.purge('APP_OWNER', '7'); -- remove logs de APP_OWNER > 7 dias

-- Purgar tudo do schema atual
EXEC LOGGER.purge;

-- Estatísticas
SELECT logger_level, COUNT(*) AS total
  FROM logger.logger_logs
 WHERE time_stamp > SYSDATE - 1
 GROUP BY logger_level
 ORDER BY total DESC;


--==============================================================================
-- 10. Anti-patterns
--==============================================================================

/*
ANTI-PATTERN 1: DBMS_OUTPUT em produção

  -- RUIM: nada captura, perde informação
  DBMS_OUTPUT.put_line('Iniciando processo');

  -- BOM:
  logger.log('Iniciando processo', l_scope);


ANTI-PATTERN 2: Log sem scope

  -- RUIM: impossível filtrar logs por fluxo
  logger.log('Erro');

  -- BOM:
  logger.log('Erro processando fatura', 'PAGAMENTO_PKG.processar_pagamento');


ANTI-PATTERN 3: Logar dados sensíveis

  -- RUIM: senhas, CPF completo, dados de cartão em log
  logger.append_param(l_params, 'senha', p_senha);
  logger.append_param(l_params, 'cpf', p_cpf);

  -- BOM: ofuscar
  logger.append_param(l_params, 'cpf_ultimos4', SUBSTR(p_cpf, -4));
  -- senha NUNCA logar


ANTI-PATTERN 4: Log_information em loop pesado

  -- RUIM: enche tabela em produção
  FOR i IN 1..100000 LOOP
    logger.log_information('Processando linha ' || i, l_scope);
    ...
  END LOOP;

  -- BOM: logar marcos a cada N iterações ou só sumário
  IF MOD(i, 1000) = 0 THEN
    logger.log_information('Processadas ' || i || ' linhas', l_scope);
  END IF;


ANTI-PATTERN 5: Não usar log_permanent para eventos críticos

  -- Eventos de auditoria DEVEM persistir mesmo com level=OFF:
  --   - Login/logout admin
  --   - Mudança de privilégio
  --   - Transação financeira > limite
  --   - Cancelamento de operação irreversível
  
  logger.log_permanent('Admin login: ' || p_usuario, l_scope);
*/
