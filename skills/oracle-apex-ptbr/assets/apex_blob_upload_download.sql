--==============================================================================
-- Template: APEX BLOB Upload/Download
--
-- Cenários cobertos:
--   1. Upload de arquivo via File Browse Item
--   2. Salvar BLOB gerado em PL/SQL (ex: PDF criado por html2pdf.js)
--   3. Download direto via On-Demand Process
--   4. Display inline (PDF embed, imagem)
--   5. Validação de hash para autenticação de documento
--
-- Casos reais cobertos:
--   - Page 15 IRPF: gerar PDF via html2pdf.js, salvar BLOB, recuperar
--   - Page 49 Auth: hash + key validation
--   - Page 225 Validation: CLOB handling com PDF como BLOB
--==============================================================================


--==============================================================================
-- 1. Upload via File Browse Item — padrão APEX
--==============================================================================

/*
ITEM CONFIGURATION:

  Type:                       File Browse...
  Storage Type:               BLOB column specified in Item Source Attribute
  Item Source Attribute:      table_name:column_name:pk_column_name:pk_value
  
  Ou:
  
  Storage Type:               Table APEX_APPLICATION_TEMP_FILES
  
  (segunda opção é mais flexível — você controla onde armazenar)
*/

-- A. Page Process: After Submit, depois da validação
DECLARE
  l_nome_unidade CONSTANT VARCHAR2(60) := 'PAGE_15_PROC_UPLOAD_PDF';
  l_blob       BLOB;
  l_nome_arquivo   VARCHAR2(500);
  l_tipo_mime   VARCHAR2(100);
  l_id_documento     NUMBER;
BEGIN
  -- Recupera arquivo do storage temporário
  SELECT blob_content, filename, tipo_mime
    INTO l_blob, l_nome_arquivo, l_tipo_mime
    FROM APEX_APPLICATION_TEMP_FILES
   WHERE nome = :P15_FILE_BROWSE;  -- nome do item de upload

  -- Validação de tipo
  IF l_tipo_mime NOT IN ('application/pdf', 'image/png', 'image/jpeg') THEN
    APEX_ERROR.add_error(
      p_mensagem          => 'Tipo de arquivo não permitido: ' || l_tipo_mime,
      p_display_location => APEX_ERROR.c_inline_with_field_and_notif,
      p_page_item_name   => 'P15_FILE_BROWSE'
    );
    RETURN;
  END IF;

  -- Validação de tamanho (max 10MB)
  IF DBMS_LOB.getlength(l_blob) > 10485760 THEN
    APEX_ERROR.add_error(
      p_mensagem          => 'Arquivo excede limite de 10MB',
      p_display_location => APEX_ERROR.c_inline_with_field_and_notif,
      p_page_item_name   => 'P15_FILE_BROWSE'
    );
    RETURN;
  END IF;

  -- Insere documento
  INSERT INTO documentos (
    id, nome_documento, tipo_mime, conteudo_arquivo,
    tamanho_arquivo, hash_conteudo, criado_em, criado_por
  ) VALUES (
    documentos_seq.NEXTVAL,
    l_nome_arquivo,
    l_tipo_mime,
    l_blob,
    DBMS_LOB.getlength(l_blob),
    LOWER(RAWTOHEX(DBMS_CRYPTO.hash(l_blob, DBMS_CRYPTO.hash_sh256))),
    SYSDATE,
    :APP_USER
  ) RETURNING id INTO l_id_documento;

  -- Limpa o arquivo temp da APEX (importante!)
  DELETE FROM APEX_APPLICATION_TEMP_FILES WHERE nome = :P15_FILE_BROWSE;

  COMMIT;

  -- Retorna ID do documento via item
  :P15_ID_DOCUMENTO := l_id_documento;
  
  APEX_APPLICATION.g_print_success_message :=
    '<span class="t-Icon icon-check"></span> Documento ' || l_nome_arquivo || ' enviado';

