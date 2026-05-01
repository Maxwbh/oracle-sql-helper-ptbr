--==============================================================================
-- Template: APEX Interactive Grid (24.2)
--
-- Interactive Grid (IG) é o substituto do Tabular Form a partir do APEX 22.
-- Permite edição em massa, sort/filter dinâmico, save selectivo.
-- 
-- Esta skill cobre os padrões mais comuns para CRUD em IG.
--==============================================================================


--==============================================================================
-- 1. Configuração básica de IG no APEX Builder
--==============================================================================

/*
CRIAR REGION:

  Region Type:                Interactive Grid
  Source Type:                SQL Query
  Source SQL:                 (a query — ver abaixo)
  
  Editing:
    Allow Edit:               On
    Allowed Operations:       Update, Insert, Delete (todos checados)
    Lost Update Type:         Row Values  (default, mais seguro)
  
  Pagination:
    Type:                     Page
    Number of Rows:           50
    Maximum Rows Per Page:    100
*/


--==============================================================================
-- 2. Query do IG — formato correto
--==============================================================================

-- A query DEVE incluir:
--   - PK da tabela (para identificar linhas em UPDATE/DELETE)
--   - Coluna ROWID ou versão (para Lost Update detection)
--   - Colunas que aparecem na grid

SELECT
    inv.id,                       -- PK obrigatória
    inv.numero_fatura,
    inv.id_cliente,
    cust.nome AS nome_cliente,   -- coluna readonly via JOIN
    inv.data_emissao,
    inv.data_vencimento,
    inv.valor,
    inv.status,
    inv.atualizado_em                -- usado para Lost Update Detection
  FROM faturas inv
  JOIN clientes cust ON inv.id_cliente = cust.id
 WHERE inv.ativo = 'Y'
   AND (:P10_FILTRO_STATUS IS NULL OR inv.status = :P10_FILTRO_STATUS);


--==============================================================================
-- 3. Configuração de colunas
--==============================================================================

/*
PARA CADA COLUNA, configure:

  ID:
    Type:                     Hidden
    Source Type:              Database Column
    Primary Key:              Yes  ← MUITO IMPORTANTE

  numero_fatura:
    Type:                     Text Field
    Source Type:              Database Column
    Source Column:            INVOICE_NUMBER
    Source Required:          Yes

  id_cliente:
    Type:                     Popup LOV
    Source Column:            CUSTOMER_ID
    LOV:                      SELECT nome AS d, id AS r FROM clientes ORDER BY nome

  nome_cliente:
    Type:                     Display Only
    Source Type:              SQL Query (single value)
    Source SQL:               SELECT nome FROM clientes WHERE id = :CUSTOMER_ID
    
  data_emissao / data_vencimento:
    Type:                     Date Picker
    Source Type:              Database Column
    Format Mask:              DD/MM/YYYY
  
  valor:
    Type:                     Number Field
    Source Type:              Database Column
    Format Mask:              FML999G999G990D00
  
  status:
    Type:                     Select List
    Source Type:              Database Column
    LOV:                      STATIC: Pendente,P;Pago,A;Cancelado,C
  
  atualizado_em:
    Type:                     Hidden
    Used as Lost Update Detection: Yes
*/


--==============================================================================
-- 4. Save Process — automatic vs custom PL/SQL
--==============================================================================

-- OPÇÃO A: Automatic Row Processing (mais simples, funciona para CRUD básico)
/*
PROCESSING ─→ ADD PROCESS:

  Type:                       Interactive Grid - Automatic Row Processing (DML)
  Region:                     <nome da IG>
  Settings:
    Lost Update Type:         Row Values
    Use Generic Column Names: No  ← se a tabela tem nomes customizados
*/


-- OPÇÃO B: Custom PL/SQL Process (controle total)
DECLARE
  l_nome_unidade CONSTANT VARCHAR2(60) := 'PAGE_10_IG_SAVE';
