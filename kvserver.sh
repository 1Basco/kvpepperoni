#!/bin/bash

DB_FILE="kvstore.txt"
PORT="8085"

touch "$DB_FILE"

process_command() {
    local cmd="$1"

    # Parse do comando
    if [[ "$cmd" =~ ^write[[:space:]]+([a-zA-Z0-9._:-]+)\|(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        # Validar tamanho da key (100KB)
        if [ ${#key} -gt 102400 ]; then
            echo "error 100kb"
            return
        fi
        # Deletar chave existente e adicionar nova (usando grep -v para evitar problemas com caracteres especiais)
        grep -v "^$(printf '%s' "$key" | sed 's/[.[\*^$]/\\&/g')|" "$DB_FILE" > "$DB_FILE.tmp" 2>/dev/null || true
        mv "$DB_FILE.tmp" "$DB_FILE"
        echo "${key}|${value}" >> "$DB_FILE"
        echo "ok"

    elif [[ "$cmd" =~ ^read[[:space:]]+([a-zA-Z0-9._:-]+)$ ]]; then
        key="${BASH_REMATCH[1]}"

        # Buscar valor
        result=$(grep "^${key}|" "$DB_FILE" 2>/dev/null | cut -d'|' -f2-)
        if [ -z "$result" ]; then
            echo "error"
        else
            echo "$result"
        fi

    elif [[ "$cmd" =~ ^delete[[:space:]]+([a-zA-Z0-9._:-]+)$ ]]; then
        key="${BASH_REMATCH[1]}"

        # Verificar se existe
        if grep -q "^${key}|" "$DB_FILE" 2>/dev/null; then
            grep -v "^$(printf '%s' "$key" | sed 's/[.[\*^$]/\\&/g')|" "$DB_FILE" > "$DB_FILE.tmp" 2>/dev/null || true
            mv "$DB_FILE.tmp" "$DB_FILE"
            echo "ok"
        else
            echo "error"
        fi

    elif [[ "$cmd" =~ ^status$ ]]; then
        echo "well going our operation"

    elif [[ "$cmd" =~ ^keys$ ]]; then
        # Listar todas as chaves
        # cut -d'|' -f1 "$DB_FILE" 2>/dev/null | tr '\n' '\r'
        cut -d'|' -f1 "$DB_FILE" | tr '\n' '\r'


    elif [[ "$cmd" =~ ^reads[[:space:]]+([a-zA-Z0-9._:-]+)$ ]]; then
        prefix="${BASH_REMATCH[1]}"

        # Buscar valores com prefixo
        grep "^${prefix}" "$DB_FILE" 2>/dev/null | cut -d'|' -f2- | tr '\n' '\r'
    elif [[ "$cmd" =~ ^end$ ]]; then
        echo "DONE"
        return 1

    else
        echo "error"
    fi
}

# Função para lidar com conexão do cliente
handle_client() {
    while IFS=$'\r' read -r -d $'\r' command; do
        if [ -z "$command" ]; then
            continue
        fi

        response=$(process_command "$command")
        exit_code=$?
        echo -ne "${response}\r"
        
        if [ $exit_code -eq 1 ]; then
            break
        fi
    done
}

echo "KV Server listening on port $PORT..."


if command -v nc &> /dev/null; then
    while true; do
        nc -l -p "$PORT" -e "$(declare -f handle_client process_command); handle_client" 2>/dev/null || {
            # Fallback: use mkfifo for bidirectional pipe
            FIFO="/tmp/kvserver_fifo_$$"
            rm -f "$FIFO"
            mkfifo "$FIFO"
            while true; do
                nc -l "$PORT" < "$FIFO" | handle_client > "$FIFO"
            done
        }
    done
else
    echo "Error: No TCP listener found. Install nc"
    exit 1
fi
