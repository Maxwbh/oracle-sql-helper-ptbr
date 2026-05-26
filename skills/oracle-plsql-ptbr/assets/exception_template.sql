--==============================================================================
-- Template: Bloco BEGIN/EXCEPTION padrão para procedures
--
-- Uso: copie este bloco como esqueleto para qualquer procedure nova.
-- Substitua marcadores <...> pelos nomes/lógica reais.
--
-- Padrões aplicados:
--   - lc_nome_unidade CONSTANT compondo nome do package + procedure
--   - Validação de pré-condições (parâmetros)
--   - Exception handler em três níveis: específico → conhecido → catch-all
--   - ROLLBACK explícito antes de re-raise quando houve DML
--   - Mensagens de erro com contexto (lc_nome_unidade) para debugging
--==============================================================================

PROCEDURE <nome_procedure> (
  p_param1 IN <tipo>,
  p_param2 IN <tipo> DEFAULT <valor_default>
) IS
  -- Identificador da unidade para logging (composição package + procedure)
  lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.<nome_procedure>';
  
  -- Variáveis locais
  l_qtd     NUMBER;
  l_status  VARCHAR2(20);
BEGIN
  --==========================================================================
  -- 1. Validação de pré-condições
  --==========================================================================
  
  IF p_param1 IS NULL THEN
    raise_application_error(-20102,
      'Parâmetro p_param1 é obrigatório em ' || lc_nome_unidade);
  END IF;

  --==========================================================================
  -- 2. Validações de negócio (estado do banco)
  --==========================================================================
  
  -- Exemplo: verificar existência de registro relacionado
  SELECT COUNT(*) INTO l_qtd
    FROM tabela_relacionada
   WHERE id = p_param1;
  
  IF l_qtd = 0 THEN
    raise_application_error(-20101,
      'Registro relacionado não existe em ' || lc_nome_unidade || ' para ID ' || p_param1);
  END IF;

  --==========================================================================
  -- 3. Lógica principal
  --==========================================================================
  
  -- Operação principal aqui
  UPDATE tabela_destino
     SET status         = 'PROCESSADO',
         atualizado_em  = SYSDATE,
         atualizado_por = USER
   WHERE id = p_param1;

  -- Verifica que linha foi efetivamente atualizada (defensive)
  IF SQL%ROWCOUNT = 0 THEN
    raise_application_error(-20104,
      'Nenhuma linha afetada em ' || lc_nome_unidade);
  END IF;

  --==========================================================================
  -- 4. Confirma transação
  --==========================================================================
  
  COMMIT;

EXCEPTION
  --==========================================================================
  -- Handlers específicos primeiro (mais específico para mais genérico)
  --==========================================================================
  
  WHEN e_regra_negocio_conhecida THEN
    ROLLBACK;
    -- Re-raise com contexto adicional, preservando código original
    raise_application_error(-20100,
      'Regra de negócio violada em ' || lc_nome_unidade || ': ' || SQLERRM);

  WHEN NO_DATA_FOUND THEN
    -- Tratamento esperado: registro não encontrado
    raise_application_error(-20101,
      'Registro não encontrado em ' || lc_nome_unidade);

  WHEN DUP_VAL_ON_INDEX THEN
    ROLLBACK;
    raise_application_error(-20106,
      'Violação de unicidade em ' || lc_nome_unidade || ': ' || SQLERRM);

  --==========================================================================
  -- Catch-all por último — sempre presente, sempre com ROLLBACK + raise
  --==========================================================================
  
  WHEN OTHERS THEN
    ROLLBACK;
    raise_application_error(-20999,
      'Erro inesperado em ' || lc_nome_unidade || ': ' || SQLERRM);
END <nome_procedure>;
