--==============================================================================
-- Template: CLOB/BLOB Operations (DBMS_LOB)
--
-- Operações comuns com Large Objects: leitura/escrita, conversão para Base64,
-- cálculo de hash, append, comparação, busca.
--
-- Cobre cenários reais: armazenamento de PDFs gerados, autenticação de
-- documentos via hash, validação de conteúdo, conversão para download.
--==============================================================================


--==============================================================================
-- 1. Inserir BLOB (PDF gerado, recebido via APEX/ORDS)
--==============================================================================

DECLARE
  l_blob          BLOB;
  l_id_documento  NUMBER;
BEGIN
  -- Cria locator temporário (necessário antes de escrever)
  DBMS_LOB.createtemporary(l_blob, TRUE);

  -- Aqui você popularia l_blob a partir de:
  --   - APEX: APEX_APPLICATION_TEMP_FILES.blob_content (file upload)
  --   - ORDS: APEX_WEB_SERVICE.make_rest_request_b (download externo)
  --   - PL/SQL: BFILE + DBMS_LOB.loadfromfile (legado)

  INSERT INTO documentos (
    id, nome_documento, tipo_mime, conteudo_arquivo, tamanho_arquivo, criado_em, criado_por
  ) VALUES (
    documentos_seq.NEXTVAL,
    'fatura_2024.pdf',
    'application/pdf',
    l_blob,
    DBMS_LOB.getlength(l_blob),
    SYSDATE,
    USER
  ) RETURNING id INTO l_id_documento;

  COMMIT;

  -- Libera locator temporário (importante para não vazar PGA)
  DBMS_LOB.freetemporary(l_blob);

  DBMS_OUTPUT.put_line('Documento inserido: ID ' || l_id_documento);
END;
/


--==============================================================================
-- 2. Ler BLOB inteiro para variável local (cuidado com tamanho)
--==============================================================================

DECLARE
  l_blob     BLOB;
  l_tamanho  NUMBER;
BEGIN
  SELECT conteudo_arquivo, DBMS_LOB.getlength(conteudo_arquivo)
    INTO l_blob, l_tamanho
    FROM documentos
   WHERE id = 12345;

  DBMS_OUTPUT.put_line('Tamanho: ' || l_tamanho || ' bytes (' ||
                       ROUND(l_tamanho/1024/1024, 2) || ' MB)');

  -- Para BLOBs >100MB, leia em chunks (próximo exemplo)
END;
/


--==============================================================================
-- 3. Ler BLOB em chunks (volume grande, evitar OOM)
--==============================================================================

DECLARE
  l_blob          BLOB;
  l_buffer        RAW(32767);
  l_offset        NUMBER := 1;
  lc_tamanho_chunk CONSTANT NUMBER := 32767;
  l_total         NUMBER;
BEGIN
  SELECT conteudo_arquivo INTO l_blob
    FROM documentos
   WHERE id = 12345;

  l_total := DBMS_LOB.getlength(l_blob);

  WHILE l_offset <= l_total LOOP
    DBMS_LOB.read(
      lob_loc => l_blob,
      amount  => lc_tamanho_chunk,
      offset  => l_offset,
      buffer  => l_buffer
    );

    -- Processa o chunk em l_buffer aqui
    -- (envia para HTTP response, calcula hash incremental, etc.)

    l_offset := l_offset + lc_tamanho_chunk;
  END LOOP;
END;
/


--==============================================================================
-- 4. BLOB → Base64 (para download via JSON, página HTML, ou JS client-side)
--==============================================================================

CREATE OR REPLACE FUNCTION blob_para_base64 (
  p_blob IN BLOB
) RETURN CLOB IS
  lc_nome_unidade CONSTANT VARCHAR2(60) := 'BLOB_PARA_BASE64';
  l_clob          CLOB;
  l_offset        NUMBER := 1;
  lc_tamanho_chunk CONSTANT NUMBER := 21000;  -- múltiplo de 3 (Base64 friendly)
  l_buffer        RAW(21000);
  l_total         NUMBER;
BEGIN
  IF p_blob IS NULL OR DBMS_LOB.getlength(p_blob) = 0 THEN
    RETURN NULL;
  END IF;

  DBMS_LOB.createtemporary(l_clob, TRUE);
  l_total := DBMS_LOB.getlength(p_blob);

  WHILE l_offset <= l_total LOOP
    DBMS_LOB.read(p_blob, lc_tamanho_chunk, l_offset, l_buffer);
    DBMS_LOB.append(l_clob, UTL_RAW.cast_to_varchar2(
      UTL_ENCODE.base64_encode(l_buffer)
    ));
    l_offset := l_offset + lc_tamanho_chunk;
  END LOOP;

  RETURN l_clob;