BEGIN
  -- Para cada linha modificada/inserida/deletada na grid
  FOR i IN 1..APEX_APPLICATION.G_F01.COUNT LOOP
    -- G_F01 vem do array de IDs (PK)
    -- APEX_APPLICATION.g_request_data tem 'I' (insert), 'U' (update), 'D' (delete)

    DECLARE
      l_id_linha     NUMBER := TO_NUMBER(APEX_APPLICATION.G_F01(i));
      l_acao_linha VARCHAR2(1);  -- 'I', 'U' ou 'D'
    BEGIN
      -- Action vem em outro array, depende da configuração
      -- Em geral, prefira Automatic Row Processing.
      -- Esta opção custom é para regras de negócio complexas.

      IF l_acao_linha = 'D' THEN
        UPDATE faturas SET ativo = 'N',
                            excluido_em = SYSDATE,
                            excluido_por = :APP_USER
         WHERE id = l_id_linha;
      
      ELSIF l_acao_linha = 'I' THEN
        -- INSERT lógica
        NULL;
      
      ELSIF l_acao_linha = 'U' THEN
        -- UPDATE com Lost Update check via atualizado_em
        -- (APEX faz isso automaticamente se "Lost Update Detection" estiver ON)
        UPDATE faturas
           SET valor     = TO_NUMBER(APEX_APPLICATION.G_F05(i)),
               status     = APEX_APPLICATION.G_F07(i),
               atualizado_em = SYSDATE,
               atualizado_por = :APP_USER
         WHERE id = l_id_linha
           AND atualizado_em = TO_TIMESTAMP(APEX_APPLICATION.G_F08(i),
                                         'YYYY-MM-DD HH24:MI:SS.FF');
        
        IF SQL%ROWCOUNT = 0 THEN
          raise_application_error(-20100,
            'Linha ' || l_id_linha || ' foi alterada por outro usuário. Recarregue.');
        END IF;
      END IF;
    END;
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    APEX_DEBUG.error('Erro em ' || l_nome_unidade || ': ' || SQLERRM);
    APEX_ERROR.add_error(
      p_mensagem          => SQLERRM,
      p_display_location => APEX_ERROR.c_inline_in_notification
    );
END;


--==============================================================================
-- 5. Validations no IG — múltiplas linhas
--==============================================================================

-- Validations no IG executam UMA VEZ por linha modificada
-- Use Validation Type: PL/SQL Function (returning Error Text)

DECLARE
  l_valor NUMBER := TO_NUMBER(:VALOR, '999G999G999D99', 'NLS_NUMERIC_CHARACTERS=,.');
BEGIN
  -- Validação por linha
  IF l_valor <= 0 THEN
    RETURN 'Valor da fatura deve ser maior que zero.';
  END IF;

  IF l_valor > 1000000 THEN
    RETURN 'Valor acima do limite. Aprovação manual necessária.';
  END IF;

  IF :DUE_DATE < :INVOICE_DATE THEN
    RETURN 'Data de vencimento não pode ser anterior à emissão.';
  END IF;

  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RETURN 'Erro de validação: ' || SQLERRM;
END;


--==============================================================================
-- 6. JavaScript hooks no IG
--==============================================================================

/*
EVENT: After Refresh do IG (recarregou dados)
  Region:           Interactive Grid - <nome>
  Action:           Execute JavaScript Code

// Exemplo: destacar linhas com valor > 10000
function highlightHighValueRows() {
  var grid = apex.region("ig_invoices").widget().interactiveGrid("getViews", "grid");
  var model = grid.model;
  
  model.forEach(function(record, index, id) {
    var valor = parseFloat(model.getValue(record, "VALOR"));
    if (valor > 10000) {
      var $row = grid.view$.find("tr[data-id='" + id + "']");
      $row.addClass("high-value");
    }
  });
}

highlightHighValueRows();
*/


--==============================================================================
-- 7. Programmatic — adicionar linha via JS
--==============================================================================

/*
// True Action: Execute JavaScript Code

var grid = apex.region("ig_invoices").widget().interactiveGrid("getViews", "grid");
var model = grid.model;
var record = model.insertNewRecord();

// Pré-popula com defaults
model.setValue(record, "INVOICE_DATE", new Date().toISOString().split('T')[0]);
model.setValue(record, "STATUS", "P");

// Foca no primeiro campo editável
grid.gotoCell(record, "INVOICE_NUMBER");
*/


--==============================================================================
-- 8. Programmatic — selecionar/desselecionar linhas
--==============================================================================

/*
// Selecionar linhas com valor > 5000
var grid = apex.region("ig_invoices").widget().interactiveGrid("getViews", "grid");
var model = grid.model;
var selectedIds = [];

model.forEach(function(record, index, id) {
  if (parseFloat(model.getValue(record, "VALOR")) > 5000) {
    selectedIds.push(id);
  }
});

grid.setSelectedRecords(model.getRecords(selectedIds));
*/


