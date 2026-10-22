#!/usr/bin/env bash
# Roteiro de testes da API ToggleMaster
# Uso: ./testes.sh                       (local)
#      ./testes.sh http://<dns-da-ec2>   (Bloco 3)
set -u
BASE="${1:-http://localhost:5000}"
JSON="Content-Type: application/json"
NOME="teste-$(date +%s)"

passo()  { printf '%-46s' "$1"; }
codigo() { curl -s -o /dev/null -w '%{http_code}' "$@"; echo; }

passo "GET /health (espera 200)";                codigo "$BASE/health"
passo "POST /flags (espera 201)";                codigo -X POST "$BASE/flags" -H "$JSON" -d '{"name":"'"$NOME"'","is_enabled":true}'
passo "POST /flags repetido (espera 409)";       codigo -X POST "$BASE/flags" -H "$JSON" -d '{"name":"'"$NOME"'"}'
passo "POST /flags sem name (espera 400)";       codigo -X POST "$BASE/flags" -H "$JSON" -d '{"is_enabled":true}'
passo "GET /flags (espera 200)";                 codigo "$BASE/flags"
passo "GET /flags/<nome> (espera 200)";          codigo "$BASE/flags/$NOME"
passo "PUT /flags/<nome> (espera 200)";          codigo -X PUT "$BASE/flags/$NOME" -H "$JSON" -d '{"is_enabled":false}'
passo "PUT nao booleano (espera 400)";           codigo -X PUT "$BASE/flags/$NOME" -H "$JSON" -d '{"is_enabled":"sim"}'
passo "GET /flags/inexistente (espera 404)";     codigo "$BASE/flags/inexistente-$NOME"
echo; echo "Estado final:"; curl -s "$BASE/flags/$NOME"; echo