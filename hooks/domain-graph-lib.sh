#!/usr/bin/env bash
# domain-graph-lib.sh — скоринг по графу доменов для knowledge-activator.
#
# Извлечено из knowledge-activator.sh (Ф4 — модуляризация монолита, слой
# domain-graph). expand_domains_from_context раскрывает домены из ключевых
# слов через граф (parent/child/overlap/applies/analogous, веса 30/20/10/5);
# domain_graph_score возвращает лучший вес домена в раскрытом наборе.
#
# Зависит от DOMAINS_DIR (задаётся вызывающим хуком до подключения).
# Не предназначено для standalone-подключения.

# --- Domain Graph functions (v0.5.4) ---
# Build expanded domain set from context keywords
# Returns lines: "domain_name weight_multiplier" (weight: 30=self, 20=parent/child, 10=overlap/applies, 5=analogous)

expand_domains_from_context() {
    local keywords="$1"
    local expanded=""

    [ -z "$DOMAINS_DIR" ] && return

    # Step 1: Find which domains match context keywords (by name or alias)
    local matched_domains=""
    for dfile in "$DOMAINS_DIR"/*.md; do
        [ -f "$dfile" ] || continue
        local dname=$(basename "$dfile" .md)
        [ "$dname" = "_roots" ] && continue

        # Read frontmatter
        local dfm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$dfile")
        local dcanonical=$(echo "$dfm" | grep '^name:' | sed 's/^name:[[:space:]]*//' | tr -d '"' || true)
        local daliases=$(echo "$dfm" | grep '^aliases:' | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z_]{2,}' | tr '\n' ' ' || true)

        # Check if any keyword matches domain name or aliases
        for kw in $keywords; do
            if [ "$kw" = "$dcanonical" ] || [ "$kw" = "$dname" ] || echo "$daliases" | grep -qw "$kw" 2>/dev/null; then
                matched_domains="$matched_domains $dcanonical"
                expanded="${expanded}${dcanonical} 30\n"
                break
            fi
        done
    done

    # Step 2: Expand matched domains through graph
    for mdomain in $matched_domains; do
        local mfile="$DOMAINS_DIR/${mdomain}.md"
        # Try with underscores replaced by hyphens
        [ ! -f "$mfile" ] && mfile="$DOMAINS_DIR/$(echo "$mdomain" | tr '_' '-').md"
        [ ! -f "$mfile" ] && continue

        # Read relationships (after frontmatter)
        local body=$(awk '/^---$/{n++; next} n>=2{print}' "$mfile")
        local parents=$(echo "$body" | grep '^parent:' | tr -d '[]' | sed 's/parent://' | tr ',' ' ' | tr -d ' ' || true)
        local children=$(echo "$body" | grep '^children:' | tr -d '[]' | sed 's/children://' | tr ',' '\n' | sed 's/^[[:space:]]*//' | tr '\n' ' ' || true)
        local overlaps=$(echo "$body" | grep '^overlaps:' | tr -d '[]' | sed 's/overlaps://' | tr ',' '\n' | sed 's/^[[:space:]]*//' | tr '\n' ' ' || true)
        local applies=$(echo "$body" | grep '^applies_to:' | tr -d '[]' | sed 's/applies_to://' | tr ',' '\n' | sed 's/^[[:space:]]*//' | tr '\n' ' ' || true)
        local analogous=$(echo "$body" | grep '^analogous:' | tr -d '[]' | sed 's/analogous://' | tr ',' '\n' | sed 's/^[[:space:]]*//' | tr '\n' ' ' || true)

        for p in $parents $children; do
            [ -n "$p" ] && expanded="${expanded}${p} 20\n"
        done
        for o in $overlaps $applies; do
            [ -n "$o" ] && expanded="${expanded}${o} 10\n"
        done
        for a in $analogous; do
            [ -n "$a" ] && expanded="${expanded}${a} 5\n"
        done
    done

    printf "$expanded"
}

# Lookup: is domain_name in expanded set? Returns best weight or 0
domain_graph_score() {
    local domain_name="$1"
    local expanded_set="$2"
    local best=0

    # Normalize: try both hyphen and underscore forms
    local d_hyphen=$(echo "$domain_name" | tr '_' '-')
    local d_under=$(echo "$domain_name" | tr '-' '_')

    while IFS=' ' read -r dn dw; do
        [ -z "$dn" ] && continue
        local dn_h=$(echo "$dn" | tr '_' '-')
        local dn_u=$(echo "$dn" | tr '-' '_')
        if [ "$dn" = "$domain_name" ] || [ "$dn_h" = "$d_hyphen" ] || [ "$dn_u" = "$d_under" ]; then
            if [ "$dw" -gt "$best" ] 2>/dev/null; then
                best="$dw"
            fi
        fi
    done <<< "$expanded_set"

    echo "$best"
}

