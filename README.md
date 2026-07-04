# alura-ms

Projeto de estudo de arquitetura de microsserviços (curso Alura). Simula uma escola
online: um visitante vira "lead" no marketing, compra um curso no financeiro, e ao
ter o pagamento confirmado passa a ser aluno com acesso à área acadêmica.

Cada serviço é um **git submodule** independente, com seu próprio repositório,
linguagem e banco de dados. A comunicação entre eles é feita por **RabbitMQ**
(eventos assíncronos) e por **HTTP via API Gateway** (requisições síncronas do
front-end).

## Visão geral da infraestrutura

```
                         ┌─────────────┐
                         │  front-end  │  (Angular, porta 4200)
                         └──────┬──────┘
                                │ HTTP
                         ┌──────▼──────┐
                         │ api-gateway │  (nginx, porta 80)
                         └──┬───┬───┬──┘
              /financeiro/  │   │   │ /academico/
                    ┌────────┘   │   └────────┐
                    │      /mkt/ │             │
             ┌──────▼─────┐ ┌───▼──────┐ ┌─────▼───────┐
             │financeiro- │ │ mkt-node │ │academico-php│
             │    php     │ │          │ │    -web     │
             └──────┬─────┘ └────┬─────┘ └─────┬───────┘
                     │            │             │
                     │      ┌─────▼─────┐       │
                     └─────▶│  RabbitMQ │◀──────┘
               publica      │ (exchange │  consome
          "client_enrolled" │  fanout)  │ "client_enrolled"
                             └─────┬─────┘
                                   │ consome também
                            ┌──────▼───────┐
                            │academico-php │  (consumer/worker)
                            │  (receive.php)│
                            └──────────────┘
```

`docker-compose.yml` na raiz sobe todos os serviços. Cada `*.sh` na raiz
(`academico-php.sh`, `financeiro-php.sh`, etc.) é montado dentro do respectivo
container como `entrypoint.sh` — é ali que ficam os comandos reais de boot
(`composer install`, `php receive.php`, `npm start`, etc.), não dentro do
Dockerfile do submódulo.

## Módulos

### `front-end`
Angular. Interface do aluno/visitante: página de matrícula/pagamento e login.
Fala com os serviços de backend através do `api-gateway` (nginx, porta 80).

### `mkt-node`
Node.js + TypeScript + Express + MongoDB. Time de marketing: cadastra e
gerencia **leads** (`leads/` segue application/domain/infra/ui). Também
**consome** o evento `client_enrolled` do RabbitMQ para converter um lead em
cliente (`leads/ui/rabbitmq-consumer.ts` → `ConvertLead`) quando a matrícula é
confirmada.

### `financeiro-php`
PHP + Swoole (servidor HTTP assíncrono nativo, porta 9501). Recebe o pedido de
matrícula/pagamento (`POST /clients`), processa o pagamento em uma *task*
assíncrona do próprio Swoole e, ao confirmá-lo, **publica** o evento
`client_enrolled` (exchange fanout) no RabbitMQ — é esse evento que
`academico-php` e `mkt-node` consomem.

### `academico-php`
PHP procedural, sem framework nem servidor HTTP — é um **consumer/worker**
(`receive.php`) que fica em loop consumindo a fila `student_enrollment`
(vinculada ao exchange `client_enrolled`). Usa RedBeanPHP (modo *fluid*, cria
colunas automaticamente) para gravar o aluno direto no Postgres do acadêmico,
e Symfony Mailer para enviar o e-mail de boas-vindas com o link de definição
de senha (ver `functions.php`).

> Alteração recente: ao matricular, o serviço já não envia mais uma senha
> fraca fixa ("123456") por e-mail. Em vez disso gera um token aleatório,
> grava só o hash dele (com expiração de 24h) e manda um link de
> "definir senha" no e-mail. Veja `academico-php-web` para o endpoint que
> valida esse token.

### `academico-php-web`
Lumen (micro-framework Laravel). API HTTP (porta 8080) da área acadêmica,
compartilhando o **mesmo banco Postgres** (`students`) que o `academico-php`
grava. Rotas atuais:
- `POST /login` — autentica aluno e devolve um JWT.
- `POST /definir-senha` — recebe `token` + `senha`, valida o token gerado pelo
  `academico-php` (hash + expiração) e grava a senha definitiva do aluno.
- `GET /cursos` e `PATCH /cursos/{id}` (autenticado via JWT) — lista/atualiza
  progresso dos cursos do aluno.

### `servicos-nginx`
Configuração do API Gateway (`api-gateway.conf`): faz proxy de
`/financeiro/`, `/mkt/` e `/academico/` para os respectivos serviços web.

## Infraestrutura compartilhada (definida no `docker-compose.yml` raiz)
- **RabbitMQ**: barramento de eventos entre os serviços (exchange fanout
  `client_enrolled`).
- **Postgres** (`postgre-academico`): banco do módulo acadêmico.
- **MongoDB** (`mongo-mkt`): banco do módulo de marketing.
- Credenciais de e-mail (Gmail) do `academico-php` vêm do `.env` da raiz
  (veja `.env.example`).

## Como subir o projeto
```bash
docker-compose up
```
- Front-end: http://localhost:4200
- API Gateway: http://localhost:80
- Web acadêmico direto: http://localhost:8080
- Financeiro direto: http://localhost:9501