EXCEPTION
  WHEN OTHERS THEN
    APEX_DEBUG.error('Erro em ' || l_nome_unidade || ': ' || SQLERRM);
    APEX_ERROR.add_error(
      p_mensagem          => 'Erro ao processar arquivo: ' || SQLERRM,
      p_display_location => APEX_ERROR.c_inline_in_notification
    );
END;


--==============================================================================
-- 2. Salvar BLOB recebido via JavaScript (caso real: PDF gerado por html2pdf.js)
--
-- Cenário de upload de documento:
--   - JS no cliente gera PDF com html2pdf.js
--   - Converte para Base64
--   - Envia via apex.server.process
--   - PL/SQL converte Base64 → BLOB e salva
--==============================================================================

/*
JAVASCRIPT no cliente (resumido):

async function generateAndSavePdf() {
  // Gera PDF do conteúdo da página
  const element = documento.getElementById('printable-area');
  const opt = {
    margin: 10,
    filename: 'demonstrativo_irpf.pdf',
    image: { type: 'jpeg', quality: 0.95 },
    html2canvas: { scale: 2 },
    jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' }
  };
  
  const pdfBlob = await html2pdf().set(opt).from(element).output('blob');
  
  // Converte BLOB para Base64
  const base64 = await blobToBase64(pdfBlob);
  
  // Envia para servidor
  apex.server.process('SAVE_GENERATED_PDF', {
    x01: $v('P15_ID_FATURA'),         // contexto
    x02: 'demonstrativo_irpf.pdf',     // filename
    f01: [base64]                       // payload (em F01 array, suporta tamanho)
  }, {
    dataType: 'json',
    success: function(data) {
      if (data.error) {
        apex.message.alert('Erro: ' + data.error);
        return;
      }
      $s('P15_ID_DOCUMENTO', data.id_documento);
      apex.message.showPageSuccess('PDF salvo (ID ' + data.id_documento + ')');
    }
  });
}

function blobToBase64(blob) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result.split(',')[1]);
    reader.readAsDataURL(blob);
  });
}
*/


-- AJAX Callback "SAVE_GENERATED_PDF"
DECLARE
  l_nome_unidade  CONSTANT VARCHAR2(60) := 'AJAX_SAVE_GENERATED_PDF';
  l_id_fatura NUMBER := TO_NUMBER(APEX_APPLICATION.G_X01);
  l_nome_arquivo   VARCHAR2(500) := APEX_APPLICATION.G_X02;
  l_base64     CLOB;
  l_blob       BLOB;
  l_id_documento     NUMBER;
  l_hash       VARCHAR2(64);
BEGIN
  -- Reconstrói o Base64 a partir do array F01 (chunks)
  DBMS_LOB.createtemporary(l_base64, TRUE);
  FOR i IN 1..APEX_APPLICATION.G_F01.COUNT LOOP
    DBMS_LOB.append(l_base64, APEX_APPLICATION.G_F01(i));
  END LOOP;

  -- Decodifica Base64 → BLOB
  l_blob := base64_para_blob(l_base64);  -- função do clob_blob_operations.sql

  -- Hash para autenticação
  l_hash := LOWER(RAWTOHEX(DBMS_CRYPTO.hash(l_blob, DBMS_CRYPTO.hash_sh256)));

  -- Insere
  INSERT INTO documentos (
    id, nome_documento, tipo_mime, conteudo_arquivo, tamanho_arquivo,
    hash_conteudo, id_fatura_relacionada, criado_em, criado_por
  ) VALUES (
    documentos_seq.NEXTVAL,
    l_nome_arquivo,
    'application/pdf',
    l_blob,
    DBMS_LOB.getlength(l_blob),
    l_hash,
    l_id_fatura,
    SYSDATE,
    :APP_USER
  ) RETURNING id INTO l_id_documento;

  COMMIT;

  -- Liberar CLOB temporário
  DBMS_LOB.freetemporary(l_base64);

  -- Resposta
  APEX_JSON.open_object;
  APEX_JSON.write('id_documento', l_id_documento);
  APEX_JSON.write('hash_conteudo', l_hash);
  APEX_JSON.close_object;

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    APEX_DEBUG.error('Erro em ' || l_nome_unidade || ': ' || SQLERRM);
    APEX_JSON.open_object;
    APEX_JSON.write('error', SQLERRM);
    APEX_JSON.close_object;
