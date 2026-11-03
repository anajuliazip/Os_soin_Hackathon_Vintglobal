# Os Soin - InHire Alocação Inteligente

Este repositório contém a interface frontend e as configurações de infraestrutura (Docker) para correr o projeto InHire AI localmente.

## 🚀 Como Rodar o Projeto Localmente em Qualquer Máquina

Para garantir que a comunicação entre a IA, o n8n, o PostgreSQL e a interface funcione sem problemas de CORS ou conectividade, siga estes passos:

### Pré-requisitos
- Ter o **Docker** e o **Docker Compose** instalados na sua máquina.
- Ter o **Git** instalado.

### Passo 1: Clonar o repositório
\`\`\`bash
git clone https://github.com/anajuliazip/Os_soin_Hackathon_Vintglobal.git
cd Os_soin_Hackathon_Vintglobal
\`\`\`

### Passo 2: Configurar Variáveis de Ambiente
1. Crie um ficheiro `.env` na raiz do projeto.
2. Adicione as seguintes variáveis (ajuste os valores conforme necessário para o seu ambiente local, mas **não as submeta para o GitHub**):
\`\`\`env
POSTGRES_USER=postgres
POSTGRES_PASSWORD=sua_senha_segura
POSTGRES_DB=postgres
\`\`\`

### Passo 3: Subir a Infraestrutura (n8n, PostgreSQL e Ollama)
1. Crie a rede Docker (se ainda não existir):
\`\`\`bash
docker network create hackathon_default
\`\`\`
2. Inicie os contentores em segundo plano:
\`\`\`bash
docker compose up -d
\`\`\`

### Passo 4: Baixar o Modelo Qwen 2.5
O modelo de Inteligência Artificial precisa de ser descarregado dentro do contentor do Ollama. Execute:
\`\`\`bash
docker exec -it ollama ollama pull qwen2.5:3b
\`\`\`

### Passo 5: Configurar o PostgreSQL
Restaure a estrutura do banco de dados (o schema "InHire" e as tabelas):
\`\`\`bash
docker exec -i nome_do_container_postgres psql -U postgres -d postgres < 01-hackathon.sql
\`\`\`
*(Substitua `nome_do_container_postgres` pelo nome real do contentor listado com `docker ps`).*

### Passo 6: Configurar o n8n
1. Aceda ao n8n localmente no seu navegador: `http://localhost:5678`
2. Configure as suas credenciais para o PostgreSQL (em *Credentials* -> *Postgres account*), utilizando:
   - **Host:** `nome_do_container_postgres` (ou o nome definido no docker-compose)
   - **User:** postgres
   - **Password:** a senha definida no seu `.env`
3. Vá a *Workflows* e clique em **Import from File**. Selecione o ficheiro `workflow_alocacao.json` presente neste repositório.
4. **IMPORTANTE:** No canto superior direito, ative o *workflow* (mude a chave para **Active**). Se estiver no modo *Test*, os endpoints do frontend falharão após uma chamada.

### Passo 7: Abrir a Interface Frontend
1. Na pasta do projeto, abra o ficheiro `index.html` utilizando a extensão **Live Server** do VS Code (ou sirva o ficheiro com outro servidor HTTP local simples, como `python -m http.server 5500`).
2. Aceda à aplicação através do endereço do servidor local (geralmente `http://127.0.0.1:5500`).
