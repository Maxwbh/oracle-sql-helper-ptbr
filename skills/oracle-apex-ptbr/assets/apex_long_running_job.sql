--==============================================================================
-- Template: APEX Long-Running Jobs
--
-- Cenário: processo PL/SQL demora mais que o timeout do navegador (30-60s).
-- Solução: rodar em background, retornar imediatamente, polling via AJAX
--          para mostrar progresso ao usuário.
--
-- Versão: APEX 24.2
--
-- Duas abordagens cobertas:
--   1. APEX_BACKGROUND_PROCESS (APEX 21.2+) — usa Scheduler internamente,
--                                              integrado com APEX session
--   2. DBMS_SCHEDULER + tabela de status — funciona em qualquer versão,
--                                          mais flexível
--==============================================================================


--==============================================================================
-- ABORDAGEM 1: APEX_BACKGROUND_PROCESS (recomendado em 24.2)
--==============================================================================

-- A. Criar tabela de status (pode ser compartilhada entre todos jobs do APEX)
CREATE TABLE app_status_job (
    id_job          VARCHAR2(50) PRIMARY KEY,
    sessao_apex    NUMBER,
    usuario_apex       VARCHAR2(100),
    nome_job        VARCHAR2(100),
    status          VARCHAR2(20)  CHECK (status IN ('PENDENTE', 'EXECUTANDO', 'CONCLUIDO', 'FALHOU')),
    progresso_pct    NUMBER(5,2)   DEFAULT 0,
    mensagem_progresso    VARCHAR2(500),
    result          CLOB,
    mensagem_erro   VARCHAR2(4000),
    iniciado_em      TIMESTAMP,
    finalizado_em     TIMESTAMP,
    criado_em      TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE INDEX idx_app_job_status_session ON app_status_job(sessao_apex);
CREATE INDEX idx_app_job_status_status ON app_status_job(status);


-- B. Package que executa o trabalho pesado
CREATE OR REPLACE PACKAGE BODY heavy_job_pkg AS
  
  gc_nome_pacote CONSTANT VARCHAR2(30) := 'HEAVY_JOB_PKG';

  -----------------------------------------------------------------------------
  -- executar_arquivamento_faturas
  -- Procedure pesada que será chamada em background.
  -----------------------------------------------------------------------------
  PROCEDURE executar_arquivamento_faturas (
    p_id_job      IN VARCHAR2,
    p_data_corte IN DATE
  ) IS
    lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.executar_arquivamento_faturas';
    l_scope      VARCHAR2(60) := lc_nome_unidade;
    l_params     logger.tab_param;
    l_total      NUMBER;
    l_processados  NUMBER := 0;
    l_tamanho_chunk CONSTANT PLS_INTEGER := 1000;
  BEGIN
    logger.append_param(l_params, 'id_job', p_id_job);
    logger.append_param(l_params, 'data_corte', p_data_corte);
    
    -- Atualiza status: iniciando
    UPDATE app_status_job
       SET status = 'EXECUTANDO',
           iniciado_em = SYSTIMESTAMP,
           mensagem_progresso = 'Iniciando arquivamento'
     WHERE id_job = p_id_job;
    COMMIT;

    -- Conta total para calcular progresso
    SELECT COUNT(*) INTO l_total
      FROM faturas
     WHERE data_emissao < p_data_corte
       AND status = 'PAGO';

    logger.log('Job iniciado. Total a processar: ' || l_total, l_scope, NULL, l_params);

    -- Processamento em chunks com atualização de progresso
    DECLARE
      CURSOR co_faturas IS
        SELECT id, id_cliente, valor, data_emissao
          FROM faturas
         WHERE data_emissao < p_data_corte
           AND status = 'PAGO';
      
      TYPE t_lista_faturas IS TABLE OF co_faturas%ROWTYPE;
      l_faturas t_lista_faturas;
    BEGIN
      OPEN co_faturas;
      LOOP
        FETCH co_faturas BULK COLLECT INTO l_faturas LIMIT l_tamanho_chunk;
        EXIT WHEN l_faturas.COUNT = 0;

        -- Move para arquivo
        FORALL i IN l_faturas.FIRST..l_faturas.LAST
          INSERT INTO arquivo_faturas (id, id_cliente, valor, data_emissao, arquivado_em)
          VALUES (l_faturas(i).id, l_faturas(i).id_cliente, l_faturas(i).valor,
                  l_faturas(i).data_emissao, SYSDATE);

        FORALL i IN l_faturas.FIRST..l_faturas.LAST
          DELETE FROM faturas WHERE id = l_faturas(i).id;

        l_processados := l_processados + l_faturas.COUNT;

        -- Atualiza progresso (autonomous transaction para visibilidade imediata)
        atualizar_progresso(
          p_id_job      => p_id_job,
          p_progresso_pct => ROUND((l_processados / l_total) * 100, 2),
          p_mensagem_progresso => l_processados || ' de ' || l_total || ' faturas arquivadas'
        );

        COMMIT;
      END LOOP;
      CLOSE co_faturas;
    END;

    -- Marca como concluído
    UPDATE app_status_job
       SET status        = 'CONCLUIDO',
           progresso_pct  = 100,
           mensagem_progresso  = 'Arquivamento concluído',
           result        = l_processados || ' faturas arquivadas',
           finalizado_em   = SYSTIMESTAMP
     WHERE id_job = p_id_job;
    COMMIT;

    logger.log('Job concluído. Processadas: ' || l_processados, l_scope, NULL, l_params);

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      
      -- Marca como falhado para o frontend saber
      UPDATE app_status_job
         SET status        = 'FALHOU',
             mensagem_erro = SUBSTR(SQLERRM, 1, 4000),
             finalizado_em   = SYSTIMESTAMP
       WHERE id_job = p_id_job;
      COMMIT;
      
      logger.log_error('Falha em ' || lc_nome_unidade, l_scope, NULL, l_params);
      -- NÃO re-raise: job está em background, raise não vai para o usuário
  END executar_arquivamento_faturas;


  -----------------------------------------------------------------------------
  -- atualizar_progresso (autonomous transaction)
  -----------------------------------------------------------------------------
  PROCEDURE atualizar_progresso (
    p_id_job       IN VARCHAR2,
    p_progresso_pct IN NUMBER,
    p_mensagem_progresso IN VARCHAR2
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    UPDATE app_status_job
       SET progresso_pct = p_progresso_pct,
           mensagem_progresso = p_mensagem_progresso
     WHERE id_job = p_id_job;
    COMMIT;
  END atualizar_progresso;

END heavy_job_pkg;
/


-- C. APEX Page Process (chamado quando usuário clica "Iniciar Arquivamento")
DECLARE
  l_id_job VARCHAR2(50);
BEGIN
  -- Gera ID único do job
  l_id_job := 'archive_' || :APP_SESSION || '_' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');

  -- Cria registro de status
  INSERT INTO app_status_job (id_job, sessao_apex, usuario_apex, nome_job, status)
  VALUES (l_id_job, :APP_SESSION, :APP_USER, 'arquivar_faturas', 'PENDENTE');
  COMMIT;

  -- Dispara em background usando APEX_BACKGROUND_PROCESS (APEX 21.2+)
  APEX_BACKGROUND_PROCESS.execute(
    p_application_id  => :APP_ID,
    p_callback        => 'BEGIN heavy_job_pkg.executar_arquivamento_faturas(p_id_job => '''
                          || l_id_job || ''', p_data_corte => TO_DATE(''' 
                          || TO_CHAR(:P10_DATE_CUTOFF, 'YYYY-MM-DD')
                          || ''', ''YYYY-MM-DD'')); END;'
  );

  -- Devolve id_job para o cliente via item
  :P10_ID_JOB := l_id_job;
  
  -- Mensagem inicial
  APEX_APPLICATION.g_print_success_message := 
    '<span class="t-Icon icon-check"></span> Arquivamento iniciado em background. ID: ' || l_id_job;
END;


-- D. AJAX Callback para polling do progresso
-- Nome do callback: GET_JOB_STATUS
DECLARE
  l_status app_status_job%ROWTYPE;
BEGIN
  SELECT * INTO l_status
    FROM app_status_job
   WHERE id_job = APEX_APPLICATION.G_X01;

  APEX_JSON.open_object;
  APEX_JSON.write('id_job', l_status.id_job);
  APEX_JSON.write('status', l_status.status);
  APEX_JSON.write('progresso_pct', l_status.progresso_pct);
  APEX_JSON.write('mensagem_progresso', l_status.mensagem_progresso);
  APEX_JSON.write('result', l_status.result);
  APEX_JSON.write('mensagem_erro', l_status.mensagem_erro);
  APEX_JSON.close_object;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Job não encontrado');
    APEX_JSON.close_object;
END;


-- E. JavaScript no client — polling com setInterval
/*
// Inicia polling após disparar o job
function startJobPolling(jobId) {
  var pollInterval = setInterval(function() {
    apex.server.process('GET_JOB_STATUS', {
      x01: jobId
    }, {
      dataType: 'json',
      success: function(data) {
        if (data.error) {
          clearInterval(pollInterval);
          apex.message.alert('Erro: ' + data.error);
          return;
        }

        // Atualiza barra de progresso
        $('#progress-bar').css('width', data.progresso_pct + '%');
        $('#progress-text').text(data.mensagem_progresso);

        // Verifica se concluiu
        if (data.status === 'CONCLUIDO') {
          clearInterval(pollInterval);
          apex.message.showPageSuccess('Concluído: ' + data.result);
          apex.region('lista_invoices').refresh();
        } else if (data.status === 'FALHOU') {
          clearInterval(pollInterval);
          apex.message.alert('Falha: ' + data.mensagem_erro);
        }
      },
      error: function() {
        clearInterval(pollInterval);
        apex.message.alert('Erro ao consultar status');
      }
    });
  }, 2000);  // poll a cada 2 segundos
}

// Quando o Page Process retorna o id_job, dispara polling
var jobId = $v('P10_ID_JOB');
if (jobId) {
  startJobPolling(jobId);
}
*/


--==============================================================================
-- ABORDAGEM 2: DBMS_SCHEDULER puro (mais flexível, funciona em qualquer versão)
--==============================================================================

-- Útil quando:
--   - Job precisa repetir (cron-like)
--   - Job pode rodar fora de sessão APEX
--   - Quer separar autenticação/contexto

-- A. Cria job único (one-shot)
DECLARE
  l_id_job VARCHAR2(50);
BEGIN
  l_id_job := 'archive_' || :APP_SESSION || '_' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');

  INSERT INTO app_status_job (id_job, sessao_apex, usuario_apex, nome_job, status)
  VALUES (l_id_job, :APP_SESSION, :APP_USER, 'arquivar_faturas', 'PENDENTE');
  COMMIT;

  DBMS_SCHEDULER.create_job(
    nome_job        => 'JOB_' || l_id_job,
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN heavy_job_pkg.executar_arquivamento_faturas('''
                       || l_id_job || ''', TO_DATE(''' 
                       || TO_CHAR(:P10_DATE_CUTOFF, 'YYYY-MM-DD') 
                       || ''', ''YYYY-MM-DD'')); END;',
    start_date      => SYSTIMESTAMP,
    enabled         => TRUE,
    auto_drop       => TRUE,    -- remove job após execução
    comments        => 'APEX archive job para session ' || :APP_SESSION
  );

  :P10_ID_JOB := l_id_job;
END;


-- B. Job recorrente (ex: limpeza diária às 3h)
BEGIN
  DBMS_SCHEDULER.create_job(
    nome_job        => 'MS_LIMPEZA_DIARIA',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN limpeza_pkg.executar_limpeza_diaria; END;',
    start_date      => TRUNC(SYSDATE) + 1 + 3/24,  -- amanhã 03:00
    repeat_interval => 'FREQ=DAILY; BYHOUR=3; BYMINUTE=0',
    enabled         => TRUE,
    comments        => 'Limpeza diária de dados temporários'
  );
END;
/


-- C. Monitorar jobs scheduler
SELECT nome_job, state, last_start_date, last_run_duration, run_count, failure_count
  FROM user_scheduler_jobs
 WHERE nome_job LIKE 'MS_%'
 ORDER BY last_start_date DESC NULLS LAST;

-- Histórico de execuções
SELECT log_date, status, run_duration, additional_info
  FROM user_scheduler_job_run_details
 WHERE nome_job = 'MS_LIMPEZA_DIARIA'
 ORDER BY log_date DESC
 FETCH FIRST 10 ROWS ONLY;


-- D. Cancelar / desabilitar job
EXEC DBMS_SCHEDULER.stop_job('JOB_archive_12345');
EXEC DBMS_SCHEDULER.disable('MS_LIMPEZA_DIARIA');
EXEC DBMS_SCHEDULER.drop_job('MS_LIMPEZA_DIARIA');


--==============================================================================
-- COMPARAÇÃO das abordagens
--==============================================================================

/*
APEX_BACKGROUND_PROCESS:
  ✓ Integrado com APEX (session, segurança, debug)
  ✓ Configuração mais simples
  ✓ Visível em APEX_BG_PROCESSES (monitoring nativo)
  ✗ Apenas one-shot (não recorrente)
  ✗ Limitado ao contexto da app APEX
  ✗ Versão APEX 21.2+

DBMS_SCHEDULER:
  ✓ Funciona em qualquer versão Oracle
  ✓ Suporta jobs recorrentes (cron-like)
  ✓ Mais controle (chains, classes, prioridades)
  ✓ Visível via DBA tools de monitoramento
  ✗ Não integra automaticamente com APEX session
  ✗ Configuração mais verbosa

ESCOLHA:
  - Job triggered de página APEX, one-shot, contexto APEX importa → APEX_BACKGROUND_PROCESS
  - Job recorrente, ETL, limpeza, fora de APEX → DBMS_SCHEDULER
  - Em APEX 24.2 (sua versão), APEX_BACKGROUND_PROCESS é o default para jobs APEX
*/


--==============================================================================
-- ANTI-PATTERNS
--==============================================================================

/*
ANTI-PATTERN 1: Tentar fazer job pesado em Page Process síncrono

  -- RUIM: navegador faz timeout em 30-60s
  -- Page Process roda inline, browser espera...
  BEGIN
    FOR i IN 1..1000000 LOOP
      heavy_processing(...);
    END LOOP;
  END;

  -- BOM: dispara em background, polling de status

ANTI-PATTERN 2: Job sem tabela de status
  
  -- Sem tabela de status, frontend não tem como saber progresso.
  -- Sempre crie tabela de status e atualize via autonomous transaction.

ANTI-PATTERN 3: Polling sem clearInterval em erro

  -- Poll continua para sempre se primeira requisição falhar.
  -- Sempre clearInterval em error/COMPLETED/FAILED.

ANTI-PATTERN 4: Confiar em ROW LOCK para garantir único job rodando

  -- RUIM: SELECT FOR UPDATE não previne dois APEX_BACKGROUND_PROCESS
  --       sendo enfileirados.
  -- BOM: usar status em tabela com constraint/check antes de criar
*/
