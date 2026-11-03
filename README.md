# InHire AI - Alocação Inteligente

Projeto do Hackathon Vintglobal com frontend, PostgreSQL e workflows n8n.

## Estrutura

```text
frontend/       Interface web
database/       Schema e dados iniciais do PostgreSQL
infrastructure/ Compose do PostgreSQL e configuração do pgAdmin
n8n/             Compose, variáveis de exemplo e workflows n8n
```

## Executar o PostgreSQL

```bash
cd infrastructure
cp postgres.env.example .env
docker compose -f postgres-compose.yaml up -d
```

O banco fica disponível em `localhost:5432` e o pgAdmin em `localhost:5050`.

## Executar o n8n

```bash
cd n8n
cp .env.example .env
docker compose up -d
```

Configure no n8n a credencial PostgreSQL usando o banco `hackathon`, usuário
`hackathon` e a senha definida no ambiente local. Depois importe os arquivos de
`n8n/workflows/` e ative os workflows.

## Abrir o frontend

Sirva a pasta `frontend/` com um servidor HTTP local. Por exemplo:

```bash
cd frontend
python -m http.server 8088
```

Abra `http://localhost:8088`.

## Segurança

Arquivos `.env`, credenciais, tokens e senhas não devem ser commitados. Use os
arquivos `.env.example` somente como referência.
