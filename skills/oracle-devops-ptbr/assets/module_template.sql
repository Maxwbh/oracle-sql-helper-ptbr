-- ords/modules/{nome_modulo}_v{N}/module.sql
-- Template de módulo ORDS para versionamento no Git
-- M&S do Brasil LTDA — contato@msbrasil.inf.br
--
-- Substituir:
--   {MODULO}    → nome do módulo (ex: clientes)
--   {N}         → versão (ex: 1, 2, 3)
--   {BASE_PATH} → path base da API (ex: /clientes/v1/)
-- ─────────────────────────────────────────────────────────────────────────────

-- ============================================================
-- module.sql — Definição do módulo
-- ============================================================
BEGIN
  -- Remove módulo se existir (deploy idempotente)
  BEGIN
    ORDS.delete_module(p_module_name => '{MODULO}.v{N}');
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN NULL; -- Não falha se não existir
  END;

  ORDS.define_module(
    p_module_name    => '{MODULO}.v{N}',
    p_base_path      => '/{BASE_PATH}/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'API {MODULO} versão {N} — M&S do Brasil LTDA'
  );

  COMMIT;
END;
/

-- ============================================================
-- templates.sql — URI patterns do módulo
-- ============================================================

BEGIN
  -- Collection: GET lista / POST cria
  ORDS.define_template(
    p_module_name => '{MODULO}.v{N}',
    p_pattern     => '{MODULO}',
    p_priority    => 0,
    p_etag_type   => 'HASH',
    p_comments    => 'Collection — lista e criação'
  );

  -- Item: GET detalhe / PUT atualiza / DELETE remove
  ORDS.define_template(
    p_module_name => '{MODULO}.v{N}',
    p_pattern     => '{MODULO}/:id',
    p_priority    => 0,
    p_etag_type   => 'HASH',
    p_comments    => 'Item — detalhe, atualização e remoção'
  );

  COMMIT;
END;
/

-- ============================================================
-- handlers.sql — Implementação dos endpoints
-- ============================================================

BEGIN
  -- GET /collection — lista paginada
  ORDS.define_handler(
    p_module_name   => '{MODULO}.v{N}',
    p_pattern       => '{MODULO}',
    p_method        => 'GET',
    p_source_type   => ORDS.source_type_collection_query,
    p_items_per_page => 25,
    p_mimes_allowed => 'application/json',
    p_comments      => 'Lista {MODULO} paginada',
    p_source        => q'[
SELECT id,
       nome,
       status,
       criado_em
  FROM {MODULO}s
 WHERE (:status IS NULL OR status = :status)
 ORDER BY nome ASC
]'
  );

  -- GET /item/:id — detalhe
  ORDS.define_handler(
    p_module_name   => '{MODULO}.v{N}',
    p_pattern       => '{MODULO}/:id',
    p_method        => 'GET',
    p_source_type   => ORDS.source_type_collection_item,
    p_mimes_allowed => 'application/json',
    p_comments      => 'Detalhe de {MODULO} por ID',
    p_source        => q'[
SELECT id,
       nome,
       status,
       criado_em,
       atualizado_em
  FROM {MODULO}s
 WHERE id = :id
]'
  );

  -- POST /collection — criação
  ORDS.define_handler(
    p_module_name   => '{MODULO}.v{N}',
    p_pattern       => '{MODULO}',
    p_method        => 'POST',
    p_source_type   => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_comments      => 'Criar {MODULO}',
    p_source        => q'[
DECLARE
  l_id   {MODULO}s.id%TYPE;
  l_nome {MODULO}s.nome%TYPE := :nome;
BEGIN
  -- Validação básica
  IF l_nome IS NULL OR LENGTH(TRIM(l_nome)) = 0 THEN
    OWA_UTIL.status_line(400);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('erro', 'Campo obrigatório: nome');
    APEX_JSON.close_object;
    RETURN;
  END IF;

  INSERT INTO {MODULO}s (nome, status, criado_em, criado_por)
  VALUES (TRIM(l_nome), 'ATIVO', SYSDATE, :current_user)
  RETURNING id INTO l_id;

  COMMIT;

  OWA_UTIL.status_line(201);
  OWA_UTIL.mime_header('application/json', FALSE);
  HTP.p('Location: ' || OWA_UTIL.get_cgi_env('REQUEST_PROTOCOL') ||
        '://' || OWA_UTIL.get_cgi_env('HTTP_HOST') ||
        OWA_UTIL.get_cgi_env('REQUEST_URI') || '/' || l_id);
  OWA_UTIL.http_header_close;
  APEX_JSON.open_object;
  APEX_JSON.write('id', l_id);
  APEX_JSON.write('status', 'CRIADO');
  APEX_JSON.close_object;

EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    ROLLBACK;
    OWA_UTIL.status_line(409);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('erro', 'Registro duplicado');
    APEX_JSON.close_object;
  WHEN OTHERS THEN
    ROLLBACK;
    OWA_UTIL.status_line(500);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('erro', SQLERRM);
    APEX_JSON.close_object;
END;
]'
  );

  -- DELETE /item/:id — remoção (soft delete)
  ORDS.define_handler(
    p_module_name   => '{MODULO}.v{N}',
    p_pattern       => '{MODULO}/:id',
    p_method        => 'DELETE',
    p_source_type   => ORDS.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_comments      => 'Remover {MODULO} (soft delete)',
    p_source        => q'[
BEGIN
  UPDATE {MODULO}s
     SET status      = 'INATIVO',
         excluido_em = SYSDATE,
         excluido_por = :current_user
   WHERE id = :id;

  IF SQL%ROWCOUNT = 0 THEN
    OWA_UTIL.status_line(404);
    OWA_UTIL.mime_header('application/json', FALSE);
    OWA_UTIL.http_header_close;
    APEX_JSON.open_object;
    APEX_JSON.write('erro', 'Registro não encontrado: ' || :id);
    APEX_JSON.close_object;
    RETURN;
  END IF;

  COMMIT;
  OWA_UTIL.status_line(204);
  OWA_UTIL.http_header_close;
END;
]'
  );

  COMMIT;
END;
/

-- ============================================================
-- privileges.sql — Segurança do módulo
-- ============================================================

BEGIN
  -- Role leitores
  BEGIN
    ORDS.create_role(p_role_name => '{MODULO}_reader');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  -- Role escritores
  BEGIN
    ORDS.create_role(p_role_name => '{MODULO}_writer');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  -- Privilege de leitura (GET)
  ORDS.define_privilege(
    p_privilege_name => 'priv.{MODULO}.v{N}.read',
    p_roles          => OWA.vc_arr('{MODULO}_reader', '{MODULO}_writer'),
    p_patterns       => OWA.vc_arr('/{BASE_PATH}/*'),
    p_label          => 'Leitura {MODULO} v{N}',
    p_description    => 'Permite GET em /{BASE_PATH}/*'
  );

  -- Privilege de escrita (POST, PUT, DELETE)
  ORDS.define_privilege(
    p_privilege_name => 'priv.{MODULO}.v{N}.write',
    p_roles          => OWA.vc_arr('{MODULO}_writer'),
    p_patterns       => OWA.vc_arr('/{BASE_PATH}/*'),
    p_label          => 'Escrita {MODULO} v{N}',
    p_description    => 'Permite POST/PUT/DELETE em /{BASE_PATH}/*'
  );

  COMMIT;
END;
/