--==============================================================================
-- 9. Bulk Actions — Custom Toolbar Button
--==============================================================================

/*
ATTRIBUTES da Region IG:
  Toolbar:
    Add Custom Button:
      Label:                  Marcar como Pago
      Action:                 Defined by Dynamic Action
      Static ID:              btn-mark-paid

DYNAMIC ACTION:
  When (Event):               Click
  Selection Type:              jQuery Selector
  jQuery Selector:             #btn-mark-paid
  
  True Action 1: Confirm
    Text:                     Marcar selecionados como pagos?
  
  True Action 2: Execute JavaScript
    Code:
      // Coleta IDs selecionados
      var grid = apex.region("ig_invoices").widget().interactiveGrid("getViews", "grid");
      var selected = grid.getSelectedRecords();
      
      var ids = selected.map(function(r) {
        return grid.model.getValue(r, "ID");
      });
      
      // Chama AJAX callback
      apex.server.process("MARK_AS_PAID", {
        x01: ids.join(",")
      }, {
        dataType: "json",
        success: function(data) {
          if (data.error) {
            apex.message.alert("Erro: " + data.error);
            return;
          }
          apex.region("ig_invoices").refresh();
          apex.message.showPageSuccess(data.count + " faturas atualizadas");
        }
      });
*/


-- AJAX Callback "MARK_AS_PAID"
DECLARE
  l_ids       APEX_T_NUMBER;
  l_qtd     NUMBER;
BEGIN
  -- Converte CSV de IDs em coleção
  SELECT TO_NUMBER(REGEXP_SUBSTR(APEX_APPLICATION.G_X01, '[^,]+', 1, LEVEL))
    BULK COLLECT INTO l_ids
    FROM dual
 CONNECT BY REGEXP_SUBSTR(APEX_APPLICATION.G_X01, '[^,]+', 1, LEVEL) IS NOT NULL;

  -- Bulk update
  FORALL i IN l_ids.FIRST..l_ids.LAST
    UPDATE faturas
       SET status     = 'PAGO',
           pago_em    = SYSDATE,
           atualizado_em = SYSDATE,
           atualizado_por = :APP_USER
     WHERE id = l_ids(i)
       AND status <> 'PAGO';

  l_qtd := SQL%ROWCOUNT;
  COMMIT;

  APEX_JSON.open_object;
  APEX_JSON.write('count', l_qtd);
  APEX_JSON.close_object;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    APEX_JSON.open_object;
    APEX_JSON.write('error', SQLERRM);
    APEX_JSON.close_object;
END;


--==============================================================================
-- 10. Anti-patterns IG
--==============================================================================

/*
ANTI-PATTERN 1: Query do IG sem PK
  Sem PK, IG não consegue identificar linhas para UPDATE/DELETE.
  → Sempre inclua a coluna PK e marque "Primary Key: Yes"

ANTI-PATTERN 2: Editar coluna que vem de JOIN sem trigger
  nome_cliente vem de JOIN com clientes. Editar nome_cliente não
  atualiza clientes automaticamente.
  → Use Display Only para colunas read-only de JOIN
  → Para editar, use Popup LOV no id_cliente

ANTI-PATTERN 3: Sem Lost Update Detection em ambiente multi-usuário
  Dois usuários editam a mesma linha. Quem salvar último sobrescreve sem aviso.
  → Sempre habilite Lost Update Detection
  → Coluna atualizado_em no SELECT da query

ANTI-PATTERN 4: Volume gigante na grid
  IG carrega 10000 linhas em memória do browser → trava.
  → Limite Maximum Rows. Use filtro server-side.

ANTI-PATTERN 5: Custom PL/SQL Save quando Automatic Row Processing serve
  Custom é difícil de manter. Use Automatic Row Processing para CRUD comum.
  Custom só quando há regra que precisa controle total.

ANTI-PATTERN 6: Validation que faz SELECT pesado por linha
  Validation roda UMA VEZ POR LINHA. Se faz SELECT em outra tabela grande
  por linha, save de 100 linhas vira 100 selects.
  → Pré-carregue dados em APEX collection antes do save
  → Ou faça validação batch no save process custom
*/
