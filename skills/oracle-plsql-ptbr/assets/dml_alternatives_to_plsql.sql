--==============================================================================
-- Template: Alternativas DML/SQL puro em vez de PL/SQL
--
-- Princípio Tim Hall (Oracle ACE): "PL/SQL é extensão de SQL, não substituto.
-- Na maioria dos casos, SQL puro performa melhor que PL/SQL+SQL combinados."
--
-- Este template mostra 5 cenários onde PL/SQL é tentador mas SQL/DML resolve
-- com performance ordens de magnitude superior:
--
--   1. MERGE em vez de loop+IF EXISTS+UPDATE/INSERT
--   2. DBMS_ERRLOG (DML error logging) em vez de FORALL SAVE EXCEPTIONS
--   3. Multitable INSERT em vez de múltiplos INSERTs
--   4. External Tables em vez de UTL_FILE para ler arquivos
--   5. CTAS / INSERT SELECT em vez de PL/SQL para popular tabelas
--==============================================================================


--==============================================================================
-- CENÁRIO 1: MERGE — Upsert sem PL/SQL
--
-- Pergunta: "Para cada linha em ORIGEM, atualize em DESTINO se existe,
--            insira se não existe."
--==============================================================================

-- ANTI-PATTERN: PL/SQL com IF EXISTS
DECLARE
  l_qtd NUMBER;
BEGIN
  FOR r IN (SELECT id, nome, status FROM clientes_origem) LOOP
    SELECT COUNT(*) INTO l_qtd FROM clientes_destino WHERE id = r.id;

    IF l_qtd > 0 THEN
      UPDATE clientes_destino
         SET nome = r.nome, status = r.status
       WHERE id = r.id;
    ELSE
      INSERT INTO clientes_destino (id, nome, status)
      VALUES (r.id, r.nome, r.status);
    END IF;
  END LOOP;
  COMMIT;
END;
/

-- BOM: MERGE em SQL puro
MERGE INTO clientes_destino d
USING clientes_origem o
   ON (d.id = o.id)
WHEN MATCHED THEN
  UPDATE SET d.nome = o.nome, d.status = o.status
  WHERE d.nome <> o.nome OR d.status <> o.status  -- evita updates desnecessários
WHEN NOT MATCHED THEN
  INSERT (id, nome, status)
  VALUES (o.id, o.nome, o.status);

COMMIT;

-- Vantagens do MERGE:
--   - Single context switch SQL ↔ PL/SQL (vs N para PL/SQL loop)
--   - Paralelizável: ALTER SESSION ENABLE PARALLEL DML; depois usar /*+ PARALLEL */
--   - Otimizador escolhe o melhor plano de execução para o conjunto
--   - DELETE clause disponível (MERGE WHEN MATCHED THEN DELETE WHERE ...)


-- MERGE com DELETE — exclui linhas em destino que não existem mais em origem
MERGE INTO clientes_destino d
USING clientes_origem o
   ON (d.id = o.id)
WHEN MATCHED THEN
  UPDATE SET d.nome = o.nome, d.status = o.status
  DELETE WHERE o.excluido = 'S'   -- exclui se origem marcou como deletado
WHEN NOT MATCHED THEN
  INSERT (id, nome, status) VALUES (o.id, o.nome, o.status);


--==============================================================================
-- CENÁRIO 2: DBMS_ERRLOG — DML error logging em vez de FORALL SAVE EXCEPTIONS
--
-- Pergunta: "Quero processar 1M de linhas. Algumas vão falhar (constraint,
--            tipo, etc). Quero capturar os erros sem abortar o batch."
--==============================================================================

-- ANTI-PATTERN: FORALL SAVE EXCEPTIONS
DECLARE
  TYPE t_lista_faturas IS TABLE OF faturas_origem%ROWTYPE;
  l_faturas    t_lista_faturas;
  l_qtd_erros  NUMBER;
  e_erros_bulk EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_erros_bulk, -24381);