EXCEPTION
  WHEN OTHERS THEN
    raise_application_error(-20999,
      'Erro em ' || lc_nome_unidade || ': ' || SQLERRM);
END;
/


--==============================================================================
-- 5. Base64 → BLOB (decodificar upload de JSON ou form)
--==============================================================================

CREATE OR REPLACE FUNCTION base64_para_blob (
  p_base64 IN CLOB
) RETURN BLOB IS
  l_blob          BLOB;
  l_offset        NUMBER := 1;
  lc_tamanho_chunk CONSTANT NUMBER := 28000;  -- múltiplo de 4 (Base64)
  l_buffer        VARCHAR2(28000);
  l_total         NUMBER;
BEGIN
  IF p_base64 IS NULL THEN
    RETURN NULL;
  END IF;

  DBMS_LOB.createtemporary(l_blob, TRUE);
  l_total := DBMS_LOB.getlength(p_base64);

  WHILE l_offset <= l_total LOOP
    l_buffer := DBMS_LOB.substr(p_base64, lc_tamanho_chunk, l_offset);
    DBMS_LOB.append(l_blob,
      UTL_ENCODE.base64_decode(UTL_RAW.cast_to_raw(l_buffer))
    );
    l_offset := l_offset + lc_tamanho_chunk;
  END LOOP;

  RETURN l_blob;
END;
/


--==============================================================================
-- 6. Hash de BLOB para autenticação de documento
--
-- Uso: gerar identificador único do conteúdo. Comparar dois documentos
-- pelo hash em vez de byte-a-byte. Detectar adulteração.
--==============================================================================

-- SHA-256 (recomendado — DBMS_CRYPTO requer execute privilege)
CREATE OR REPLACE FUNCTION hash_sha256_blob (
  p_blob IN BLOB
) RETURN VARCHAR2 IS
  l_hash_raw RAW(32);
BEGIN
  IF p_blob IS NULL THEN
    RETURN NULL;
  END IF;

  l_hash_raw := DBMS_CRYPTO.hash(
    src => p_blob,
    typ => DBMS_CRYPTO.hash_sh256
  );

  RETURN LOWER(RAWTOHEX(l_hash_raw));
END;
/

-- Uso para autenticação de documento (caso real: validação de documentos)
DECLARE
  l_blob_documento BLOB;
  l_hash           VARCHAR2(64);
  l_chave          VARCHAR2(40);
BEGIN
  SELECT conteudo_arquivo INTO l_blob_documento FROM documentos WHERE id = 12345;

  l_hash := hash_sha256_blob(l_blob_documento);

  -- Gera "chave" pública curta para mostrar ao usuário (URL-friendly)
  -- Ex: 8 primeiros chars do hash + checksum simples
  l_chave := SUBSTR(l_hash, 1, 8) || '-' || SUBSTR(l_hash, -8);

  UPDATE documentos
     SET hash_conteudo = l_hash,
         chave_publica = l_chave
   WHERE id = 12345;
  COMMIT;

  -- URL pública para validação:
  -- https://msbrasil.inf.br/ords/api/validar?chave=<l_chave>
END;
/


--==============================================================================
-- 7. Validar documento por hash (autenticação reversa)
--==============================================================================

CREATE OR REPLACE FUNCTION validar_hash_documento (
  p_id_documento IN NUMBER,
  p_blob         IN BLOB
) RETURN BOOLEAN IS
  l_hash_armazenado VARCHAR2(64);
  l_hash_atual      VARCHAR2(64);
BEGIN
  SELECT hash_conteudo INTO l_hash_armazenado
    FROM documentos
   WHERE id = p_id_documento;

  l_hash_atual := hash_sha256_blob(p_blob);

  RETURN l_hash_armazenado = l_hash_atual;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN FALSE;
END;
/


--==============================================================================
-- 8. CLOB — Inserir texto longo (HTML, XML, JSON grandes)
--==============================================================================

DECLARE
  l_clob CLOB;
BEGIN
  DBMS_LOB.createtemporary(l_clob, TRUE);

  -- Append em pedaços para CLOB grande (literal Oracle limita a ~32KB)
  DBMS_LOB.append(l_clob, '<html>');
  DBMS_LOB.append(l_clob, '<head><title>Relatório</title></head>');
  DBMS_LOB.append(l_clob, '<body>');

  -- Concatenação com query
  FOR r IN (SELECT nome, total FROM clientes WHERE total > 1000) LOOP
    DBMS_LOB.append(l_clob,
      '<p>' || r.nome || ': R$ ' || r.total || '</p>'
    );
  END LOOP;

  DBMS_LOB.append(l_clob, '</body></html>');

  INSERT INTO relatorios (id, conteudo) VALUES (relatorios_seq.NEXTVAL, l_clob);
  COMMIT;

  DBMS_LOB.freetemporary(l_clob);
