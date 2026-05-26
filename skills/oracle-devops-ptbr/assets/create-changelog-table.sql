-- create-changelog-table.sql
-- Cria a tabela de controle do changelog de banco de dados
-- M&S do Brasil LTDA — contato@msbrasil.inf.br
--
-- IMPORTANTE: Funciona corretamente quando o usuário de conexão é diferente
-- do schema alvo. Usa ALL_TABLES + SYS_CONTEXT('USERENV','CURRENT_SCHEMA')
-- em vez de USER_TABLES, pois USER_TABLES só enxerga o schema do usuário
-- conectado, não o schema definido por ALTER SESSION SET CURRENT_SCHEMA.
--
-- O apply_changelog.py executa ALTER SESSION SET CURRENT_SCHEMA = DB_SCHEMA
-- antes de chamar este script, garantindo que a tabela seja criada no
-- schema correto independentemente de qual usuário está conectado.
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE
  l_schema VARCHAR2(128) := SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
  l_exists NUMBER;
BEGIN
  -- ALL_TABLES + filtro por CURRENT_SCHEMA funciona com DBA conectado em schema alvo
  SELECT COUNT(*)
    INTO l_exists
    FROM all_tables
   WHERE table_name = 'DB_CHANGELOG'
     AND owner      = l_schema;

  IF l_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE db_changelog (
        id             VARCHAR2(20)   NOT NULL,
        descricao      VARCHAR2(500)  NOT NULL,
        arquivo        VARCHAR2(500)  NOT NULL,
        tipo           VARCHAR2(10)   NOT NULL,
        checksum       VARCHAR2(64)   NOT NULL,
        aplicado_em    DATE           DEFAULT SYSDATE NOT NULL,
        aplicado_por   VARCHAR2(100)  DEFAULT USER    NOT NULL,
        duracao_ms     NUMBER,
        ambiente       VARCHAR2(10),
        CONSTRAINT pk_db_changelog PRIMARY KEY (id)
      )
    ';

    EXECUTE IMMEDIATE
      'COMMENT ON TABLE db_changelog IS
       ''Controle de migrations — gerenciado por apply_changelog.py''';

    DBMS_OUTPUT.put_line('Tabela db_changelog criada em schema: ' || l_schema);
  ELSE
    DBMS_OUTPUT.put_line('db_changelog já existe em schema: ' || l_schema || ' — nenhuma ação.');
  END IF;
END;
/

-- Confirmar estrutura
SELECT column_name, data_type, data_length, nullable
  FROM all_tab_columns
 WHERE table_name = 'DB_CHANGELOG'
   AND owner      = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
 ORDER BY column_id;