BEGIN
  SELECT * BULK COLLECT INTO l_faturas FROM faturas_origem;

  BEGIN
    FORALL i IN l_faturas.FIRST..l_faturas.LAST SAVE EXCEPTIONS
      INSERT INTO faturas_destino VALUES l_faturas(i);
  EXCEPTION
    WHEN e_erros_bulk THEN
      l_qtd_erros := SQL%BULK_EXCEPTIONS.COUNT;
      FOR j IN 1..l_qtd_erros LOOP
        INSERT INTO log_erros_bulk (indice_registro, mensagem_erro)
        VALUES (
          SQL%BULK_EXCEPTIONS(j).ERROR_INDEX,
          SQLERRM(-SQL%BULK_EXCEPTIONS(j).ERROR_CODE)
        );
      END LOOP;
  END;
  COMMIT;
END;
/

-- BOM: DBMS_ERRLOG + DML único
-- Setup (uma vez): cria tabela err$_faturas_destino automaticamente
EXEC DBMS_ERRLOG.create_error_log(dml_table_name => 'FATURAS_DESTINO');

-- Uso: INSERT padrão com cláusula LOG ERRORS
INSERT INTO faturas_destino
SELECT * FROM faturas_origem
LOG ERRORS INTO err$_faturas_destino ('insert_faturas_2024')
REJECT LIMIT UNLIMITED;

COMMIT;

-- Consultar erros após execução
SELECT ora_err_number$, ora_err_mesg$, ora_err_tag$, id, id_cliente
  FROM err$_faturas_destino
 WHERE ora_err_tag$ = 'insert_faturas_2024'
 ORDER BY ora_err_number$;

-- Vantagens DBMS_ERRLOG:
--   - DML único (paralelizável, otimizável)
--   - Sem PGA explosão (não carrega coleção inteira em memória)
--   - Compatível com UPDATE, DELETE, MERGE também
--   - Erros persistem em tabela: análise SQL posterior, não logger transitório


-- Mesmo padrão para UPDATE e MERGE
UPDATE faturas
   SET status = 'PROCESSADO'
 WHERE id_lote = 100
   LOG ERRORS INTO err$_faturas ('lote_100_update')
   REJECT LIMIT UNLIMITED;


--==============================================================================
-- CENÁRIO 3: Multitable INSERT — várias tabelas em uma DML
--
-- Pergunta: "Para cada linha origem, inserir em faturas E criar registro
--            em log_auditoria E criar entrada em fila_processamento."
--==============================================================================

-- ANTI-PATTERN: 3 INSERTs em loop
DECLARE
BEGIN
  FOR r IN (SELECT * FROM dados_origem) LOOP
    INSERT INTO faturas (id, valor) VALUES (r.id, r.valor);
    INSERT INTO log_auditoria (operacao, id_registro, ts) VALUES ('INSERT_FATURA', r.id, SYSDATE);
    INSERT INTO fila_processamento (id_registro, status) VALUES (r.id, 'PENDENTE');
  END LOOP;
  COMMIT;
END;
/

-- BOM: Multitable INSERT — uma DML, três destinos
INSERT ALL
  INTO faturas              (id, valor)              VALUES (id, valor)
  INTO log_auditoria        (operacao, id_registro, ts)
                            VALUES ('INSERT_FATURA', id, SYSDATE)
  INTO fila_processamento   (id_registro, status)    VALUES (id, 'PENDENTE')
SELECT id, valor FROM dados_origem;

COMMIT;


-- Multitable INSERT condicional (INSERT FIRST)
INSERT FIRST
  WHEN valor > 10000 THEN
    INTO faturas_alto_valor (id, valor) VALUES (id, valor)
    INTO log_auditoria (operacao, id_registro) VALUES ('ALTO_VALOR', id)
  WHEN valor BETWEEN 1000 AND 10000 THEN
    INTO faturas_regulares (id, valor) VALUES (id, valor)
  ELSE
    INTO faturas_pequenas (id, valor) VALUES (id, valor)
SELECT id, valor FROM dados_origem;


