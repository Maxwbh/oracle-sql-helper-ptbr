--==============================================================================
-- Package SPEC: <NOME_PACOTE>_PKG
-- 
-- Descrição: <descrição em uma linha do propósito do package>
--
-- Padrões aplicados:
--   - Trivadis Guidelines 4.4 (naming conventions)
--   - Documentação Javadoc-like nos métodos públicos
--   - Tipos públicos antes de constantes; constantes antes de exceptions;
--     exceptions antes de procedures/functions (ordem canônica)
--
-- Histórico:
--   <DATA>  <AUTOR>  Criação inicial
--==============================================================================

CREATE OR REPLACE PACKAGE <nome_pacote>_pkg AS

  --============================================================================
  -- Tipos públicos
  --============================================================================
  
  -- Tipo coleção de IDs (usado em operações bulk)
  TYPE t_lista_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

  -- Record para retorno estruturado (exemplo, ajustar conforme domínio)
  TYPE r_resumo IS RECORD (
    qtd_total       NUMBER,
    valor_total     NUMBER,
    ultimo_processado DATE
  );

  --============================================================================
  -- Constantes públicas (raras — geralmente são privadas no body)
  --============================================================================
  
  -- Limite máximo permitido pelo regulamento aplicável
  gc_max_registros CONSTANT PLS_INTEGER := 1000;

  --============================================================================
  -- Exceptions públicas (callers podem capturar especificamente)
  --============================================================================
  
  -- Lançada quando estado do registro não permite a operação
  e_estado_invalido EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_estado_invalido, -20100);

  -- Lançada quando registro requerido não existe
  e_nao_encontrado EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_nao_encontrado, -20101);

  --============================================================================
  -- Procedures e Functions públicas
  --============================================================================

  /**
   * <Descrição em uma linha do que o método faz.>
   *
   * <Parágrafo opcional com detalhes: regras de negócio importantes,
   * efeitos colaterais, dependências externas.>
   *
   * @param p_id              <descrição do parâmetro>
   * @param p_forcar_update   <descrição>; default 'N'
   *
   * @raises e_nao_encontrado   Se o registro não existe
   * @raises e_estado_invalido  Se o registro está em estado incompatível
   */
  PROCEDURE processar_registro (
    p_id            IN NUMBER,
    p_forcar_update IN VARCHAR2 DEFAULT 'N'
  );

  /**
   * Retorna o status atual do registro.
   *
   * @param p_id ID do registro
   * @return Código de status (CHAR(1)). NULL se não encontrado.
   */
  FUNCTION obter_status (
    p_id IN NUMBER
  ) RETURN VARCHAR2;

  /**
   * Retorna sumário consolidado para o período.
   *
   * @param p_data_inicio Data inicial (inclusive)
   * @param p_data_fim    Data final (inclusive)
   * @return Record com qtd_total, valor_total, ultimo_processado
   */
  FUNCTION obter_resumo (
    p_data_inicio IN DATE,
    p_data_fim    IN DATE
  ) RETURN r_resumo;

END <nome_pacote>_pkg;
/
