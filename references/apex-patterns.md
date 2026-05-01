# APEX — Padrões Application Express

Padrões para desenvolvimento Oracle APEX (Application Express). Foco em práticas que funcionam consistentemente em APEX 19+ e que evitam armadilhas comuns.

## Tipos de objetos APEX e quando usar cada um

| Objeto | Quando usar |
|---|---|
| **Page Process (PL/SQL)** | Lógica server-side disparada por evento de página (Submit, Load, etc.) |
| **AJAX Callback (On-Demand Process)** | Função PL/SQL chamada via JavaScript sem reload de página |
| **Dynamic Action** | Reação client-side a eventos (change, click, focus) com opção de PL/SQL |
| **Validation** | Validação server-side antes de processar Submit |
| **Computation** | Cálculo automático de item (Before Header, After Submit, etc.) |
| **Authorization Scheme** | Controle de acesso por usuário/role |
| **Application Process** | Processo global (todas as páginas), use com parcimônia |

Confunde-se Page Process com Dynamic Action constantemente. **Regra prática:**
- Se a ação não exige reload e é leve → Dynamic Action
- Se exige reload, transação ou cálculo pesado → Page Process

## Pagination — padrão correto

Pagination em APEX tem 3 níveis de configuração que DEVEM bater entre si:

### 1. Region attributes

Em Classic Report ou Interactive Report:

```
Pagination Type:    Row Ranges X to Y (with Set Pagination)
Number of Rows:     50  (ou variável :G_PAGE_SIZE)
Maximum Row Count:  10000
```

### 2. Query

A query NÃO deve ter `ORDER BY` complexo se a página tem muitos registros — APEX adiciona o `ROW_NUMBER()` automaticamente, mas mau ordenamento força full scan.

```sql
-- BOM (com index em criado_em DESC)
SELECT id, name, criado_em
  FROM clientes
 WHERE status = 'A'
 ORDER BY criado_em DESC;

-- RUIM (ordenação por função sem index)
SELECT id, name
  FROM clientes
 ORDER BY UPPER(name);  -- precisa de FBI ou vai full scan
```

### 3. Page Items para state

Mantenha o estado de pagination em items hidden:

```
P1_PAGE_NUMBER       (Hidden, Protected)
P1_ROWS_PER_PAGE     (Hidden, Protected, default :G_PAGE_SIZE)
```

E preserve em chamadas AJAX:

```javascript
apex.server.process('REFRESH_REPORT', {
  pageItems: '#P1_PAGE_NUMBER,#P1_ROWS_PER_PAGE'
}, {
  success: function(data) { /* ... */ }
});
```

### Anti-pattern comum

Recomputar a query inteira a cada paginação. APEX faz isso por padrão se o cache da region é "Always Refresh". Para volumes grandes:

- Use **`Cache Region: Yes`** quando os dados não mudam por sessão
- Habilite **server-side caching** se o resultado é compartilhável entre usuários

## Dynamic Actions

### Estrutura típica

Dynamic Action tem:
- **Event** (When): mudança em item, click em botão, page load, custom event
- **Affected Elements** (What): item, region, ou jQuery Selector
- **True Action** / **False Action**: o que executar

### Padrão PL/SQL → JavaScript

Quando um Dynamic Action precisa rodar PL/SQL e devolver resultado para JS:

```sql
-- True Action: Execute PL/SQL Code
DECLARE
  l_total NUMBER;
BEGIN
  SELECT SUM(valor) INTO l_total
    FROM faturas
   WHERE id_cliente = :P10_ID_CLIENTE;

  -- Set item via APEX_UTIL ou via Items to Return
  :P10_TOTAL := l_total;
END;

-- Items to Submit: P10_ID_CLIENTE
-- Items to Return: P10_TOTAL
```

E no JS subsequente (próxima True Action: Execute JavaScript):

```javascript
// P10_TOTAL agora tem o valor calculado
var total = apex.item('P10_TOTAL').getValue();
$('#total-display').text('R$ ' + total);
```

### Quando NÃO usar Dynamic Action

- Validação que afeta múltiplos items relacionados → use Validation com Submit
- Cálculo que precisa de transação → Page Process
- Lógica que depende de session state pesado → Page Process

## AJAX Callback (On-Demand Process)

Para chamar PL/SQL do client-side sem reload, use AJAX Callback (Application-level Process tipo "AJAX Callback") ou Page-level "AJAX Callback":

```sql
-- AJAX Callback: GET_INVOICE_TOTAL
DECLARE
  l_total NUMBER;
  l_json  CLOB;
BEGIN
  SELECT SUM(valor) INTO l_total
    FROM faturas
   WHERE id_cliente = APEX_APPLICATION.G_X01;

  -- Retornar JSON para o cliente
  APEX_JSON.open_object;
  APEX_JSON.write('id_cliente', APEX_APPLICATION.G_X01);
  APEX_JSON.write('total', l_total);
  APEX_JSON.close_object;
EXCEPTION
  WHEN OTHERS THEN
    -- Erro também retorna JSON (não HTTP 500 sempre)
    APEX_JSON.open_object;
    APEX_JSON.write('error', SQLERRM);
    APEX_JSON.close_object;
END;
```

JavaScript no client:

```javascript
apex.server.process('GET_INVOICE_TOTAL', {
  x01: $v('P10_ID_CLIENTE')
}, {
  dataType: 'json',
  success: function(data) {
    if (data.error) {
      apex.message.alert('Erro: ' + data.error);
      return;
    }
    $('#total-display').text('R$ ' + data.total);
  }
});
```

### Convenções

- **APEX_APPLICATION.G_X01 a G_X10**: parâmetros simples passados via AJAX
- **APEX_APPLICATION.G_F01 a G_F50**: arrays (multi-row submit, checkbox lists)
- **APEX_JSON**: sempre prefira para retorno estruturado
- **HTP.p()**: ainda válido para retorno texto puro, mas raro

## Validations

### Padrão "PL/SQL Function returning Error Text"

```sql
DECLARE
  l_qtd NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_qtd
    FROM clientes
   WHERE cpf = :P10_CPF
     AND id <> NVL(:P10_ID_CLIENTE, 0);  -- exclui o próprio em edição

  IF l_qtd > 0 THEN
    RETURN 'CPF já cadastrado para outro cliente.';
  END IF;

  -- Valida formato (regra de negócio adicional)
  IF NOT validate_cpf(:P10_CPF) THEN
    RETURN 'CPF informado é inválido.';
  END IF;

  RETURN NULL;  -- NULL = passou na validação
EXCEPTION
  WHEN OTHERS THEN
    RETURN 'Erro ao validar CPF: ' || SQLERRM;
END;
```

### Validations vs PL/SQL Process

- **Validation:** verifica e retorna erro antes do Submit processar. Não modifica dados.
- **Process:** modifica dados após validations passarem.

Não misture: validation que faz UPDATE é antipattern.

## Authorization Schemes

### Tipos

| Tipo | Uso |
|---|---|
| **Exists SQL Query** | Usuário existe em tabela X com permissão Y |
| **NOT Exists SQL Query** | Usuário NÃO está em blocklist |
| **PL/SQL Function** | Lógica complexa de autorização |
| **Item in Expression 1 IS in Expression 2** | Comparação simples de items |

### Exemplo PL/SQL Function

```sql
CREATE OR REPLACE FUNCTION user_has_role(
  p_role IN VARCHAR2
) RETURN BOOLEAN IS
  l_qtd NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_qtd
    FROM user_roles
   WHERE username = :APP_USER
     AND role_name = p_role;

  RETURN l_qtd > 0;
END;
```

Use no Authorization Scheme:

```sql
RETURN user_has_role('ADMIN');
```

### Cache de authorization

APEX cacheia por **session** ou **request**:
- **Once per session:** rápido mas mudança de role exige logout
- **Once per page view:** verifica a cada página, balanceado
- **Always (no caching):** sempre verifica, mais seguro mas custoso

Para roles que mudam dinâmicamente, use "Once per page view".

## Items APEX

### Tipos comuns

| Tipo | Uso típico |
|---|---|
| Text Field | Input simples |
| Select List | Dropdown estático ou de query |
| Popup LOV | Lista grande com search |
| Date Picker | Datas com calendar |
| Display Only | Read-only |
| Hidden | Estado interno |
| Switch | Boolean Y/N |

### Items hidden — padrão protected

```
P10_ID_CLIENTE
  Type: Hidden
  Value Protected: Yes  ← sempre Yes para PKs e dados sensíveis
```

Sem proteção, JavaScript no client pode alterar e fazer mass assignment ataque.

### Default values

Use **PL/SQL Expression** ou **Function Body** para defaults dinâmicos:

```sql
-- Default value: data de hoje
SYSDATE

-- Default value: usuário atual
:APP_USER

-- Default value: PL/SQL function
DECLARE
  l_id NUMBER;
BEGIN
  SELECT NVL(MAX(numero_fatura), 0) + 1 INTO l_id FROM faturas;
  RETURN l_id;
END;
```

## Session State

### APEX_UTIL package

```sql
-- Set item value programaticamente
APEX_UTIL.set_session_state('P10_ID_CLIENTE', 12345);

-- Get item value
l_value := APEX_UTIL.get_session_state('P10_ID_CLIENTE');
```

### Sintaxe abreviada

Em PL/SQL dentro de APEX:
```sql
-- Lendo
:P10_ID_CLIENTE  -- equivalente a APEX_UTIL.get_session_state

-- Setando (não funciona em qualquer contexto — use APEX_UTIL para garantir)
:P10_ID_CLIENTE := 12345;
```

## Anti-patterns APEX

| Anti-pattern | Impacto |
|---|---|
| Reports sem pagination com >1000 linhas | Browser trava |
| Authorization "Always" em items individuais | N+1 queries |
| PL/SQL inline em Region Source com lógica complexa | Difícil manutenção |
| Items sensíveis sem `Value Protected: Yes` | Mass assignment vulnerability |
| Dynamic Actions encadeados profundamente | Comportamento imprevisível |
| Validações em Page Process | Erro é re-raise feio em vez de mensagem amigável |
| `apex.message.alert()` para erros frequentes | UX ruim — use Inline Error |

## Linkagem

- Templates prontos em `assets/apex_dynamic_action.sql`, `assets/apex_pagination_pattern.sql`, `assets/apex_pl_sql_process.sql`
- Para PL/SQL puro chamado por APEX → `plsql-trivadis-guidelines.md`
- Para queries lentas em reports → `performance-tuning.md`
