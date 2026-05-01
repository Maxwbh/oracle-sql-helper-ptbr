--==============================================================================
-- Template: ORDS Handler Individual
--
-- Templates para cada método HTTP, prontos para adaptar.
-- Use quando precisar adicionar UM endpoint a um módulo já existente,
-- sem recriar todo o módulo (ords_module.sql cobre o caso completo).
--==============================================================================


--==============================================================================
-- HANDLER 1: GET /resource/:id (item) — Source Type: Query One Row
--
-- Retorna 1 linha como JSON automático. ORDS gera o JSON estruturado.
-- Returns 404 automaticamente se a query não encontra resultado.
--==============================================================================

BEGIN
  ORDS.define_handler(
    p_module_name    => '<module_name>',
    p_pattern        => '<resource>/:id',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query_one_row,
    p_source         =>
'SELECT id, nome, status, criado_em, atualizado_em
   FROM <table_name>
  WHERE id = :id'
  );
  COMMIT;
END;
/


--==============================================================================
-- HANDLER 2: GET /resource (collection) — Source Type: Collection Query
--
-- Retorna lista paginada como JSON automático.
-- ORDS adiciona links HATEOAS, contagem, e pagination.
--==============================================================================

BEGIN
  ORDS.define_handler(
    p_module_name    => '<module_name>',
    p_pattern        => '<resource>',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_collection_query,
    p_items_per_page => 25,
    p_source         =>
'SELECT id, nome, status, criado_em
   FROM <table_name>
  WHERE (:status IS NULL OR status = :status)
    AND (:name_filter IS NULL OR UPPER(nome) LIKE ''%'' || UPPER(:name_filter) || ''%'')
  ORDER BY criado_em DESC, id DESC'
  );
  COMMIT;
END;
/


--==============================================================================
-- HANDLER 3: POST /resource — Source Type: PL/SQL
--
-- Cria recurso. Recebe payload JSON, valida, insere, retorna 201 + Location.
--==============================================================================

