# oracle-skills-ptbr

**Skills Claude para Oracle — Stack Completa em Português**

7 Skills do Claude cobrindo toda a stack Oracle (PL/SQL, APEX, ORDS, DBA, Performance, Trivadis Guidelines e DevOps/CI-CD), desenvolvidas pela **M&S do Brasil LTDA** para uso profissional em projetos Oracle 19c + APEX 24.2 + ORDS.

---

## Desenvolvedor

**Maxwell da Silva Oliveira**  
M&S do Brasil LTDA — [msbrasil.inf.br](https://msbrasil.inf.br)  
✉ contato@msbrasil.inf.br · 🐙 [@maxwbh](https://github.com/maxwbh)

---

## Skills disponíveis

| Skill | Versão | Escopo | Tamanho |
|---|---|---|---|
| `oracle-plsql-ptbr` | 2.0.0 | PL/SQL 19c, packages, LOBs, EBR, triggers, Logger | 35K |
| `oracle-apex-ptbr` | 2.0.0 | APEX 24.2 development + Data Dictionary completo | 36K |
| `oracle-ords-ptbr` | 2.0.0 | ORDS REST services + Data Dictionary (USER/DBA_ORDS_*) | 19K |
| `oracle-dba-ptbr` | 2.0.0 | DBA operacional + Oracle Data Dictionary (V$, DBA_*, CDB_*) | 24K |
| `oracle-tuning-ptbr` | 2.0.0 | Performance tuning, AWR, ASH, explain plan, indexes | 17K |
| `oracle-trivadis-ptbr` | 2.0.0 | Trivadis Guidelines 4.4 — nomenclatura e revisão de código | 7K |
| `oracle-devops-ptbr` | 3.1.0 | Git, CI/CD, changelog Oracle, deploy Python + oracledb | 47K |

---

## Instalação

### Via arquivo `.skill` (Claude.ai)

1. Baixe os arquivos `.skill` da pasta [`dist/`](./dist/)
2. No Claude.ai → **Settings** → **Skills** → arraste ou clique em **Upload**
3. Repita para cada skill desejada

### Stack completa (recomendado)

```bash
# Baixar todos os .skill e instalar um por um
dist/oracle-plsql-ptbr.skill
dist/oracle-apex-ptbr.skill
dist/oracle-ords-ptbr.skill
dist/oracle-dba-ptbr.skill
dist/oracle-tuning-ptbr.skill
dist/oracle-trivadis-ptbr.skill
dist/oracle-devops-ptbr.skill
```

---

## Quando cada skill é ativada

### oracle-plsql-ptbr
`BULK COLLECT` · `FORALL` · `NOCOPY` · `EXECUTE IMMEDIATE` · `MERGE INTO` · compound trigger · EBR · CLOB/BLOB · Logger · package · procedure · function

```
"Criar um package para processar pagamentos"
"Refatorar esse loop para BULK COLLECT"
"Como usar EBR para deploy sem downtime?"
```

### oracle-apex-ptbr
APEX · Dynamic Action · Interactive Report · Interactive Grid · Page Process · AJAX Callback · `APEX_APPLICATION_*` · `APEX_WORKSPACE_*` · Workflows · AI configs · JSON Sources

```
"Como auditar a paginação dos meus IRs?"
"Diferença entre Page Process e Dynamic Action"
"Como verificar pages sem authorization scheme?"
```

### oracle-ords-ptbr
ORDS · `define_module` · `define_handler` · AutoREST · OAuth · `ORDS_SECURITY` · JWT · PAR · `USER_ORDS_*` · `DBA_ORDS_*`

```
"Criar endpoint REST com autenticação OAuth"
"Inventário de todos os handlers ORDS"
"Como migrar do OAUTH depreciado para ORDS_SECURITY?"
```

### oracle-dba-ptbr
`V$SESSION` · `GV$` · `DBA_*` · `CDB_*` · `DBA_HIST_*` · sessão travada · lock · flashback · recompile · tablespace · SE2 vs EE · Diagnostics Pack

```
"Quem está bloqueando essa sessão?"
"Recuperar linha deletada por engano"
"Qual edição Oracle preciso para usar AWR?"
```

### oracle-tuning-ptbr
explain plan · `V$SQL` · `V$SQLAREA` · AWR em tempo real · ASH · index · hard parse · `DBMS_STATS` · cardinality · hints

```
"Essa query está fazendo full scan, como otimizar?"
"Qual index criar para essa consulta?"
"Hard parse muito alto no V$SQLAREA"
```

### oracle-trivadis-ptbr
Revisão explícita do padrão · prefixos `g_/l_/p_/r_/t_/co_/e_` · naming PT-BR · checklist pré-deploy

```
"Esse package segue o padrão Trivadis?"
"Qual prefixo usar para esse cursor?"
"Checklist Trivadis antes do GMUD"
```

> As demais skills aplicam Trivadis automaticamente — `oracle-trivadis-ptbr` é para consultas e revisões explícitas.

### oracle-devops-ptbr
Estrutura Git · changelog Oracle (`db/changelog.yml` + `db_changelog`) · scripts Python com `oracledb` · GitHub Actions · GMUD naming · export APEX split · versionamento ORDS · `DB_SCHEMA` para deploy via DBA

```
"Como estruturar meu projeto Oracle no Git?"
"Script de deploy com changelog versionado"
"Export do APEX para Git em modo split"
"Deploy via usuário DBA em schema diferente"
```

---

## Referências cruzadas entre skills

```
oracle-plsql-ptbr  ←→  oracle-trivadis-ptbr    (nomenclatura)
oracle-plsql-ptbr  ←→  oracle-apex-ptbr         (page process)
oracle-plsql-ptbr  ←→  oracle-ords-ptbr          (handler logic)
oracle-dba-ptbr    ←→  oracle-tuning-ptbr        (AWR / performance)
oracle-apex-ptbr   ←→  oracle-ords-ptbr          (REST consumption)
oracle-devops-ptbr ←→  oracle-plsql-ptbr         (db/packages/)
oracle-devops-ptbr ←→  oracle-apex-ptbr          (apex/app_N/)
oracle-devops-ptbr ←→  oracle-ords-ptbr          (ords/modules/)
```

---

## Stack coberta

| Tecnologia | Versão | Cobertura |
|---|---|---|
| Oracle Database | 19c (LTS) | PL/SQL, SQL, tipos, EBR, Data Dictionary 11g→26ai |
| Oracle APEX | 24.2 | Development + Data Dictionary (APEX_APPLICATION_* etc.) |
| Oracle ORDS | 24.4 / 25.x | REST services + Data Dictionary (USER/DBA_ORDS_*) |
| Trivadis Guidelines | 4.4 | Nomenclatura PT-BR + checklist |
| Python oracledb | 2.0+ (Thin Mode) | Scripts DevOps sem Oracle Client |
| GitHub Actions | — | CI/CD com deploy por ambiente e aprovação prod |

---

## oracle-devops-ptbr — Scripts Python

A skill DevOps inclui 7 scripts Python + módulo compartilhado:

- Empresa: M&S do Brasil
- Sete Lagoas, Minas Gerais, Brasil
- E-mail: [maxwbh@gmail.com](mailto:maxwbh@gmail.com)
- GitHub: [@maxwbh](https://github.com/maxwbh)