END;


--==============================================================================
-- 3. Download direto via On-Demand Process
--
-- URL: f?p=&APP_ID.:0:&APP_SESSION.:APPLICATION_PROCESS=DOWNLOAD_DOCUMENT:::P_DOC_ID:12345
--==============================================================================

-- APPLICATION-LEVEL Process (não Page-level), tipo "On Demand"
DECLARE
  l_nome_unidade CONSTANT VARCHAR2(60) := 'APP_PROC_DOWNLOAD_DOCUMENT';
  l_blob       BLOB;
  l_nome_arquivo   VARCHAR2(500);
  l_tipo_mime   VARCHAR2(100);
  l_tamanho       NUMBER;
BEGIN
  -- Pega ID da URL (item P_DOC_ID setado via URL parameter)
  SELECT conteudo_arquivo, nome_documento, tipo_mime, tamanho_arquivo
    INTO l_blob, l_nome_arquivo, l_tipo_mime, l_tamanho
    FROM documentos
   WHERE id = :P_DOC_ID
     AND ativo = 'Y';

  -- Headers HTTP para download
  OWA_UTIL.mime_header(NVL(l_tipo_mime, 'application/octet-stream'), FALSE);
  HTP.p('Content-Length: ' || l_tamanho);
  HTP.p('Content-Disposition: attachment; filename="' || l_nome_arquivo || '"');
  HTP.p('Cache-Control: max-age=0');
  OWA_UTIL.http_header_close;

  -- Envia o BLOB
  WPG_DOCLOAD.download_file(l_blob);

  -- IMPORTANTE: termina o processamento APEX (não continua a página)
  APEX_APPLICATION.stop_apex_engine;

EXCEPTION
  WHEN APEX_APPLICATION.e_stop_apex_engine THEN
    -- Engine terminou normalmente (download enviado)
    NULL;
  WHEN NO_DATA_FOUND THEN
    HTP.p('<h1>Documento não encontrado</h1>');
    APEX_APPLICATION.stop_apex_engine;
  WHEN OTHERS THEN
    APEX_DEBUG.error('Erro em ' || l_nome_unidade || ': ' || SQLERRM);
    HTP.p('<h1>Erro ao baixar documento</h1>');
    APEX_APPLICATION.stop_apex_engine;
END;


--==============================================================================
-- 4. Display inline (PDF embed na página)
--==============================================================================

/*
REGION TYPE: Static Content

Source HTML:

<div class="pdf-viewer">
  <embed
    src="f?p=&APP_ID.:0:&APP_SESSION.:APPLICATION_PROCESS=DOWNLOAD_DOCUMENT:::P_DOC_ID:&P15_ID_DOCUMENTO."
    type="application/pdf"
    width="100%"
    height="600px" />
</div>

OU usando iframe para mais controle:

<iframe
  src="f?p=&APP_ID.:0:&APP_SESSION.:APPLICATION_PROCESS=DOWNLOAD_DOCUMENT:::P_DOC_ID:&P15_ID_DOCUMENTO."
  width="100%"
  height="600px"
  frameborder="0"></iframe>
*/


--==============================================================================
-- 5. Validação de documento via hash + key (caso de validação de documentos)
--==============================================================================

-- Cenário: documento gerado tem URL pública para validação
-- URL: https://msbrasil.inf.br/ords/api/validar?key=ab12cd34-ef56gh78
-- Endpoint retorna se documento é autêntico