--==============================================================================
-- CENÁRIO 4: External Tables em vez de UTL_FILE para ler arquivos
--
-- Pergunta: "Preciso processar arquivo CSV de 10MB com 500k linhas."
--==============================================================================

-- ANTI-PATTERN: UTL_FILE com loop linha-a-linha
DECLARE
  l_arquivo UTL_FILE.file_type;
  l_linha   VARCHAR2(32767);
BEGIN
  l_arquivo := UTL_FILE.fopen('DIR_CARGA', 'faturas.csv', 'r');
  LOOP
    BEGIN
      UTL_FILE.get_line(l_arquivo, l_linha);
      -- Parse manualmente CSV...
      INSERT INTO staging_faturas (linha_bruta) VALUES (l_linha);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN EXIT;
    END;
  END LOOP;
  UTL_FILE.fclose(l_arquivo);
  COMMIT;
END;
/

-- BOM: External Table — Oracle lê e parseia o arquivo nativamente
-- Setup (uma vez):
CREATE OR REPLACE DIRECTORY dir_carga AS '/home/oracle/cargas';
GRANT READ, WRITE ON DIRECTORY dir_carga TO ms_app;

CREATE TABLE ext_faturas (
  id              NUMBER,
  id_cliente      NUMBER,
  valor           NUMBER(12,2),
  data_emissao    DATE
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY dir_carga
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    SKIP 1   -- pula header
    BADFILE dir_carga : 'faturas.bad'
    LOGFILE dir_carga : 'faturas.log'
    FIELDS TERMINATED BY ','
    OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
    (
      id,
      id_cliente,
      valor,
      data_emissao DATE 'YYYY-MM-DD'
    )
  )
  LOCATION ('faturas.csv')
)
REJECT LIMIT UNLIMITED;

-- Uso: SELECT na external table como tabela normal
INSERT INTO faturas_destino
SELECT id, id_cliente, valor, data_emissao
  FROM ext_faturas
 WHERE data_emissao >= DATE '2024-01-01'
LOG ERRORS INTO err$_faturas_destino ('carga_csv_2024')
REJECT LIMIT UNLIMITED;

COMMIT;

-- Vantagens External Tables:
--   - Parsing CSV nativo (sem regex manual)
--   - Paralelizável: ACCESS PARAMETERS PARALLEL
--   - Permite preprocessor (descompactar gz, executar comando antes de ler)
--   - Bad file e log file separados para análise
--   - Combinável com DBMS_ERRLOG para tratamento de erros


-- Preprocessor para arquivos compactados (Oracle 11gR2+)
CREATE TABLE ext_faturas_gz (
  -- mesmas colunas
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY dir_carga
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    PREPROCESSOR dir_executavel : 'descompactar_gz.sh'
    -- ...resto igual
  )
  LOCATION ('faturas_2024.csv.gz')
);


--==============================================================================
-- CENÁRIO 5: CTAS / INSERT SELECT em vez de PL/SQL para popular tabelas
--
-- Pergunta: "Preciso copiar dados transformados de uma tabela para outra."
--==============================================================================

-- ANTI-PATTERN: PL/SQL para copiar com transformação
DECLARE
  TYPE t_lista_faturas IS TABLE OF faturas_origem%ROWTYPE;
  l_faturas t_lista_faturas;
BEGIN
  SELECT * BULK COLLECT INTO l_faturas
    FROM faturas_origem
   WHERE data_emissao > SYSDATE - 365;

  FORALL i IN l_faturas.FIRST..l_faturas.LAST
    INSERT INTO arquivo_faturas (id, id_cliente, valor, arquivado_em)
    VALUES (
      l_faturas(i).id,
      l_faturas(i).id_cliente,
      l_faturas(i).valor * 1.05,  -- ajuste fictício
      SYSDATE
    );
  COMMIT;
END;
/

-- BOM: INSERT SELECT direto, com hint de paralelismo
ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ APPEND PARALLEL(arquivo_faturas, 4) */ INTO arquivo_faturas
       (id, id_cliente, valor, arquivado_em)
