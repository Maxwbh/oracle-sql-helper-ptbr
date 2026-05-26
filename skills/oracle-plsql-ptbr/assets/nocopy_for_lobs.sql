--==============================================================================
-- Template: NOCOPY Hint para LOBs e Collections
--
-- Princípio Tim Hall: pass-by-value de LOB/collection grande em parâmetros
-- OUT/IN OUT é overhead significativo. NOCOPY força pass-by-reference.
--
-- Cenário M&S do Brasil — processamento de LOBs:
--   - Page 15 (IRPF): PDF gerado por html2pdf.js manipulado em PL/SQL
--   - Page 49 (Auth): documento autenticado, hash, validação
--   - Page 225 (Validation): CLOB com conteúdo do documento
--
-- Em todos os casos, BLOBs/CLOBs trafegam entre procedures sem NOCOPY,
-- multiplicando uso de PGA por sessão.
--==============================================================================


--==============================================================================
-- 1. Por que NOCOPY importa — entendendo o problema
--==============================================================================

/*
COMPORTAMENTO PADRÃO (sem NOCOPY):

  Procedure A passa um BLOB de 5MB para procedure B como IN OUT
  → Oracle COPIA os 5MB para um workspace temporário (pass-by-value)
  → B modifica a cópia
  → Quando B retorna, COPIA os 5MB de volta para A
  → Total: 10MB de cópia para uma operação que poderia ser zero

COMPORTAMENTO COM NOCOPY:

  Procedure A passa BLOB com NOCOPY
  → Oracle passa REFERÊNCIA (pass-by-reference)
  → B modifica diretamente o BLOB de A
  → Sem cópia
  → Total: ~zero overhead

QUANDO IMPORTA:
  - LOBs (BLOB, CLOB, NCLOB, BFILE) > 100KB
  - Collections grandes (TABLE OF, VARRAY com muitos elementos)
  - Records complexos
  - Em loops: cada iteração economiza a cópia

QUANDO NÃO IMPORTA:
  - Tipos escalares (NUMBER, VARCHAR2, DATE) — Oracle já otimiza
  - Parâmetros IN puros — não há cópia de volta mesmo
  - LOBs pequenos (< 4KB) — overhead é negligível
*/


--==============================================================================
-- 2. Sintaxe NOCOPY
--==============================================================================

CREATE OR REPLACE PROCEDURE processar_pdf_blob (
  p_id_fatura   IN     NUMBER,
  p_pdf_blob    IN OUT NOCOPY BLOB,    -- ← NOCOPY aplica aqui
  p_metadados   OUT    NOCOPY CLOB     -- ← e aqui
) IS
BEGIN
  -- Modifica p_pdf_blob diretamente (sem cópia interna)
  DBMS_LOB.append(p_pdf_blob, UTL_RAW.cast_to_raw('<!-- rodape -->'));

  -- Popula p_metadados diretamente
  DBMS_LOB.createtemporary(p_metadados, TRUE);
  DBMS_LOB.append(p_metadados, '{"tamanho":' || DBMS_LOB.getlength(p_pdf_blob) || '}');
END processar_pdf_blob;
/


--==============================================================================
-- 3. Caso prático M&S do Brasil: pipeline de processamento de PDF
--==============================================================================

-- ANTI-PATTERN: sem NOCOPY (PDF de 2MB copiado 4 vezes no fluxo)
CREATE OR REPLACE PACKAGE BODY pipeline_pdf_pkg AS

  PROCEDURE adicionar_marca_dagua (
    p_pdf IN OUT BLOB
  ) IS
  BEGIN
    -- Modifica p_pdf, mas Oracle copia 2MB de entrada e 2MB de saída
    NULL;  -- lógica fictícia
  END;

  PROCEDURE comprimir_pdf (
    p_pdf IN OUT BLOB
  ) IS
  BEGIN
    -- Mais 2MB + 2MB de cópia
    NULL;
  END;

  PROCEDURE criptografar_pdf (
    p_pdf IN OUT BLOB
  ) IS
  BEGIN
    -- Mais 2MB + 2MB de cópia
    NULL;
  END;

  PROCEDURE processar_pdf_irpf (
    p_id_fatura IN NUMBER,
    p_pdf       IN OUT BLOB
  ) IS
  BEGIN
    adicionar_marca_dagua(p_pdf);   -- 4MB de cópia
    comprimir_pdf(p_pdf);           -- 4MB de cópia
    criptografar_pdf(p_pdf);        -- 4MB de cópia
    -- Total overhead: 12MB de cópia para PDF de 2MB
  END;

END pipeline_pdf_pkg;
/


