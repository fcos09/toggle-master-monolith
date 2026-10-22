# ToggleMaster e os 12 fatores

> Tech Challenge · Fase 1 · Requisito 1.3 (Cultura DevOps e Arquitetura de Aplicações)

## O que é o 12-Factor App

O [12-Factor App](https://12factor.net/pt_br/) é um conjunto de doze práticas, publicado em 2011 por engenheiros do Heroku, para aplicações que rodam como serviço na nuvem. Uma aplicação que segue os doze fatores roda igual em qualquer ambiente, pode ser construída e publicada por automação e escala adicionando cópias.

Cada fator foi avaliado em três níveis: **atende**, **atende em parte** (a prática existe, mas com lacunas) e **não atende**. Toda classificação tem uma evidência verificável: um trecho de arquivo ou o resultado de um comando.

## Resumo

| Fator | Situação | Ajuste principal para produção |
| --- | --- | --- |
| I. Base de código | Atende | Versionar releases com tags |
| II. Dependências | Atende em parte | Fixar dependências transitivas e atualizar versões vulneráveis |
| III. Configurações | Atende em parte | Ler `DB_PORT` e `PORT` do ambiente; tirar a senha do `docker-compose.yaml` |
| IV. Serviços de apoio | Atende | Nenhum nesta fase |
| V. Build, release, run | Não atende | Pipeline que gera imagem versionada e publica a release |
| VI. Processos | Atende | Nenhum |
| VII. Vínculo de porta | Atende | Porta configurável por variável |
| VIII. Concorrência | Atende em parte | Pool de conexões; porta do host não fixa; workers configuráveis |
| IX. Descartabilidade | Atende em parte | Health check que testa o banco; nova tentativa de conexão |
| X. Paridade dev/prod | Atende em parte | Mesma versão de banco e mesmo artefato (imagem) em todos os ambientes |
| XI. Logs | Atende em parte | Logs estruturados com `logging` e log de acesso; não expor exceções |
| XII. Processos administrativos | Atende | Migrações versionadas (Alembic) |

**Placar: 5 atendem, 6 atendem em parte, 1 não atende.**

---

## I. Base de código — Atende

**O fator pede** uma base de código versionada e vários deploys a partir dela.

**No projeto.** Todo o código está em um único repositório Git. O ambiente local (Docker Compose) e o servidor (EC2, Bloco 3) saem do mesmo repositório, só com configurações diferentes.

**Ajuste para produção.** Marcar cada versão publicada com uma tag (`v1.0.0`) para saber exatamente qual código está em cada ambiente.

## II. Dependências — Atende em parte

**O fator pede** que todas as dependências sejam declaradas explicitamente e isoladas do sistema.

**No projeto.**
- O [`requirements.txt`](../requirements.txt) declara as quatro bibliotecas diretas com versão fixa (Flask 2.2.2, Werkzeug 2.3.8, psycopg2-binary 2.9.5, gunicorn 20.1.0).
- O isolamento existe: o container usa o próprio Python 3.9 (`python:3.9-slim`), e na EC2 usa-se um ambiente virtual (venv).
- O [`Dockerfile`](../Dockerfile) declara também a dependência de sistema `postgresql-client`, usada pelo `pg_isready`.

**Lacunas.**
- As dependências transitivas (Jinja2, click, itsdangerous, MarkupSafe) não estão fixadas: a versão instalada depende do dia do build.
- As versões fixadas são antigas: Flask 2.2.2 e gunicorn 20.1.0 têm vulnerabilidades conhecidas corrigidas em versões posteriores, e o Python 3.9 já saiu de suporte.
- Na execução direta na EC2, o `postgresql-client` não está declarado em lugar nenhum; precisa ser lembrado manualmente.

**Ajuste para produção.** Gerar um arquivo de travamento com todas as dependências e seus hashes (`pip-compile --generate-hashes`), atualizar as versões e rodar uma verificação de vulnerabilidades (`pip-audit`) no pipeline.

## III. Configurações — Atende em parte

**O fator pede** que tudo o que muda entre ambientes fique em variáveis de ambiente, nunca no código.

**No projeto.** As credenciais do banco são lidas do ambiente em [`get_db_connection`](../app.py#L14-L15): `DB_HOST`, `DB_NAME`, `DB_USER` e `DB_PASSWORD`. Trocar de banco não exige mudar código.

**Lacunas.**
- O [`docker-compose.yaml`](../docker-compose.yaml) define `DB_PORT=5432`, mas o `app.py` não lê essa variável: a aplicação sempre usa a porta padrão do PostgreSQL. A configuração parece existir, mas não tem efeito.
- A porta da aplicação (5000) está fixa no código ([linha 143](../app.py#L143)), no `entrypoint.sh` e no `Dockerfile`.
- A senha do banco está em texto aberto no `docker-compose.yaml`. É aceitável para desenvolvimento local, mas o arquivo não pode ser reaproveitado para outros ambientes.
- As variáveis não têm validação dentro da aplicação: se faltar uma, o erro só aparece na primeira requisição.

**Ajuste para produção.** Ler `DB_PORT` e `PORT` do ambiente, validar todas as variáveis na inicialização e manter segredos em um cofre (SSM Parameter Store ou Secrets Manager) ou, localmente, em um arquivo `.env` fora do Git.

## IV. Serviços de apoio — Atende

**O fator pede** que banco, filas e caches sejam recursos anexados, trocáveis apenas por configuração.

**No projeto.** O PostgreSQL é acessado por endereço vindo do ambiente (`DB_HOST`). O mesmo código conecta no container `db` localmente e no Amazon RDS na AWS, mudando só as variáveis. A demonstração está na seção de evidências: a aplicação passa a usar outro banco, de outra versão, sem nenhuma alteração de código.

## V. Build, release, run — Não atende

**O fator pede** três etapas separadas: construir um artefato (build), combiná-lo com a configuração de um ambiente (release) e executá-lo (run). Uma release é imutável e identificável.

**No projeto.**
- Existe um `Dockerfile`, que seria o build, mas ele não é usado no deploy pedido pelo enunciado: na EC2 o código é obtido com `git clone` e as dependências são instaladas com `pip install` direto no servidor. Build e run acontecem juntos, na máquina de produção.
- Mesmo localmente, o `docker-compose.yaml` monta a pasta do projeto dentro do container (`.:/app`): o código que roda é o da pasta, e não o que foi copiado para a imagem no build.
- Não há versões identificáveis (tags) nem pipeline de CI/CD.

**Ajuste para produção.** Um pipeline (por exemplo, GitHub Actions) que, a cada mudança, constrói a imagem, marca com a versão, publica em um registro (Amazon ECR) e faz o deploy dessa imagem com a configuração do ambiente. Voltar uma versão passa a ser trocar a tag.

## VI. Processos — Atende

**O fator pede** processos sem estado: nada guardado em memória ou em disco local entre requisições.

**No projeto.** O `app.py` não usa variáveis globais de estado, sessões ou arquivos locais. Todo o estado está na tabela `flags` do PostgreSQL. Reiniciar ou recriar o container da aplicação não perde nenhum dado.

## VII. Vínculo de porta — Atende

**O fator pede** que a aplicação exporte HTTP sozinha, vinculando-se a uma porta, sem depender de um servidor web externo injetado em tempo de execução.

**No projeto.** O Gunicorn faz parte das dependências da aplicação e escuta diretamente na porta 5000. A aplicação é autossuficiente: basta executá-la para ter um serviço HTTP.

**Ajuste para produção.** Tornar a porta configurável (`PORT`), já apontado no fator III.

## VIII. Concorrência — Atende em parte

**O fator pede** que a aplicação escale rodando mais processos.

**No projeto.** Como a aplicação é sem estado (fator VI), é possível rodar várias cópias, e o Gunicorn permite vários processos de trabalho.

**Lacunas.**
- O Gunicorn sobe com a configuração padrão, ou seja, um único processo de trabalho.
- O `docker-compose.yaml` publica a porta fixa `5000:5000`; por isso não é possível subir uma segunda cópia da aplicação no mesmo host (a porta já está ocupada).
- Cada requisição abre uma conexão nova com o banco e não há pool de conexões; com muitos processos, o limite de conexões do PostgreSQL vira o gargalo.
- Na AWS, a arquitetura desta fase tem uma única EC2.

**Ajuste para produção.** Número de workers por variável, pool de conexões (ou RDS Proxy) e várias instâncias atrás de um balanceador de carga.

## IX. Descartabilidade — Atende em parte

**O fator pede** processos que sobem rápido e encerram de forma limpa, para que possam ser criados e destruídos a qualquer momento.

**No projeto.**
- A aplicação inicia em poucos segundos.
- O [`entrypoint.sh`](../entrypoint.sh) termina com `exec gunicorn ...`: o Gunicorn substitui o shell e recebe diretamente o sinal de parada do Docker, encerrando de forma limpa e rápida.
- O entrypoint espera o banco ficar disponível (`pg_isready`) antes de iniciar.

**Lacunas.**
- O `/health` responde 200 mesmo com o banco fora do ar. Um orquestrador ou balanceador que confie nele mandaria tráfego para uma instância que não funciona.
- Fora do container (na EC2), não existe a espera pelo banco nem nova tentativa de conexão dentro da aplicação.

**Ajuste para produção.** Separar uma verificação de vida (`/live`, só o processo) de uma verificação de prontidão (`/ready`, que testa o banco), e tentar reconectar com espera progressiva.

## X. Paridade entre desenvolvimento e produção — Atende em parte

**O fator pede** ambientes de desenvolvimento e produção o mais parecidos possível: mesmas ferramentas, mesmas versões, deploys frequentes.

**No projeto.** Os dois ambientes usam PostgreSQL e o mesmo código, o que já evita a armadilha comum de usar um banco diferente (como SQLite) só no desenvolvimento.

**Lacunas.**
- O ambiente local usa PostgreSQL 13, versão que já saiu do suporte padrão; o RDS usará uma versão atual. Diferenças de versão de banco são exatamente o que o fator combate.
- Localmente a aplicação roda em container; na EC2 roda direto no sistema, com Python e bibliotecas instalados à mão. São dois artefatos diferentes.

**Ajuste para produção.** Mesma versão do PostgreSQL no `docker-compose.yaml` e no RDS, e a mesma imagem Docker rodando em todos os ambientes.

## XI. Logs — Atende em parte

**O fator pede** que a aplicação escreva logs como um fluxo de eventos na saída padrão, deixando para o ambiente a coleta e o armazenamento.

**No projeto.** O Gunicorn escreve na saída padrão, e o `Dockerfile` desliga o buffer (`PYTHONUNBUFFERED`), de modo que o Docker (`docker compose logs`) e, na EC2, o journald do systemd capturam tudo.

**Lacunas.**
- O `app.py` não usa o módulo `logging`; há apenas `print` na criação da tabela.
- O Gunicorn sobe sem log de acesso: as requisições não aparecem nos logs.
- Os logs não são estruturados (JSON), o que dificulta buscas e alertas.
- As respostas de erro 500 devolvem ao cliente o texto da exceção (campo `details`), expondo detalhes internos do banco. Isso deveria ir para o log, não para a resposta.

**Ajuste para produção.** `logging` com saída em JSON, `--access-logfile -` no Gunicorn, envio para o Amazon CloudWatch Logs e mensagens de erro genéricas para o cliente.

## XII. Processos administrativos — Atende

**O fator pede** que tarefas pontuais (migrações, scripts) rodem como processos únicos, com o mesmo código e a mesma configuração da aplicação.

**No projeto.** A criação da tabela é um comando da própria aplicação, `flask init-db` ([linhas 45 e 46](../app.py#L45-L46)), executado com o mesmo código e as mesmas variáveis de ambiente, tanto pelo entrypoint quanto manualmente na EC2.

**Ajuste para produção.** Evoluir para migrações versionadas (Alembic), que registram cada mudança de esquema e permitem desfazê-la.

---

## Conclusão

O ToggleMaster já nasce com uma boa base para a nuvem: configuração por ambiente, banco como recurso anexado, processos sem estado e tarefas administrativas no próprio código. Isso é o que permite publicá-lo na AWS nesta fase sem alterar uma linha de código.

As lacunas aparecem quando se pensa em operação contínua. Os três ajustes de maior retorno são:

1. **Pipeline de build e release (fator V).** É o único fator não atendido e o que mais reduz risco: elimina o deploy manual, torna cada versão identificável e permite voltar atrás em segundos. Também resolve boa parte da paridade (fator X), porque a mesma imagem passa a rodar em todos os ambientes.
2. **Observabilidade (fatores XI e IX).** Logs estruturados com registro de acesso, e um health check que realmente testa o banco. Sem isso, não se sabe quando a aplicação falha nem por quê.
3. **Configuração completa (fatores III e II).** Ler todas as configurações do ambiente, tirar segredos de arquivos versionados e atualizar dependências vulneráveis.

## Evidências

Os comandos abaixo reproduzem cada conclusão. Rode a partir da pasta do projeto, com a aplicação no ar (`docker compose up -d --build`).

```bash
# I. Base de código
git remote -v
git log --oneline -5

# II. Dependências: diretas fixadas, transitivas não
cat requirements.txt
docker compose exec app pip freeze
# (opcional) vulnerabilidades conhecidas nas versões fixadas
docker run --rm -v "$PWD":/src python:3.9-slim sh -c "pip install -q pip-audit && pip-audit -r /src/requirements.txt"

# III. Configurações
grep -n "getenv" app.py
grep -n "DB_PORT" app.py docker-compose.yaml entrypoint.sh
grep -n "5000" app.py Dockerfile entrypoint.sh docker-compose.yaml
grep -n "PASSWORD" docker-compose.yaml

# IV. Serviços de apoio: outro banco, outra versão, nenhum código alterado
docker run -d --name pg-alternativo --network toggle-master-monolith_default \
  -e POSTGRES_USER=user -e POSTGRES_PASSWORD=password -e POSTGRES_DB=togglemaster postgres:16
docker compose run --rm -d --name app-alternativo -p 5001:5000 -e DB_HOST=pg-alternativo app
curl -s http://localhost:5001/flags      # lista vazia: outro banco
curl -s http://localhost:5000/flags      # flags do banco original
docker rm -f app-alternativo pg-alternativo

# V. Build, release, run
grep -n -A1 "volumes" docker-compose.yaml   # .:/app sobrepõe o código da imagem
git tag                                      # nenhuma versão marcada
ls .github 2>/dev/null || echo "sem pipeline de CI/CD"

# VI. Processos sem estado
curl -s -X POST http://localhost:5000/flags -H "Content-Type: application/json" -d '{"name":"evidencia-vi","is_enabled":true}'
docker compose up -d --force-recreate app
curl -s http://localhost:5000/flags/evidencia-vi   # a flag sobreviveu à recriação

# VII. Vínculo de porta
docker compose port app 5000
curl -i http://localhost:5000/health

# VIII. Concorrência
docker compose top app                      # um processo mestre e um worker
docker compose up -d --scale app=2          # falha: a porta 5000 do host já está em uso

# IX. Descartabilidade
time docker compose restart app             # sobe em segundos
docker compose stop db
curl -i http://localhost:5000/health        # 200, mesmo sem banco
curl -i http://localhost:5000/flags         # 500
docker compose start db

# X. Paridade
docker compose exec db psql -U user -d togglemaster -c "SELECT version();"
docker compose exec app python --version

# XI. Logs
grep -n "logging\|print" app.py
docker compose logs --tail 20 app           # sem linhas de acesso
docker compose stop db
curl -s http://localhost:5000/flags         # o campo "details" expõe a exceção
docker compose start db

# XII. Processos administrativos
grep -n "init-db" app.py entrypoint.sh
docker compose exec app flask init-db
```