SELECT /*+ PARALLEL(faturas_origem, 4) */
       id, id_cliente, valor * 1.05, SYSDATE
  FROM faturas_origem
 WHERE data_emissao > SYSDATE - 365;

COMMIT;

-- Vantagens INSERT SELECT:
--   - Single SQL statement (otimizável)
--   - APPEND hint = direct-path insert (bypass buffer cache, MUITO rápido)
--   - PARALLEL hint = múltiplos slaves processando em paralelo
--   - NOLOGGING table option: minimiza redo (cuidado: incompatível com archivelog
--     em alguns casos, e perde redo para recovery do INSERT)


-- CTAS para criar tabela do zero (mais rápido que CREATE + INSERT)
CREATE TABLE arquivo_faturas_2024
  NOLOGGING
  PARALLEL 4
  AS
SELECT id, id_cliente, valor * 1.05 AS valor_ajustado, SYSDATE AS arquivado_em
  FROM faturas_origem
 WHERE data_emissao BETWEEN DATE '2024-01-01' AND DATE '2024-12-31';

-- Após CTAS com NOLOGGING, gere backup imediato — sem redo, recovery não funciona


--==============================================================================
-- DECISÃO RÁPIDA — quando usar SQL puro vs PL/SQL
--==============================================================================

/*
USE SQL PURO (DML único) quando:
  - Operação cabe em UMA dml com SELECT
  - Não há lógica condicional complexa por linha
  - Volume é grande (paralelismo ajuda)
  - Sem necessidade de logging por linha (ou DBMS_ERRLOG basta)
  - Sem necessidade de chamadas externas (HTTP, API) por linha

USE PL/SQL quando:
  - Lógica de negócio complexa por linha
  - Chamadas externas necessárias (API, web service, file)
  - Coordenação entre múltiplas operações com rollback parcial
  - Volume pequeno (overhead de PL/SQL não importa)
  - Cursor com fetch lento de fonte externa

EM AMBOS:
  - Documente a decisão com comentário (por que escolheu este caminho)
  - Em caso de dúvida, comece com SQL puro e vá para PL/SQL se necessário
  - Meça antes e depois (timing real, não chute)
*/


--==============================================================================
-- Anti-patterns adicionais
--==============================================================================

/*
ANTI-PATTERN 1: Loop em PL/SQL para chamar function que faz SELECT
  -- RUIM
  FOR r IN (SELECT id FROM clientes) LOOP
    l_total := l_total + obter_valor_fatura(r.id);  -- function faz SELECT
  END LOOP;

  -- BOM: JOIN em SQL puro
  SELECT SUM(NVL(f.valor, 0)) INTO l_total
    FROM clientes c
    LEFT JOIN faturas f ON c.id = f.id_cliente;


ANTI-PATTERN 2: Cursor para fazer transformação que SQL faz
  -- RUIM
  FOR r IN (SELECT nome FROM clientes) LOOP
    UPDATE clientes SET nome = INITCAP(r.nome) WHERE id = r.id;
  END LOOP;

  -- BOM
  UPDATE clientes SET nome = INITCAP(nome);


ANTI-PATTERN 3: Múltiplos UPDATEs em sequência quando UPDATE com CASE resolve
  -- RUIM
  UPDATE faturas SET status = 'VENCIDO' WHERE data_vencimento < SYSDATE;
  UPDATE faturas SET status = 'ALERTA' WHERE data_vencimento BETWEEN SYSDATE AND SYSDATE+7;
  UPDATE faturas SET status = 'OK' WHERE data_vencimento > SYSDATE+7;

  -- BOM
  UPDATE faturas
     SET status = CASE
                    WHEN data_vencimento < SYSDATE       THEN 'VENCIDO'
                    WHEN data_vencimento <= SYSDATE + 7  THEN 'ALERTA'
                    ELSE 'OK'
                  END
   WHERE status IS NULL OR status NOT IN ('PAGO', 'CANCELADO');
*/