-- BOM: com NOCOPY (zero cópia entre as procedures)
CREATE OR REPLACE PACKAGE BODY pipeline_pdf_pkg AS

  PROCEDURE adicionar_marca_dagua (
    p_pdf IN OUT NOCOPY BLOB
  ) IS
  BEGIN
    -- Modifica diretamente o BLOB original via referência
    NULL;
  END;

  PROCEDURE comprimir_pdf (
    p_pdf IN OUT NOCOPY BLOB
  ) IS
  BEGIN
    NULL;
  END;

  PROCEDURE criptografar_pdf (
    p_pdf IN OUT NOCOPY BLOB
  ) IS
  BEGIN
    NULL;
  END;

  PROCEDURE processar_pdf_irpf (
    p_id_fatura IN NUMBER,
    p_pdf       IN OUT NOCOPY BLOB
  ) IS
  BEGIN
    adicionar_marca_dagua(p_pdf);   -- zero cópia
    comprimir_pdf(p_pdf);           -- zero cópia
    criptografar_pdf(p_pdf);        -- zero cópia
    -- Total overhead: ~0
  END;

END pipeline_pdf_pkg;
/


--==============================================================================
-- 4. NOCOPY com collections grandes
--==============================================================================

CREATE OR REPLACE PACKAGE processador_faturas AS
  TYPE t_lista_faturas IS TABLE OF faturas%ROWTYPE INDEX BY PLS_INTEGER;

  -- Collection passada com NOCOPY — útil quando tem milhares de elementos
  PROCEDURE aplicar_regras_negocio (
    p_faturas IN OUT NOCOPY t_lista_faturas
  );

  PROCEDURE calcular_totais (
    p_faturas IN  t_lista_faturas,           -- IN, sem NOCOPY (não há cópia volta)
    p_total   OUT NOCOPY NUMBER
  );
END;
/


--==============================================================================
-- 5. Caveats CRÍTICOS — quando NOCOPY pode causar bugs
--==============================================================================

/*
CAVEAT 1: Compilador pode IGNORAR NOCOPY silenciosamente

  NOCOPY é HINT, não instrução. Oracle ignora em casos como:
    - Parâmetro associado a expressão (não variável simples)
    - Collection do tipo associativa indexada por VARCHAR2
    - Tipos com TRIGGER de coleção
    - Conversões implícitas necessárias
    - Procedure remota (database link)

  Você não recebe warning. Para confirmar, use PL/SQL warnings:

  ALTER SESSION SET PLSQL_WARNINGS = 'ENABLE:ALL';
  ALTER PACKAGE pipeline_pdf_pkg COMPILE;

  -- Veja warnings em USER_ERRORS / USER_PLSQL_OBJECT_SETTINGS


CAVEAT 2: Estado intermediário visível em caso de exception

  Sem NOCOPY: se procedure B falhar, A recebe o BLOB original (rollback do
              workspace).
  
  Com NOCOPY: B modifica o BLOB de A diretamente. Se B falhar no meio,
              A vê o estado intermediário (parcialmente modificado).
  
  Implicação: não confie em "o parâmetro volta como entrou" se houve exception.

  PROCEDURE validar_e_processar (p_blob IN OUT NOCOPY BLOB) IS
  BEGIN
    DBMS_LOB.append(p_blob, raw1);  -- modificou p_blob
    DBMS_LOB.append(p_blob, raw2);  -- modificou de novo
    raise_meu_erro;                  -- ← caller vê p_blob com raw1 e raw2 anexados
  END;


CAVEAT 3: NOCOPY + recursão = problemas

  Procedure recursiva passando NOCOPY pode ter comportamento inesperado.
  Cada chamada ainda usa a mesma referência. Estado pode ser modificado
  em ordem inesperada.


CAVEAT 4: Não use NOCOPY apenas porque "é mais rápido"

  Adicionar NOCOPY em todo lugar não traz benefício e introduz risco
  de exception-state-visible. Use SELETIVAMENTE em:
    - LOBs > 100KB
    - Collections com >1000 elementos
    - Records com tipos LOB internos
    - Hot paths (chamados milhares de vezes)
*/


--==============================================================================
-- 6. Como medir o ganho real
--==============================================================================

-- Baseline (sem NOCOPY): timing
SET TIMING ON;
DECLARE
  l_blob BLOB;
BEGIN
  SELECT conteudo_arquivo INTO l_blob FROM documentos WHERE id = 12345;
  
  FOR i IN 1..1000 LOOP
    pipeline_pdf_pkg.processar_pdf_irpf(12345, l_blob);
  END LOOP;
END;
/
-- Tempo: e.g., 8.3 segundos

