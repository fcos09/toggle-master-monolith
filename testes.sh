#!/usr/bin/env bash
# Roteiro de testes da API ToggleMaster
# Uso: ./testes.sh                       (para execução local)
#      ./testes.sh http://<dns-da-ec2>   (recebe argumento para execução não local)
set -u
BASE="${1:-http://localhost:5000}"
JSON="Content-Type: application/json"
NOME="teste-$(date +%s)"

passo()  { printf '%-46s' "$1"; }
codigo() { curl -s -o /dev/null -w '%{http_code}' "$@"; echo; }

# a aplicação está no ar?
passo "GET /health (espera 200)";                codigo "$BASE/health"
# Criação funciona e grava no banco?
passo "POST /flags (espera 201)";                codigo -X POST "$BASE/flags" -H "$JSON" -d '{"name":"'"$NOME"'","is_enabled":true}'
# Restrição da tabela é respeitada?
passo "POST /flags repetido (espera 409)";       codigo -X POST "$BASE/flags" -H "$JSON" -d '{"name":"'"$NOME"'"}'
# A validação de entrada da api funciona?
passo "POST /flags sem name (espera 400)";       codigo -X POST "$BASE/flags" -H "$JSON" -d '{"is_enabled":true}'
# Listagem funciona?
passo "GET /flags (espera 200)";                 codigo "$BASE/flags"
# Consulta encontra a flag criada?
passo "GET /flags/<nome> (espera 200)";          codigo "$BASE/flags/$NOME"
# Atualização funciona?
passo "PUT /flags/<nome> (espera 200)";          codigo -X PUT "$BASE/flags/$NOME" -H "$JSON" -d '{"is_enabled":false}'
# Só aceita booleano?
passo "PUT nao booleano (espera 400)";           codigo -X PUT "$BASE/flags/$NOME" -H "$JSON" -d '{"is_enabled":"sim"}'
# Trata recurso ausente?
passo "GET /flags/inexistente (espera 404)";     codigo "$BASE/flags/inexistente-$NOME"
echo; echo "Estado final:"; curl -s "$BASE/flags/$NOME"; echo