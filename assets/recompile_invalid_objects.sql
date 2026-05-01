--==============================================================================
-- Template: Recompilar Objetos Inválidos
--
-- Identificar e recompilar objetos PL/SQL invalidados após mudanças
-- (alterações em tabelas, types, dependências, etc).
--
-- Pré-requisitos:
--   - DBA ou ALTER ANY PROCEDURE/PACKAGE/TYPE/TRIGGER
--   - Privilégio EXECUTE em DBMS_UTILITY
--==============================================================================


--==============================================================================
-- 1. Listar objetos inválidos no schema atual
--==============================================================================

SELECT object_name, object_type, status, last_ddl_time
  FROM user_objects
 WHERE status = 'INVALIDO'
 ORDER BY object_type, object_name;


--==============================================================================
-- 2. Listar invalid objects em schema específico (precisa privilégio)
--==============================================================================

SELECT owner, object_name, object_type, status, last_ddl_time
  FROM dba_objects
 WHERE status = 'INVALIDO'
   AND owner = 'APP_OWNER'  -- ← substitua pelo schema
 ORDER BY object_type, object_name;


--==============================================================================
-- 3. Listar invalid objects em todos os schemas (visão geral)
--==============================================================================

SELECT owner, object_type,
       COUNT(*) AS qty_invalid
  FROM dba_objects
 WHERE status = 'INVALIDO'
   AND owner NOT IN ('SYS', 'SYSTEM', 'XDB', 'CTXSYS', 'MDSYS', 'ORDDATA',
                     'OUTLN', 'GSMADMIN_INTERNAL', 'AUDSYS', 'WMSYS',
                     'OJVMSYS', 'DBSNMP', 'APPQOSSYS', 'DVF', 'DVSYS',
                     'GSMUSER', 'OLAPSYS', 'ORDPLUGINS', 'SI_INFORMTN_SCHEMA',
                     'XS$NULL', 'LBACSYS', 'GSMCATUSER', 'PUBLIC')
 GROUP BY owner, object_type
 ORDER BY owner, object_type;


--==============================================================================
-- 4. Recompilar schema inteiro — DBMS_UTILITY.compile_schema
--==============================================================================

-- Recompila apenas inválidos (recomendado, mais rápido)
BEGIN
  DBMS_UTILITY.compile_schema(
    schema      => 'APP_OWNER',  -- ← substitua pelo schema
    compile_all => FALSE         -- FALSE: só inválidos | TRUE: todos
  );
END;
/

-- Verificar resultado
SELECT object_name, object_type, status
  FROM dba_objects
 WHERE owner = 'APP_OWNER'
   AND status = 'INVALIDO'
 ORDER BY object_name;


--==============================================================================
-- 5. Recompilar objeto individual
--==============================================================================

-- Package (spec + body)
ALTER PACKAGE app_owner.payment_pkg COMPILE;
ALTER PACKAGE app_owner.payment_pkg COMPILE BODY;

-- Procedure
ALTER PROCEDURE app_owner.processar_fatura COMPILE;

-- Function
ALTER FUNCTION app_owner.calcular_imposto COMPILE;

-- Type (cuidado: pode invalidar dependentes)
ALTER TYPE app_owner.t_invoice COMPILE;
ALTER TYPE app_owner.t_invoice COMPILE BODY;

-- View
ALTER VIEW app_owner.v_active_invoices COMPILE;

-- Trigger
ALTER TRIGGER app_owner.trg_invoice_audit COMPILE;

-- Synonym (raramente fica inválido — geralmente alvo desapareceu)
ALTER SYNONYM app_owner.faturas COMPILE;


--==============================================================================
-- 6. Verificar erros de compilação
--==============================================================================

-- Erros do schema atual (após recompile)
SELECT nome, type, line, position, text
  FROM user_errors
 ORDER BY nome, sequence;

-- Erros em outro schema (precisa privilégio)
SELECT owner, nome, type, line, position, text
  FROM dba_errors
 WHERE owner = 'APP_OWNER'
 ORDER BY owner, nome, sequence;

-- Erros de UM objeto específico
SELECT line, position, text
  FROM user_errors
 WHERE nome = 'PAYMENT_PKG'
   AND type = 'PACKAGE BODY'
 ORDER BY sequence;


--==============================================================================
-- 7. Recompile com utlrp.sql — Oracle script padrão
--==============================================================================

-- Para casos pesados (após upgrade, patch, mudança grande de schema):
-- Execute como SYS/SYSDBA. Recompila tudo em paralelo, ordena dependências.
--
-- @?/rdbms/admin/utlrp.sql
--
-- O ? é variável Oracle que aponta para $ORACLE_HOME.
-- Demora — pode ser longo em bancos grandes.


--==============================================================================
-- 8. Identificar dependências (entender por que algo invalidou)
--==============================================================================

-- Objetos dos quais MEU PACKAGE depende
SELECT referenced_owner, referenced_name, referenced_type
  FROM user_dependencies
 WHERE nome = 'PAYMENT_PKG'
   AND type = 'PACKAGE BODY'
 ORDER BY referenced_owner, referenced_name;

-- Objetos que dependem do MEU PACKAGE (impactados se eu alterar)
SELECT owner, nome, type
  FROM dba_dependencies
 WHERE referenced_owner = 'APP_OWNER'
   AND referenced_name = 'PAYMENT_PKG'
   AND referenced_type = 'PACKAGE'
 ORDER BY owner, nome;


--==============================================================================
-- 9. Causas comuns de invalidação
--==============================================================================

/*
1. ALTER TABLE em tabela usada pelo package
   - Solução: ALTER PACKAGE ... COMPILE BODY

2. Privilégio revogado
   - Identificar:
     SELECT grantee, privilege, granted_role 
       FROM dba_role_privs WHERE grantee = 'APP_OWNER';
   - Solução: regrant

3. TYPE alterado (ALTER TYPE)
   - Cascade de invalidação: package usando o type também invalida
   - Recompile em ordem: TYPE → TYPE BODY → packages dependentes

4. Synonym apontando para objeto deletado
   - Identificar:
     SELECT * FROM dba_synonyms 
      WHERE owner = 'APP_OWNER' 
        AND table_name NOT IN (SELECT object_name FROM dba_objects);
   - Solução: recriar synonym ou apontar para novo destino

5. Patch ou upgrade do Oracle
   - Padrão: rodar utlrp.sql pós-instalação

6. RECYCLE BIN cheio (raro)
   - Verificar: SELECT * FROM dba_recyclebin;
   - Limpar: PURGE DBA_RECYCLEBIN;
*/


--==============================================================================
-- 10. Workflow recomendado para pós-deployment
--==============================================================================

/*
Após deploy de mudanças no schema:

1. Identifique invalid objects:
   SELECT object_name, object_type FROM user_objects WHERE status = 'INVALIDO';

2. Recompile schema:
   EXEC DBMS_UTILITY.compile_schema(schema => USER, compile_all => FALSE);

3. Verifique se algo restou inválido:
   SELECT object_name, object_type FROM user_objects WHERE status = 'INVALIDO';

4. Para cada objeto restante, veja erros específicos:
   SELECT line, position, text FROM user_errors 
    WHERE nome = '...' ORDER BY sequence;

5. Corrija a causa raiz (não tente compilar repetidamente esperando milagre):
   - Se é privilégio: regrant
   - Se é DDL faltando: aplique
   - Se é bug no código: corrija

6. Após correção, recompile o objeto específico:
   ALTER PACKAGE ... COMPILE BODY;
   ALTER PROCEDURE ... COMPILE;
*/
