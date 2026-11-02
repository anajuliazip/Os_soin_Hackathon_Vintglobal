# Hackathon Vint_Global — Banco de Dados

Você sobe tudo com **um único comando** e tem o banco disponível em segundos — sem instalar nada além do Docker.

Ao final você terá:
- Um banco PostgreSQL 18 rodando localmente com a tabela 11 tabelas, schema "InHire".
- O pgAdmin 4 acessível pelo navegador, já conectado ao banco
- Dados prontos para uso na aplicação que você vai construir

---

## 1. Pré-requisitos

| Sistema | O que instalar |
|---------|---------------|
| **Windows** | [Docker Desktop para Windows](https://docs.docker.com/desktop/install/windows-install/) |
| **macOS** | [Docker Desktop para Mac](https://docs.docker.com/desktop/install/mac-install/) |
| **Linux** | [Docker Engine + Compose plugin](https://docs.docker.com/engine/install/) |

> **Windows/Mac:** O Docker Desktop precisa estar **aberto** antes de rodar qualquer comando.  
> Você verá o ícone da baleia na bandeja do sistema quando estiver ativo.

**Conferindo se está tudo certo** — abra o terminal e rode:

```bash
docker --version
docker compose version
```

Você deve ver algo como `Docker version 27.x.x` e `Docker Compose version v2.x.x`.  
Se aparecer erro, verifique se o Docker Desktop está aberto.

---

## 2. Subindo o ambiente

### Passo 1 — Baixe e descompacte este pacote

Extraia a pasta `hackathon-vintglobal` em algum lugar no seu computador.

Dentro da pasta deve existir o arquivo **`.env`**, com a senha do banco
igual ao **token** que você recebeu no WhatsApp:

```
POSTGRES_PASSWORD=seu_token_aqui
```

Não apague nem altere esse arquivo antes de subir o ambiente.
Sem ele, o Postgres não sobe com a senha correta.

### Passo 2 — Abra o terminal na pasta do pacote

**Windows (PowerShell ou Prompt):**
```
cd caminho\para\hackathon-vintglobal
```

**Mac/Linux:**
```bash
cd caminho/para/hackathon-vintglobal
```

### Passo 3 — Suba os serviços

```bash
docker compose up -d
```

O que acontece na tela:
```
[+] Running 3/3
 ✔ Network hackathon_default      Created
 ✔ Container hackathon-vintglobal   Started
 ✔ Container hackathon-pgadmin    Started
```

Na primeira execução o Docker vai baixar as imagens (~200 MB). Aguarde.

### Passo 4 — Confirme que está saudável

```bash
docker compose ps
```

Quando estiver pronto, você verá `healthy` na coluna STATUS para o postgres:

```
NAME                   IMAGE                STATUS
hackathon-vintglobal     postgres:18-alpine   Up X seconds (healthy)
hackathon-pgadmin      dpage/pgadmin4       Up X seconds
```

> O banco leva de 10 a 30 segundos para ficar `healthy` na primeira subida  
> (ele precisa carregar o dump). Aguarde antes de tentar conectar.

---

## 3. Credenciais

| Campo | Valor |
|-------|-------|
| Host | `localhost` |
| Porta | `5432` |
| Banco | `hackathon` |
| Usuário | `hackathon` |
| Senha | valor de `POSTGRES_PASSWORD` no arquivo `.env` (seu token) |

A senha do Postgres **não** é a palavra `hackathon`.
Ela é o token que chegou no WhatsApp e foi gravado no `.env`.

**String de conexão** (troque `SEU_TOKEN` pelo valor do `.env`):
```
postgresql://hackathon:SEU_TOKEN@localhost:5432/hackathon
```

> Credenciais só para o ambiente local do desafio.
> Não use em produção.

**Se a porta 5432 já estiver em uso**, abra o `docker-compose.yaml` e troque o número da **esquerda** na linha:
```yaml
ports:
  - "5433:5432"   # <-- coloque qualquer porta livre no seu computador
```
Depois suba novamente com `docker compose up -d` e use `localhost:5433` nas conexões.

---

## 4. Acessando o banco

### pgAdmin (recomendado para iniciantes)

1. Abra o navegador e acesse: **http://localhost:5050**
2. Login do pgAdmin (painel): e-mail `admin@hackathon.com`, senha `hackathon`
3. O servidor **Hackathon** já aparece na árvore à esquerda
4. Clique em `Hackathon` → informe a senha do **Postgres**
   (o valor de `POSTGRES_PASSWORD` no `.env`, ou seja, o seu token)
5. Expanda `Databases → hackathon → Schemas → InHire → Tables`
6. Clique com o botão direito em uma `tabela → View/Edit Data → All Rows`

Para escrever queries SQL: menu `Tools → Query Tool`.

### DBeaver (alternativa gratuita)

1. Abra o DBeaver e clique em **Nova Conexão** (ícone de tomada)
2. Selecione **PostgreSQL** → clique em `Próximo`
3. Preencha os campos:
   - **Host:** `localhost`
   - **Port:** `5432`
   - **Database:** `hackathon`
   - **Username:** `hackathon`
   - **Password:** o valor de `POSTGRES_PASSWORD` no `.env` (seu token)
4. Clique em **Testar Conexão** → se aparecer `Connected`, clique em `Finalizar`

### psql (linha de comando)

```bash
docker compose exec postgres psql -U hackathon -d hackathon
```

Você cai direto no prompt do banco. Para sair: `\q`

---

## 5. Os dados

Os dados estão no schema **`"InHire"`** dentro do banco `hackathon`. O schema contém **11 tabelas** de um sistema de gestão de alocações de profissionais.

| Tabela | O que contém |
|--------|-------------|
| `dominios` | Listas de valores do sistema (cargos, senioridades, modalidades, vínculos, setores etc.) |
| `colaboradores` | Profissionais internos cadastrados |
| `colaborador_skills` | Skills de cada colaborador e seu nível de conhecimento |
| `skills` | Catálogo de skills organizado por área de tecnologia |
| `contratos` | Contratos comerciais com clientes |
| `demandas` | Projetos/demandas vinculados a contratos |
| `demanda_skills` | Skills requeridas por cada demanda |
| `alocacoes` | Vínculo entre colaborador e demanda |
| `planejamentos` | Percentual de alocação mensal de cada colaborador em cada demanda |
| `talentos` | Candidatos externos com disponibilidade informada |
| `talento_skills` | Skills dos talentos externos |

> O schema também conta com **funções auxiliares** para cálculo de disponibilidade e ranking por skills — explore com `\df "InHire".*` no psql.


## 6. Comandos úteis

```bash
# Ver status dos containers
docker compose ps

# Ver logs em tempo real
docker compose logs -f

# Parar os containers (dados mantidos)
docker compose stop

# Subir novamente após parar
docker compose start

# Parar e APAGAR tudo (volumes incluídos — o banco volta do zero na próxima subida)
docker compose down -v
```

---

## 7. Problemas comuns

### "Porta 5432 já está em uso"

Outro serviço (provavelmente um Postgres local) está usando essa porta.  
Solução: troque `"5432:5432"` por `"5433:5432"` no `docker-compose.yaml` e use `localhost:5433` nas conexões. O mesmo vale para `5050` → `5051` para o pgAdmin.

### "Cannot connect to the Docker daemon"

O Docker Desktop não está aberto. Abra-o pela bandeja do sistema ou menu Iniciar e aguarde a baleia ficar estável.

### "O dump não recarrega / a tabela está vazia"

O dump só é carregado na **primeira subida** (quando o volume está vazio).  
Para forçar uma recarga completa:

```bash
docker compose down -v   # apaga os volumes
docker compose up -d     # sobe do zero e recarrega o dump
```

### Meu back-end também está em container

Se o seu back-end roda em outro container, coloque-o na mesma rede do compose:

```yaml
# No docker-compose.yaml da sua aplicação:
services:
  minha-api:
    ...
    networks:
      - hackathon_default   # nome da rede criada por este compose

networks:
  hackathon_default:
    external: true
```

Aí use `host: postgres` (não `localhost`) nas configurações do banco.

---

### "Permission denied" no Linux

```bash
sudo chmod 644 db/01-hackathon.sql
```

### Problema no WSL (Windows Subsystem for Linux)

Se estiver usando WSL, garanta que o Docker Desktop está aberto no Windows e que a integração WSL está ativada em:  
Docker Desktop → Settings → Resources → WSL Integration → habilite sua distro.

Execute os comandos `docker compose` dentro do terminal WSL, na pasta do pacote.

---

## Resumo rápido

```bash
docker compose up -d          # sobe tudo
docker compose ps             # confere se está healthy
# Acesse http://localhost:5050 no navegador (pgAdmin)
docker compose down -v        # apaga tudo quando terminar
```
