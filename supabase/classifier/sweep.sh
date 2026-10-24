#!/usr/bin/env bash
# Classifies every item in sweep.tsv on the local stack and prints the rows whose category differs
# from the expected one (item, expected, actual). Exits 1 if any differ.
# --print writes the file back with the actual categories, to refresh it after a deliberate change:
#   ./sweep.sh --print > sweep.new && mv sweep.new sweep.tsv
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
project_id="$(sed -n 's/^project_id = "\(.*\)"$/\1/p' "$here/../config.toml")"
rows="$(grep -v '^#' "$here/sweep.tsv" | python3 -I -c 'import sys, json; print(json.dumps([l.rstrip("\n").split("\t") for l in sys.stdin if l.strip()]))')"
result="$(docker exec -i "supabase_db_$project_id" psql -U postgres -v ON_ERROR_STOP=1 -At -F $'\t' <<SQL
begin;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f9', 'sweep@example.com');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000f9", "role": "authenticated"}', true);
create temp table h as select id from public.create_household('Sweep');
select r->>0, coalesce(r->>1, ''), c.seed_key
from json_array_elements(\$rows\$$rows\$rows\$::json) with ordinality t(r, n)
join public.categories c on c.id = public.classify_item((select id from h), r->>0)
order by n;
rollback;
SQL
)"
if [[ ${1:-} == --print ]]; then
  grep '^#' "$here/sweep.tsv"
  awk -F'\t' 'NF == 3 { print $1 "\t" $3 }' <<<"$result"
  exit 0
fi
diff="$(awk -F'\t' 'NF == 3 && $2 != $3' <<<"$result")"
total="$(awk -F'\t' 'NF == 3' <<<"$result" | wc -l)"
if [[ -n $diff ]]; then
  echo "$diff"
  echo "$(wc -l <<<"$diff") of $total items differ" >&2
  exit 1
fi
echo "$total items match" >&2