END;
/


--==============================================================================
-- 9. CLOB — Buscar texto dentro do conteúdo
--==============================================================================

DECLARE
  l_clob     CLOB;
  l_posicao  NUMBER;
BEGIN
  SELECT conteudo INTO l_clob FROM relatorios WHERE id = 100;

  -- DBMS_LOB.instr é equivalente a INSTR mas funciona em LOB
  l_posicao := DBMS_LOB.instr(
    lob_loc  => l_clob,
    pattern  => 'cliente especial',  -- texto buscado
    offset   => 1,
    nth      => 1                    -- primeira ocorrência
  );

  IF l_posicao > 0 THEN
    DBMS_OUTPUT.put_line('Encontrado na posição: ' || l_posicao);

    -- Extrai 100 chars ao redor da ocorrência
    DBMS_OUTPUT.put_line('Contexto: ' ||
      DBMS_LOB.substr(l_clob, 100, GREATEST(1, l_posicao - 50))
    );
  END IF;
END;
/


--==============================================================================
-- 10. CLOB → tabela de linhas (parsing CSV em CLOB grande)
--==============================================================================

CREATE OR REPLACE FUNCTION clob_para_linhas (
  p_clob IN CLOB
) RETURN sys.odcivarchar2list PIPELINED IS
  l_total      NUMBER;
  l_offset     NUMBER := 1;
  l_pos        NUMBER;
  l_linha      VARCHAR2(32767);
BEGIN
  IF p_clob IS NULL THEN
    RETURN;
  END IF;

  l_total := DBMS_LOB.getlength(p_clob);

  WHILE l_offset <= l_total LOOP
    l_pos := DBMS_LOB.instr(p_clob, CHR(10), l_offset);

    IF l_pos = 0 THEN
      -- Última linha sem \n
      l_linha := DBMS_LOB.substr(p_clob, l_total - l_offset + 1, l_offset);
      PIPE ROW(l_linha);
      EXIT;
    END IF;

    l_linha := DBMS_LOB.substr(p_clob, l_pos - l_offset, l_offset);
    PIPE ROW(l_linha);
    l_offset := l_pos + 1;
  END LOOP;
  RETURN;
END;
/

-- Uso:
SELECT column_value AS linha
  FROM TABLE(clob_para_linhas((SELECT conteudo FROM relatorios WHERE id = 100)))
 WHERE rownum <= 10;


--==============================================================================
-- 11. Anti-patterns CLOB/BLOB
--==============================================================================

/*
ANTI-PATTERN 1: VARCHAR2 onde deveria ser CLOB
  - VARCHAR2 limite: 4000 bytes (ou 32767 com MAX_STRING_SIZE=EXTENDED)
  - Se conteúdo pode crescer → CLOB

ANTI-PATTERN 2: Não liberar createtemporary
  - DBMS_LOB.createtemporary aloca em PGA temporária
  - Sem freetemporary, vaza até o fim da sessão
  - SEMPRE pareie create + free

ANTI-PATTERN 3: Concatenar CLOB com ||
  -- RUIM: força conversão para VARCHAR2 (limite 4000/32767)
  l_clob := l_clob || 'mais texto';

  -- BOM: append direto no LOB
  DBMS_LOB.append(l_clob, 'mais texto');

ANTI-PATTERN 4: SUBSTR em LOB grande
  -- RUIM: SUBSTR converte primeiro para VARCHAR2 (truncamento silencioso)
  l_chunk := SUBSTR(l_clob, 1, 100);

  -- BOM: DBMS_LOB.substr opera no próprio LOB
  l_chunk := DBMS_LOB.substr(l_clob, 100, 1);

ANTI-PATTERN 5: Hash MD5 ou SHA-1 para autenticação
  - MD5 e SHA-1 são considerados quebrados criptograficamente
  - Use SHA-256 ou superior (DBMS_CRYPTO.hash_sh256)

ANTI-PATTERN 6: Armazenar Base64 em vez de BLOB nativo
  -- RUIM: Base64 ocupa 33% mais espaço, exige decode em todo uso
  --       VARCHAR2 column → CLOB
  -- BOM: BLOB column nativo, codifica/decodifica só nos endpoints

ANTI-PATTERN 7: Comparar BLOBs com =
  -- Não funciona consistentemente
  IF l_blob1 = l_blob2 THEN ...  -- comportamento depende da versão

  -- Use DBMS_LOB.compare ou compare hashes
  IF DBMS_LOB.compare(l_blob1, l_blob2) = 0 THEN ...
*/
