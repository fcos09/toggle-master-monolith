Por que o ToggleMaster é um monolito
Tech Challenge · Fase 1 · Requisito 1.2 (Cultura DevOps e Arquitetura de Aplicações)

Definição
Um monolito é uma aplicação em que todas as responsabilidades (receber requisições, aplicar regras de negócio, acessar dados e executar tarefas administrativas) são construídas, versionadas, implantadas e escaladas como uma única unidade.

A pergunta que identifica um monolito é: quantas coisas preciso publicar para colocar uma mudança no ar, e o que cai junto quando uma delas falha? No ToggleMaster a resposta é "uma coisa só" e "tudo".

Evidências no código
#	Evidência	Onde	O que mostra
1	Um único arquivo Python com 143 linhas concentra a aplicação inteira: criação do app, conexão com o banco, criação da tabela, as cinco rotas e a inicialização do servidor	../app.py	Não há módulos nem pacotes separados por responsabilidade
2	A rota de criação valida a entrada, abre a conexão, executa o SQL e monta a resposta HTTP dentro da mesma função	create_flag, linhas 53 a 77: validação (L56–57), conexão (L63), INSERT (L65)	Camada HTTP, regra de negócio e acesso a dados estão misturados
3	O mesmo padrão se repete na atualização	update_flag, linhas 115 a 140: validação (L118–119), conexão (L124), UPDATE (L126)	Não existe camada de serviço ou de repositório
4	Todas as rotas usam a mesma função de conexão e a mesma tabela	get_db_connection, linhas 14 e 15, chamada nas linhas 63, 82, 99 e 124; tabela flags criada na linha 29	Um único banco compartilhado por todas as funcionalidades
5	A tarefa administrativa de criar a tabela vive no mesmo código da API	Comando init-db, linhas 45 e 46	Até a administração faz parte da mesma unidade
6	Existe um único artefato de deploy e um único processo	../Dockerfile gera uma imagem com o app.py; o Gunicorn sobe app:app; o ../docker-compose.yaml tem um único serviço de aplicação	Leitura e escrita de flags não podem ser publicadas nem escaladas separadamente
7	Uma falha atinge todas as funcionalidades ao mesmo tempo	Experimento: docker compose stop db	Todas as rotas de flags passam a responder 500 (só o /health continua 200)
Vantagens para um MVP
Velocidade de entrega. Um repositório, um arquivo e um deploy. Do clone à aplicação rodando bastam docker compose up --build, o que permite colocar o produto no ar rápido e começar a receber feedback, que é o objetivo declarado do MVP.
Simplicidade operacional. Não há comunicação de rede entre serviços, descoberta de serviços, orquestrador nem rastreamento distribuído. Um erro é depurado em um único processo e em um único log.
Baixo custo. Toda a solução cabe em uma instância EC2 e um banco RDS pequenos, dentro do free tier da AWS.
Mudanças fáceis enquanto o domínio é incerto. Como tudo está junto, alterar o modelo de dados ou uma regra exige mexer em um só lugar, sem coordenar contratos entre serviços.
Adequado a um time pequeno. Uma pessoa entende o sistema inteiro lendo 143 linhas.
Desvantagens para um MVP
Escala só em bloco. Em um serviço de feature flags, as consultas (GET /flags/<name>) acontecem a cada requisição dos clientes, enquanto as alterações (POST e PUT) acontecem poucas vezes por dia. No monolito, para aguentar mais consultas é preciso replicar a aplicação inteira.
Ponto único de falha. Um processo e um banco: se qualquer um cair, nenhuma flag é consultada, e os sistemas clientes ficam sem resposta.
Todo deploy republica tudo. Uma correção pequena na rota de atualização exige publicar e reiniciar também a rota de consulta, que é a mais crítica.
Acoplamento crescente. Sem fronteiras internas (SQL dentro das rotas), cada nova funcionalidade aumenta o acoplamento e encarece uma futura separação em serviços.
Conflitos com mais pessoas. Com vários desenvolvedores, todos editam o mesmo arquivo e disputam a mesma fila de deploy.
Conclusão
Para validar a ideia do ToggleMaster, o monolito é a escolha certa: o risco de um MVP é de produto (alguém vai usar?), não de escala. A simplicidade de construir, publicar e operar uma única unidade supera, nesta fase, as limitações de escala e de isolamento de falhas.

O cuidado que vale tomar desde já é organizar o código em camadas dentro do próprio monolito (rotas, regras de negócio e acesso a dados em módulos separados), formando um monolito modular. Isso torna barata a separação em serviços prevista para as próximas fases do projeto.

Os sinais que indicariam a hora de separar são:

a carga de consultas crescer muito mais que a de alterações, pedindo um serviço de consulta escalável e com cache;
mais de um time precisar publicar mudanças de forma independente;
falhas em uma funcionalidade derrubarem as outras com frequência.
Como reproduzir as evidências
# Evidências 1 a 6: abrir o código
code app.py

# Evidência 7: falha compartilhada
docker compose up -d --build
curl -i http://localhost:5000/flags        # 200
docker compose stop db
curl -i http://localhost:5000/flags        # 500
curl -i http://localhost:5000/health       # continua 200
docker compose start db