-- Após adicionar NOCOPY: re-timing
SET TIMING ON;
DECLARE
  l_blob BLOB;
BEGIN
  SELECT conteudo_arquivo INTO l_blob FROM documentos WHERE id = 12345;
  
  FOR i IN 1..1000 LOOP
    pipeline_pdf_pkg.processar_pdf_irpf(12345, l_blob);
  END LOOP;
END;
/
-- Tempo: e.g., 1.7 segundos (5x mais rápido)


-- Verificar PGA usage antes/depois (ajuda a confirmar ganho)
SELECT s.username, s.sid,
       ROUND(pga_used_mem/1024/1024, 2) AS pga_usado_mb,
       ROUND(pga_alloc_mem/1024/1024, 2) AS pga_alocado_mb,
       ROUND(pga_max_mem/1024/1024, 2) AS pga_max_mb
  FROM v$session s
  JOIN v$process p ON s.paddr = p.addr
 WHERE s.username = USER
   AND s.sid = SYS_CONTEXT('USERENV', 'SID');


--==============================================================================
-- 7. Padrão de uso recomendado — M&S do Brasil
--==============================================================================

/*
EM TODO CÓDIGO QUE TRAFEGA BLOB/CLOB ENTRE PROCEDURES:

  1. Identifique o tipo: BLOB, CLOB, NCLOB, BFILE, ou collection grande?
  2. Tamanho típico em produção: > 100KB?
  3. Se sim, adicione NOCOPY ao parâmetro IN OUT ou OUT
  4. Comente no header documentando: "NOCOPY: PDFs típicos > 1MB"
  5. Em testes, force exception no meio para confirmar comportamento
     (estado intermediário visível ao caller)

EXEMPLOS DE LOCAIS PARA APLICAR NOCOPY:
  - Procedures que assinam digitalmente um documento
  - Procedures que adicionam metadata em PDF
  - Procedures que validam hash + retornam status
  - Procedures que convertem BLOB ↔ CLOB (Base64)
  - Loops que processam coleção de documentos
*/


-- Exemplo final integrado: validation pipeline com NOCOPY
CREATE OR REPLACE PACKAGE BODY validacao_documento_pkg AS

  gc_nome_pacote CONSTANT VARCHAR2(30) := 'VALIDACAO_DOCUMENTO_PKG';

  PROCEDURE calcular_hash (
    p_blob   IN  NOCOPY BLOB,            -- read-only mas grande, NOCOPY ajuda
    p_hash   OUT VARCHAR2                -- saída pequena, NOCOPY irrelevante
  ) IS
  BEGIN
    p_hash := LOWER(RAWTOHEX(DBMS_CRYPTO.hash(p_blob, DBMS_CRYPTO.hash_sh256)));
  END;

  PROCEDURE adicionar_assinatura (
    p_blob              IN OUT NOCOPY BLOB,
    p_usuario_assinante IN     VARCHAR2,
    p_certificado       IN     VARCHAR2
  ) IS
  BEGIN
    -- Anexa metadata de assinatura ao BLOB original
    DBMS_LOB.append(p_blob, UTL_RAW.cast_to_raw(
      '<assinatura usuario="' || p_usuario_assinante || '" cert="' || p_certificado || '"/>'
    ));
  END;

  PROCEDURE validar_e_assinar (
    p_id_fatura      IN     NUMBER,
    p_blob           IN OUT NOCOPY BLOB,
    p_status         OUT    VARCHAR2,
    p_hash_apos      OUT    VARCHAR2
  ) IS
    lc_nome_unidade CONSTANT VARCHAR2(60) := gc_nome_pacote || '.validar_e_assinar';
    l_hash_antes VARCHAR2(64);
  BEGIN
    -- Hash inicial
    calcular_hash(p_blob, l_hash_antes);

    -- Valida estrutura (lógica fictícia)
    IF DBMS_LOB.getlength(p_blob) < 100 THEN
      p_status := 'INVALIDO_MUITO_PEQUENO';
      RETURN;
    END IF;

    -- Adiciona assinatura
    adicionar_assinatura(p_blob, USER, 'CERT_MSBRASIL_2024');

    -- Hash final
    calcular_hash(p_blob, p_hash_apos);

    p_status := 'ASSINADO';
  EXCEPTION
    WHEN OTHERS THEN
      -- Importante: com NOCOPY, p_blob pode estar em estado intermediário
      -- aqui. Caller deve descartar ou re-validar.
      p_status := 'ERRO';
      raise_application_error(-20999,
        'Erro em ' || lc_nome_unidade || ': ' || SQLERRM);
  END;

END validacao_documento_pkg;
/