-- Endpoint ORDS para validação pública
BEGIN
  ORDS.define_template(
    p_module_name => 'public.v1',
    p_pattern     => 'validar',
    p_priority    => 0
  );

  ORDS.define_handler(
    p_module_name    => 'public.v1',
    p_pattern        => 'validar',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_plsql,
    p_source         => q'[
DECLARE
  l_doc        documentos%ROWTYPE;
  l_hash_curto VARCHAR2(50);
BEGIN
  IF :key IS NULL THEN
    OWA_UTIL.status_line(400);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Parâmetro "key" é obrigatório');
    APEX_JSON.close_object;
    RETURN;
  END IF;

  -- Decompõe key: 8chars-8chars
  l_hash_curto := REPLACE(:key, '-', '');
  
  IF LENGTH(l_hash_curto) <> 16 OR NOT REGEXP_LIKE(l_hash_curto, '^[0-9a-f]+$') THEN
    OWA_UTIL.status_line(400);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('valid', FALSE);
    APEX_JSON.write('error', 'Formato de chave inválido');
    APEX_JSON.close_object;
    RETURN;
  END IF;

  -- Busca documento pelo chave_publica
  SELECT * INTO l_doc
    FROM documentos
   WHERE chave_publica = :key
     AND ativo = 'Y';

  -- Resposta de sucesso
  OWA_UTIL.status_line(200);
  OWA_UTIL.mime_header('application/json', FALSE);
  OWA_UTIL.http_header_close;
  
  APEX_JSON.open_object;
  APEX_JSON.write('valid', TRUE);
  APEX_JSON.write('id_documento', l_doc.id);
  APEX_JSON.write('nome_documento', l_doc.nome_documento);
  APEX_JSON.write('issued_at', TO_CHAR(l_doc.criado_em, 'YYYY-MM-DD HH24:MI:SS'));
  APEX_JSON.write('hash_conteudo', l_doc.hash_conteudo);
  APEX_JSON.close_object;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    OWA_UTIL.status_line(404);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('valid', FALSE);
    APEX_JSON.write('error', 'Documento não encontrado');
    APEX_JSON.close_object;
END;
]'
  );
  COMMIT;
END;
/


--==============================================================================
-- 6. APEX Item para mostrar PDF como Base64 inline
--
-- Útil quando JS no cliente precisa do conteúdo (não download)
--==============================================================================

-- Computation Type: PL/SQL Function Body
DECLARE
  l_blob   BLOB;
  l_base64 CLOB;
BEGIN
  IF :P15_ID_DOCUMENTO IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT conteudo_arquivo INTO l_blob
    FROM documentos
   WHERE id = :P15_ID_DOCUMENTO;

  l_base64 := blob_para_base64(l_blob);  -- função do clob_blob_operations.sql

  RETURN l_base64;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;


--==============================================================================
-- 7. Anti-patterns
--==============================================================================

/*
ANTI-PATTERN 1: Não limpar APEX_APPLICATION_TEMP_FILES após processar
  - Storage temp acumula sem limite
  - Após processar, sempre DELETE FROM APEX_APPLICATION_TEMP_FILES WHERE nome = ...

ANTI-PATTERN 2: Não validar tipo_mime
  - Cliente pode renomear .exe para .pdf
  - Sempre verifique tipo_mime ANTES de armazenar

ANTI-PATTERN 3: Aceitar BLOB sem limite de tamanho
  - Upload de 10GB consome tablespace, memória, network
  - Limite via DBMS_LOB.getlength antes de inserir

ANTI-PATTERN 4: Hash MD5 ou SHA-1 para autenticação
  - MD5 e SHA-1 estão criptograficamente quebrados
  - Use SHA-256 (DBMS_CRYPTO.hash_sh256) no mínimo

ANTI-PATTERN 5: APEX_APPLICATION.stop_apex_engine sem catch da exception
  - stop_apex_engine lança APEX_APPLICATION.e_stop_apex_engine
  - Sem catch, a exception "vaza" e parece erro real
  - Sempre WHEN APEX_APPLICATION.e_stop_apex_engine THEN NULL

ANTI-PATTERN 6: Download em página com authentication scheme bloqueando
  - On-Demand Process executa fora do contexto da página
  - Authorization Scheme da página NÃO se aplica
  - Aplique authorization no próprio On-Demand Process

ANTI-PATTERN 7: Confiar em nome_documento vindo do cliente
  - Cliente pode enviar "../../../etc/passwd" como nome
  - Sanitize: REGEXP_REPLACE(filename, '[^a-zA-Z0-9._-]', '_')
*/