BEGIN
  ORDS.define_handler(
    p_module_name    => '<module_name>',
    p_pattern        => '<resource>',
    p_method         => 'POST',
    p_source_type    => ORDS.source_type_plsql,
    p_mimes_allowed  => 'application/json',
    p_source         => q'[
DECLARE
  l_id_novo NUMBER;
BEGIN
  -- Validação de campos obrigatórios
  IF :nome IS NULL THEN
    OWA_UTIL.status_line(400);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Campo "nome" é obrigatório');
    APEX_JSON.close_object;
    RETURN;
  END IF;

  -- Insere
  INSERT INTO <table_name> (nome, status, criado_em)
  VALUES (:nome, NVL(:status, 'A'), SYSDATE)
  RETURNING id INTO l_id_novo;

  COMMIT;

  -- 201 Created + Location header
  OWA_UTIL.status_line(201);
  OWA_UTIL.mime_header('application/json', FALSE);
  HTP.p('Location: /ords/api/<module_path>/<resource>/' || l_id_novo);
  OWA_UTIL.http_header_close;

  APEX_JSON.open_object;
  APEX_JSON.write('id', l_id_novo);
  APEX_JSON.write('message', 'Recurso criado com sucesso');
  APEX_JSON.close_object;
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    ROLLBACK;
    OWA_UTIL.status_line(409);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Já existe recurso com este nome');
    APEX_JSON.close_object;
  WHEN OTHERS THEN
    ROLLBACK;
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Erro: ' || SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );
  COMMIT;
END;
/


--==============================================================================
-- HANDLER 4: PUT /resource/:id — Source Type: PL/SQL
--
-- Atualiza recurso. Idempotente — chamadas subsequentes mesmo body têm mesmo
-- efeito.
--==============================================================================

BEGIN
  ORDS.define_handler(
    p_module_name    => '<module_name>',
    p_pattern        => '<resource>/:id',
    p_method         => 'PUT',
    p_source_type    => ORDS.source_type_plsql,
    p_mimes_allowed  => 'application/json',
    p_source         => q'[
BEGIN
  UPDATE <table_name>
     SET nome       = NVL(:nome, nome),
         status     = NVL(:status, status),
         atualizado_em = SYSDATE
   WHERE id = :id;

  IF SQL%ROWCOUNT = 0 THEN
    OWA_UTIL.status_line(404);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Recurso ' || :id || ' não encontrado');
    APEX_JSON.close_object;
    RETURN;
  END IF;

  COMMIT;

  OWA_UTIL.status_line(200);
  OWA_UTIL.mime_header('application/json', FALSE);
  OWA_UTIL.http_header_close;
  
  APEX_JSON.open_object;
  APEX_JSON.write('id', :id);
  APEX_JSON.write('message', 'Atualizado com sucesso');
  APEX_JSON.close_object;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );
  COMMIT;
END;
/


--==============================================================================
-- HANDLER 5: DELETE /resource/:id — Source Type: PL/SQL
--
-- Remove (preferencialmente soft delete). Returns 204 No Content em sucesso.
--==============================================================================

BEGIN
  ORDS.define_handler(
    p_module_name    => '<module_name>',
    p_pattern        => '<resource>/:id',
    p_method         => 'DELETE',
    p_source_type    => ORDS.source_type_plsql,
    p_source         => q'[
BEGIN
  -- Soft delete: marca como inativo em vez de DELETE físico
  UPDATE <table_name>
     SET excluido_em = SYSDATE,
         ativo  = 'N'
   WHERE id = :id
     AND NVL(ativo, 'Y') = 'Y';

  IF SQL%ROWCOUNT = 0 THEN
    OWA_UTIL.status_line(404);
    OWA_UTIL.http_header_close;
    RETURN;
  END IF;

  COMMIT;

  -- 204 No Content (DELETE bem-sucedido)
  OWA_UTIL.status_line(204);
  OWA_UTIL.http_header_close;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );
  COMMIT;
END;
/


--==============================================================================
-- HANDLER 6: POST /resource/:id/action — Custom action
--
-- Quando você precisa expor uma "ação" que não é CRUD direto.
-- Ex: POST /faturas/123/cancel, POST /usuarios/456/reset-password
--==============================================================================

BEGIN
  ORDS.define_template(
    p_module_name => '<module_name>',
    p_pattern     => '<resource>/:id/<action>',
    p_priority    => 0
  );

  ORDS.define_handler(
    p_module_name    => '<module_name>',
    p_pattern        => '<resource>/:id/<action>',
    p_method         => 'POST',
    p_source_type    => ORDS.source_type_plsql,
    p_mimes_allowed  => 'application/json',
    p_source         => q'[
DECLARE
  l_status_atual VARCHAR2(20);
BEGIN
  -- Valida estado atual antes de executar ação
  SELECT status INTO l_status_atual
    FROM <table_name>
   WHERE id = :id;

  IF l_status_atual NOT IN ('PENDENTE', 'ATIVO') THEN
    OWA_UTIL.status_line(422);  -- Unprocessable Entity
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Não é possível executar ação no estado atual: ' || l_status_atual);
    APEX_JSON.close_object;
    RETURN;
  END IF;

  -- Executa ação
  UPDATE <table_name>
     SET status     = 'CANCELADO',
         atualizado_em = SYSDATE
   WHERE id = :id;

  COMMIT;

  OWA_UTIL.status_line(200);
  OWA_UTIL.mime_header('application/json', FALSE);
  OWA_UTIL.http_header_close;
  
  APEX_JSON.open_object;
  APEX_JSON.write('id', :id);
  APEX_JSON.write('new_status', 'CANCELADO');
  APEX_JSON.write('message', 'Ação executada com sucesso');
  APEX_JSON.close_object;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    OWA_UTIL.status_line(404);
    OWA_UTIL.http_header_close;
  WHEN OTHERS THEN
    ROLLBACK;
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );
  COMMIT;
END;
/
