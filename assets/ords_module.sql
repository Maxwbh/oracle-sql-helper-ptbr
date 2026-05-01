--==============================================================================
-- Template: ORDS Module Completo (CRUD)
--
-- Define um módulo ORDS com todos os endpoints CRUD para um recurso.
-- Use como base e adapte para o domínio específico.
--
-- Pré-requisitos:
--   - Schema deve estar habilitado para ORDS (uma única vez):
--     EXEC ORDS.enable_schema(p_url_mapping_pattern => 'api');
--==============================================================================

BEGIN
  --============================================================================
  -- 1. Define o módulo (versionado)
  --============================================================================
  ORDS.define_module(
    p_module_name    => 'faturas.v1',
    p_base_path      => '/faturas/v1/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'API de Faturas v1 — operações CRUD'
  );

  --============================================================================
  -- 2. GET /faturas/v1/fatura — listar (collection)
  --============================================================================
  ORDS.define_template(
    p_module_name => 'faturas.v1',
    p_pattern     => 'fatura',
    p_priority    => 0
  );

  ORDS.define_handler(
    p_module_name    => 'faturas.v1',
    p_pattern        => 'fatura',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_collection_query,
    p_items_per_page => 25,
    p_source         => 
'SELECT id, numero_fatura, id_cliente, data_emissao, data_vencimento, valor, status
   FROM faturas
  WHERE (:status IS NULL OR status = :status)
    AND (:id_cliente IS NULL OR id_cliente = :id_cliente)
  ORDER BY data_emissao DESC, id DESC'
  );

  --============================================================================
  -- 3. GET /faturas/v1/fatura/:id — detalhe (item)
  --============================================================================
  ORDS.define_template(
    p_module_name => 'faturas.v1',
    p_pattern     => 'fatura/:id',
    p_priority    => 0,
    p_etag_type   => 'HASH'
  );

  ORDS.define_handler(
    p_module_name    => 'faturas.v1',
    p_pattern        => 'fatura/:id',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query_one_row,
    p_source         =>
'SELECT id, numero_fatura, id_cliente, data_emissao, data_vencimento, valor, status,
        criado_em, atualizado_em
   FROM faturas
  WHERE id = :id'
  );

  --============================================================================
  -- 4. POST /faturas/v1/fatura — criar
  --============================================================================
  ORDS.define_handler(
    p_module_name    => 'faturas.v1',
    p_pattern        => 'fatura',
    p_method         => 'POST',
    p_source_type    => ORDS.source_type_plsql,
    p_mimes_allowed  => 'application/json',
    p_source         => q'[
DECLARE
  l_id_fatura NUMBER;
  l_qtd      NUMBER;
BEGIN
  -- Valida parâmetros obrigatórios (recebidos via JSON body)
  IF :id_cliente IS NULL OR :valor IS NULL THEN
    OWA_UTIL.status_line(400);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'id_cliente e valor são obrigatórios');
    APEX_JSON.close_object;
    RETURN;
  END IF;

  -- Valida cliente existe
  SELECT COUNT(*) INTO l_qtd FROM clientes WHERE id = :id_cliente;
  IF l_qtd = 0 THEN
    OWA_UTIL.status_line(422);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Cliente não encontrado: ' || :id_cliente);
    APEX_JSON.close_object;
    RETURN;
  END IF;

  -- Insere
  INSERT INTO faturas (
    id_cliente, numero_fatura, data_emissao, data_vencimento, valor, status, criado_em
  ) VALUES (
    :id_cliente,
    :numero_fatura,
    NVL(:data_emissao, SYSDATE),
    NVL(:data_vencimento, SYSDATE + 30),
    :valor,
    'PENDENTE',
    SYSDATE
  ) RETURNING id INTO l_id_fatura;

  COMMIT;

  -- Retorna 201 Created com Location header
  OWA_UTIL.status_line(201);
  OWA_UTIL.mime_header('application/json', FALSE);
  HTP.p('Location: /ords/api/faturas/v1/fatura/' || l_id_fatura);
  OWA_UTIL.http_header_close;
  
  APEX_JSON.open_object;
  APEX_JSON.write('id', l_id_fatura);
  APEX_JSON.write('message', 'Fatura criada com sucesso');
  APEX_JSON.close_object;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Erro ao criar fatura: ' || SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );

  --============================================================================
  -- 5. PUT /faturas/v1/fatura/:id — atualizar
  --============================================================================
  ORDS.define_handler(
    p_module_name    => 'faturas.v1',
    p_pattern        => 'fatura/:id',
    p_method         => 'PUT',
    p_source_type    => ORDS.source_type_plsql,
    p_mimes_allowed  => 'application/json',
    p_source         => q'[
BEGIN
  UPDATE faturas
     SET numero_fatura = NVL(:numero_fatura, numero_fatura),
         data_vencimento       = NVL(:data_vencimento, data_vencimento),
         valor         = NVL(:valor, valor),
         status         = NVL(:status, status),
         atualizado_em     = SYSDATE
   WHERE id = :id;

  IF SQL%ROWCOUNT = 0 THEN
    OWA_UTIL.status_line(404);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Fatura não encontrada: ' || :id);
    APEX_JSON.close_object;
    RETURN;
  END IF;

  COMMIT;

  OWA_UTIL.status_line(200);
  OWA_UTIL.mime_header('application/json', FALSE);
  OWA_UTIL.http_header_close;
  
  APEX_JSON.open_object;
  APEX_JSON.write('id', :id);
  APEX_JSON.write('message', 'Fatura atualizada com sucesso');
  APEX_JSON.close_object;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Erro ao atualizar: ' || SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );

  --============================================================================
  -- 6. DELETE /faturas/v1/fatura/:id — soft delete
  --============================================================================
  ORDS.define_handler(
    p_module_name    => 'faturas.v1',
    p_pattern        => 'fatura/:id',
    p_method         => 'DELETE',
    p_source_type    => ORDS.source_type_plsql,
    p_source         => q'[
BEGIN
  -- Soft delete (recomendado: preservar histórico)
  UPDATE faturas
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

  -- 204 No Content (DELETE bem-sucedido sem body)
  OWA_UTIL.status_line(204);
  OWA_UTIL.http_header_close;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('error', 'Erro ao excluir: ' || SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );

  COMMIT;
END;
/

--==============================================================================
-- 7. Definir privilege e role para autenticação (recomendado)
--==============================================================================

BEGIN
  -- Cria role
  ORDS.create_role(p_role_name => 'usuario_faturas');

  -- Define privilégio
  ORDS.define_privilege(
    p_privilege_name => 'priv.faturas.api',
    p_roles          => 'usuario_faturas',
    p_patterns       => '/faturas/v1/*',
    p_label          => 'API de Faturas',
    p_description    => 'Permite acesso aos endpoints de /faturas/v1/'
  );

  COMMIT;
END;
/

--==============================================================================
-- 8. Cria OAuth client (para integração com sistema externo)
--==============================================================================

BEGIN
  OAUTH.create_client(
    p_name            => 'sistema_integrador',
    p_grant_type      => 'client_credentials',
    p_owner           => 'APP',
    p_description     => 'Cliente OAuth para integração externa de faturas',
    p_support_email   => 'dba@example.com',
    p_privilege_names => 'priv.faturas.api'
  );

  COMMIT;
END;
/

-- Para obter access token:
-- POST /ords/api/oauth/token
-- Authorization: Basic base64(client_id:client_secret)
-- Body: grant_type=client_credentials

-- Para usar o token:
-- GET /ords/api/faturas/v1/fatura
-- Authorization: Bearer <access_token>


--==============================================================================
-- 9. Para listar/depurar configuração
--==============================================================================

-- Módulos definidos
SELECT module_name, pattern, status, items_per_page
  FROM user_ords_modules;

-- Templates de um módulo
SELECT m.module_name, t.pattern, t.priority
  FROM user_ords_modules m
  JOIN user_ords_templates t ON m.id = t.module_id
 WHERE m.module_name = 'faturas.v1';

-- Handlers
SELECT t.pattern, h.method, h.source_type
  FROM user_ords_templates t
  JOIN user_ords_handlers h ON t.id = h.template_id;
