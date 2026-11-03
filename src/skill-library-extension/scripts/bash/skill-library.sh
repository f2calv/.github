#!/usr/bin/env bash
# Searches, installs and loads skills from the skill library catalog through the Specify CLI.
#
# The Bash variant of the skill bootstrap helper. It behaves exactly like Invoke-SkillLibrary.ps1
# and python/skill_library.py: same commands, arguments, output and
# .specify/extensions/.skill-library.json state, so a workspace can switch variants at any time.
# After every install, upgrade, removal and prune it copies each enabled skill's
# resources/.github/ into the workspace .github/, recording each copy's SHA-256, and replaces or
# deletes a copy only while its bytes still match, so local edits are kept and reported. Spec Kit
# cannot block specify extension add, remove, enable or disable on a skill, so every command except
# help first warns about skills changed that way since the helper last recorded them.
#
# Usage: skill-library.sh <command> [target] [-Version X.Y.Z] [-Related a,b]
#        [-CatalogUrl url-or-file] [-Workspace path]
# Requires Bash 4+, jq, sha256sum or shasum, and curl for a remote catalog.
# Optional environment variables: SKILL_LIBRARY_CATALOG_URL overrides the catalog_url that the
# bootstrap build packages in the extension's skill-library.json.

if [[ -z ${BASH_VERSINFO[0]:-} || ${BASH_VERSINFO[0]} -lt 4 ]]; then
  echo "Bash 4 or later is required; use the ps or py variant, or install a newer Bash." >&2
  exit 1
fi
: "${SKILL_LIBRARY_CATALOG_URL:=}"

set -euo pipefail

readonly BOOTSTRAP_ID=skill
readonly STATE_FILE=.specify/extensions/.skill-library.json
readonly STATE_SCHEMA=1.2
readonly REGISTRY_FILE=.specify/extensions/.registry
readonly MANAGE_HINT='Manage skills with /speckit-skill-library instead of specify extension add, remove, enable or disable.'

command_name=help
target=''
version=''
related=()
catalog_url=${SKILL_LIBRARY_CATALOG_URL:-}
workspace=$PWD
catalog_file=''
temp_dir=''

# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() { [[ -n $temp_dir ]] && rm -rf "$temp_dir"; return 0; }
trap cleanup EXIT

die() {
  echo "$1" >&2
  exit 1
}

parse_arguments() {
  local positional=()
  while (($#)); do
    case $1 in
      -Version | --version) version=${2:?-Version needs a value}; shift 2 ;;
      -Related | --related)
        local item
        IFS=',' read -r -a items <<< "${2:?-Related needs a value}"
        for item in "${items[@]}"; do
          item=${item//[[:space:]]/}
          [[ -n $item ]] && related+=("$item")
        done
        shift 2
        ;;
      -CatalogUrl | --catalog-url) catalog_url=${2:?-CatalogUrl needs a value}; shift 2 ;;
      -Workspace | --workspace) workspace=${2:?-Workspace needs a value}; shift 2 ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  ((${#positional[@]} > 0)) && command_name=${positional[0]}
  ((${#positional[@]} > 1)) && target=${positional[1]}
  case $command_name in
    help | search | plan | install | upgrade-all | remove | prune | sync | list | load) ;;
    *) die "Unknown command '$command_name'. Run help for the list of commands." ;;
  esac
}

sha256_of() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

sha256_text() {
  if command -v sha256sum > /dev/null; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Prints rows of tab-separated values as a left-aligned table with a dashed header rule.
print_table() {
  local header
  header=$(printf '%s\t' "$@")
  { printf '%s\n' "${header%$'\t'}"; cat; } | awk -F'\t' '
    NR == 1 { for (i = 1; i <= NF; i++) { name[i] = $i; width[i] = length($i) } columns = NF; next }
    { rows[NR] = $0; for (i = 1; i <= NF; i++) if (length($i) > width[i]) width[i] = length($i) }
    END {
      print ""
      line = ""; rule = ""
      for (i = 1; i <= columns; i++) {
        line = line sprintf(i < columns ? "%-" width[i] "s " : "%s", name[i])
        dashes = name[i]; gsub(/./, "-", dashes)
        rule = rule sprintf(i < columns ? "%-" width[i] "s " : "%s", dashes)
      }
      print line; print rule
      for (r = 2; r <= NR; r++) {
        split(rows[r], cell, "\t"); line = ""
        for (i = 1; i <= columns; i++) line = line sprintf(i < columns ? "%-" width[i] "s " : "%s", cell[i])
        sub(/ +$/, "", line); print line
      }
      print ""
    }'
}

# Loads the catalog once, in the main shell, so command substitutions only read the cached file.
ensure_catalog() {
  [[ -n $catalog_url ]] || die "No skill library catalog is configured; set SKILL_LIBRARY_CATALOG_URL or reinstall the skill extension."
  if [[ -z $catalog_file ]]; then
    temp_dir=${temp_dir:-$(mktemp -d)}
    catalog_file=$temp_dir/catalog.json
    if [[ -f $catalog_url ]]; then
      jq '.extensions' "$catalog_url" > "$catalog_file"
    elif [[ $catalog_url == https://* || $catalog_url == http://* ]]; then
      command -v curl > /dev/null || die "curl is required to read a remote catalog."
      curl -fsSL "$catalog_url" | jq '.extensions' > "$catalog_file"
    else
      die "Catalog '$catalog_url' is neither a file nor an HTTP(S) URL."
    fi
  fi
}

catalog() {
  [[ -n $catalog_file ]] || die "Internal error: the catalog was not loaded."
  cat "$catalog_file"
}

installed() {
  local registry=$workspace/$REGISTRY_FILE
  if [[ -f $registry ]]; then jq '.extensions // {}' "$registry"; else echo '{}'; fi
}

state_part() {
  local path=$workspace/$STATE_FILE
  if [[ -f $path ]]; then jq --arg part "$1" '.[$part] // {}' "$path"; else echo '{}'; fi
}

# Prints a JSON array of installed extensions that ship skill guidance under resources/.github/.
skill_extension_ids() {
  local id ids=()
  while read -r id; do
    [[ -z $id || $id == "$BOOTSTRAP_ID" ]] && continue
    if [[ -d $workspace/.specify/extensions/$id/resources/.github ]]; then ids+=("$id"); fi
  done < <(installed | jq -r 'keys[]')
  if ((${#ids[@]})); then printf '%s\n' "${ids[@]}" | jq -R . | jq -sc .; else echo '[]'; fi
}

# Records every installed skill with its version and enabled flag, so report_drift can spot direct specify changes.
save_state() {
  local skills=$1 files=$2 installed_json extensions
  installed_json=$(installed)
  extensions=$(skill_extension_ids)
  mkdir -p "$workspace/.specify/extensions"
  jq -n --indent 2 --arg schema "$STATE_SCHEMA" --argjson skills "$skills" --argjson files "$files" \
    --argjson installed "$installed_json" --argjson extensions "$extensions" '
    {schema_version: $schema,
     skills: ((($skills | keys | map(. as $id | select($installed | has($id)))) + $extensions) | unique
       | map(. as $id | {key: $id, value: {
           chosen: (if $skills | has($id) then $skills[$id].chosen == true else true end),
           version: ($installed[$id].version // "" | tostring),
           enabled: ($installed[$id].enabled != false)}})
       | from_entries),
     files: ($files | to_entries | sort_by(.key) | from_entries)}' > "$workspace/$STATE_FILE"
}

save_manifest() { save_state "$1" "$(state_part files)"; }

# Spec Kit cannot block direct specify extension commands, so report skills they changed behind the helper's back.
report_drift() {
  local path=$workspace/$STATE_FILE installed_json extensions
  [[ -f $path ]] || return 0
  installed_json=$(installed)
  extensions=$(skill_extension_ids)
  # Before schema 1.2 the state did not record every installed skill, so an unrecorded one is not evidence of drift.
  jq -r --arg schema "$STATE_SCHEMA" --arg hint "$MANAGE_HINT" --argjson installed "$installed_json" --argjson extensions "$extensions" '
    (.skills // {}) as $skills | (.schema_version == $schema) as $complete
    | [((($skills | keys) + $extensions) | unique[]) as $id
       | if ($installed | has($id) | not) then
           "Warning: \($id) was removed outside the skill library. Run install \($id) to restore it, or sync to delete its guidance from .github/."
         else
           ($installed[$id].version // "" | tostring) as $version
           | ($installed[$id].enabled != false) as $enabled
           | if ($skills | has($id) | not) then
               (if $complete then "Warning: \($id) \($version) was installed outside the skill library. Run sync to copy its guidance into .github/." else empty end)
             else
               $skills[$id] as $entry
               | (if ($entry | has("version")) and (($entry.version | tostring) != $version) then
                    "Warning: \($id) changed from \($entry.version) to \($version) outside the skill library. Run sync to update its guidance in .github/."
                  else empty end),
                 (if ($entry | has("enabled")) and ($entry.enabled != $enabled) then
                    (if $enabled then "Warning: \($id) was enabled outside the skill library. Run sync to copy its guidance into .github/."
                     else "Warning: \($id) was disabled outside the skill library. Run sync to delete its guidance from .github/." end)
                  else empty end)
             end
         end]
    | if length > 0 then (.[], $hint) else empty end' "$path"
}

# Prints {id, version, required, related} for the current or an exact release, or fails.
release() {
  local id=$1 exact=$2 result
  result=$(catalog | jq -c --arg id "$id" --arg exact "$exact" '
    if has($id) | not then "missing"
    else .[$id] as $e
      | (if $exact == "" or $exact == $e.version then $e
         elif (($e.releases // {}) | has($exact)) then $e.releases[$exact]
         else null end) as $r
      | if $r == null then "unavailable"
        else {id: $id, version: (if $exact == "" then $e.version else $exact end),
              required: ($r.skill_library.required // []), related: ($r.skill_library.related // [])}
        end
    end')
  case $result in
    '"missing"') die "Sorry, we can't find the skill '$id'." ;;
    '"unavailable"') die "Version $exact of '$id' is not available." ;;
  esac
  echo "$result"
}

installed_release() {
  local id=$1 version=$2 result
  if result=$( (release "$id" "$version") 2> /dev/null); then echo "$result"; else release "$id" ''; fi
}

installed_version() { installed | jq -r --arg id "$1" '.[$id].version // empty'; }

is_chosen() {
  local manifest=$1 id=$2
  [[ $(jq -r --arg id "$id" 'if has($id) then (.[$id].chosen == true) else true end' <<< "$manifest") == true ]]
}

unneeded() {
  local installed_json catalog_json manifest id
  installed_json=$(installed)
  catalog_json=$(catalog)
  manifest=$(state_part skills)
  declare -A needed=()
  local stack=()
  while read -r id; do
    [[ -z $id || $id == "$BOOTSTRAP_ID" ]] && continue
    is_chosen "$manifest" "$id" && stack+=("$id")
  done < <(jq -r 'keys[]' <<< "$installed_json")
  while ((${#stack[@]})); do
    id=${stack[-1]}
    unset 'stack[-1]'
    [[ -n ${needed[$id]:-} ]] && continue
    jq -e --arg id "$id" 'has($id)' <<< "$installed_json" > /dev/null || continue
    jq -e --arg id "$id" 'has($id)' <<< "$catalog_json" > /dev/null || continue
    needed[$id]=1
    while read -r required; do
      [[ -n $required ]] && stack+=("$required")
    done < <(installed_release "$id" "$(installed_version "$id")" | jq -r '.required[].id')
  done
  while read -r id; do
    [[ -z $id || $id == "$BOOTSTRAP_ID" || -n ${needed[$id]:-} ]] && continue
    if jq -e --arg id "$id" 'has($id)' <<< "$catalog_json" > /dev/null; then echo "$id"; fi
  done < <(jq -r 'keys[]' <<< "$installed_json" | LC_ALL=C sort)
  return 0
}

show_unneeded() {
  local ids
  ids=$(paste -sd, - | sed 's/,/, /g')
  [[ -n $ids ]] && echo "No longer required by any chosen skill: $ids. Run prune to remove them."
  return 0
}

remove_empty_parents() {
  local stop=$workspace/.github folder
  folder=$(dirname "$1")
  while [[ $folder != "$stop" && $folder == "$stop"/* && -d $folder && -z $(ls -A "$folder") ]]; do
    rmdir "$folder"
    folder=$(dirname "$folder")
  done
}

# Mirrors enabled skills' resources/.github/ into .github/, touching a copy only while it matches its record.
sync_guidance() {
  local installed_json records skills id root source rel hash
  installed_json=$(installed)
  records=$(state_part files)
  skills=$(state_part skills)
  declare -A want_source=() want_skill=() want_version=() want_hash=()
  local order=() notes=()
  while read -r id; do
    [[ -z $id || $id == "$BOOTSTRAP_ID" ]] && continue
    [[ $(jq -r --arg id "$id" '.[$id].enabled' <<< "$installed_json") == false ]] && continue
    root=$workspace/.specify/extensions/$id/resources/.github
    [[ -d $root ]] || continue
    while IFS= read -r -d '' source; do
      rel=.github/${source#"$root"/}
      hash=$(sha256_of "$source")
      if [[ -n ${want_hash[$rel]:-} ]]; then
        [[ ${want_hash[$rel]} != "$hash" ]] && notes+=("Kept $rel from ${want_skill[$rel]}; $id ships a different copy.")
        continue
      fi
      order+=("$rel")
      want_source[$rel]=$source
      want_skill[$rel]=$id
      want_version[$rel]=$(jq -r --arg id "$id" '.[$id].version // ""' <<< "$installed_json")
      want_hash[$rel]=$hash
    done < <(find "$root" -type f -print0 | LC_ALL=C sort -z)
  done < <(jq -r 'keys[]' <<< "$installed_json" | LC_ALL=C sort)

  local following='{}' copied=0 updated=0 removed=0 path current record recorded new_record
  for rel in "${order[@]}"; do
    path=$workspace/$rel
    current=''
    [[ -f $path ]] && current=$(sha256_of "$path")
    record=$(jq -c --arg rel "$rel" '.[$rel] // empty' <<< "$records")
    recorded=''
    [[ -n $record ]] && recorded=$(jq -r '.sha256 // ""' <<< "$record")
    new_record=$(jq -cn --arg sha "${want_hash[$rel]}" --arg skill "${want_skill[$rel]}" --arg version "${want_version[$rel]}" --arg copied "$(utc_now)" \
      '{sha256: $sha, skill: $skill, version: $version, copied: $copied}')
    if [[ -n $current && $current == "${want_hash[$rel]}" ]]; then
      [[ -z $record || $recorded != "$current" ]] && record=$new_record
      following=$(jq -c --arg rel "$rel" --argjson record "$record" '.[$rel] = $record' <<< "$following")
      continue
    fi
    if [[ -n $current && -z $record ]]; then
      notes+=("Kept $rel: it exists and was not copied by the skill library.")
      continue
    fi
    if [[ -n $current && $current != "$recorded" ]]; then
      notes+=("Kept $rel: modified since $(jq -r '"\(.skill) \(.version) copied it on \(.copied)"' <<< "$record"); ${want_skill[$rel]} ${want_version[$rel]} was not applied.")
      following=$(jq -c --arg rel "$rel" --argjson record "$record" '.[$rel] = $record' <<< "$following")
      continue
    fi
    mkdir -p "$(dirname "$path")"
    cp "${want_source[$rel]}" "$path"
    if [[ -n $current ]]; then updated=$((updated + 1)); else copied=$((copied + 1)); fi
    following=$(jq -c --arg rel "$rel" --argjson record "$new_record" '.[$rel] = $record' <<< "$following")
  done

  while IFS=$'\t' read -r rel recorded; do
    [[ -z $rel || -n ${want_hash[$rel]:-} ]] && continue
    [[ $rel == .github/* && ! $rel =~ (^|/)\.\.(/|$) ]] || continue
    path=$workspace/$rel
    [[ -f $path ]] || continue
    if [[ $(sha256_of "$path") != "$recorded" ]]; then
      notes+=("Kept $rel: modified since $(jq -r --arg rel "$rel" '.[$rel] | "\(.skill) \(.version) copied it on \(.copied)"' <<< "$records"). Review it before deleting it.")
      continue
    fi
    rm -f "$path"
    remove_empty_parents "$path"
    removed=$((removed + 1))
  done < <(jq -r 'to_entries | sort_by(.key)[] | [.key, (.value.sha256 // "")] | @tsv' <<< "$records")

  save_state "$skills" "$following"
  echo "Guidance in .github/: $copied copied, $updated updated, $removed removed."
  ((${#notes[@]})) && printf '%s\n' "${notes[@]}"
  return 0
}

run_specify() {
  command -v specify > /dev/null || die "The specify CLI is not on PATH."
  echo "specify $*"
  (cd "$workspace" && specify "$@")
}

invoke_remove() {
  local id
  for id in "$@"; do
    run_specify extension remove "$id" --force || die "Removing $id failed; skills listed before it were removed."
  done
  save_manifest "$(state_part skills)"
}

# Reads tab-separated id, version and action lines and installs or upgrades each one.
invoke_specify() {
  local cache prefix id step_version action
  prefix=$(sha256_text "$catalog_url" | cut -c1-16)
  cache=$workspace/.specify/extensions/.cache
  [[ -d $cache ]] && find "$cache" -maxdepth 1 -name "catalog-$prefix*.json" -delete
  while IFS=$'\t' read -r id step_version action; do
    [[ -z $id ]] && continue
    local arguments=(extension add "$id" --version "$step_version")
    [[ $action == upgrade* ]] && arguments+=(--force)
    SPECKIT_CATALOG_URL=$catalog_url run_specify "${arguments[@]}" < /dev/null \
      || die "Installing $id $step_version failed; earlier skills in the order remain installed."
  done
  return 0
}

require_target() { [[ -n $target ]] || die "The $command_name command needs a skill ID."; }

declare -A plan_version=()
plan_steps=()
plan_chosen=()

plan_add() {
  local id=$1 exact=$2 reason=$3 rel current action edge_id edge_version
  if [[ -n ${plan_version[$id]:-} ]]; then
    if [[ -n $exact && ${plan_version[$id]} != "$exact" ]]; then
      die "Conflicting versions of '$id': ${plan_version[$id]} and $exact."
    fi
    return 0
  fi
  rel=$(release "$id" "$exact")
  plan_version[$id]=$(jq -r '.version' <<< "$rel")
  plan_chosen+=("$rel")
  while IFS=$'\t' read -r edge_id edge_version; do
    [[ -n $edge_id ]] && plan_add "$edge_id" "$edge_version" "required by $id"
  done < <(jq -r '.required[] | [.id, .version] | @tsv' <<< "$rel")
  current=$(installed_version "$id")
  if [[ -z $current ]]; then
    action=install
  elif [[ $current == "${plan_version[$id]}" ]]; then
    action=installed
  else
    action="conflict: $current installed"
  fi
  plan_steps+=("$id"$'\t'"${plan_version[$id]}"$'\t'"$action"$'\t'"$reason")
}

resolve_plan() {
  local id
  plan_add "$target" "$version" requested
  for id in "${related[@]}"; do plan_add "$id" '' 'related, selected'; done
}

plan_offers() {
  local installed_json chosen_ids
  installed_json=$(installed)
  chosen_ids=$(printf '%s\n' "${!plan_version[@]}" | jq -R . | jq -sc .)
  printf '%s\n' "${plan_chosen[@]}" | jq -r --argjson chosen "$chosen_ids" --argjson installed "$installed_json" '
    .id as $by | .related[] | .id as $id | select($chosen | index($id) | not)
    | [$id, (if $installed | has($id) then "installed" else "not installed" end), $by, (.reason // "")] | @tsv' \
    | LC_ALL=C sort -t$'\t' -k1,1 -k3,3 -u
}

show_plan() {
  echo 'Install order:'
  printf '%s\n' "${plan_steps[@]}" | awk -F'\t' -v OFS='\t' '{ print $1, $2, $3, $4 }' | print_table Id Version Action Reason
  local offers
  offers=$(plan_offers)
  if [[ -n $offers ]]; then
    echo 'Related skills you can add with -Related:'
    print_table Id State OfferedBy Reason <<< "$offers"
  fi
}

version_gt() {
  local IFS=. left right i
  read -r -a left <<< "$1"
  read -r -a right <<< "$2"
  for i in 0 1 2; do
    ((10#${left[i]:-0} > 10#${right[i]:-0})) && return 0
    ((10#${left[i]:-0} < 10#${right[i]:-0})) && return 1
  done
  return 1
}

declare -A upgrade_target=() upgrade_visited=()
upgrade_steps=()

upgrade_add() {
  local id=$1 rel edge_id edge_version current action latest
  [[ -n ${upgrade_visited[$id]:-} ]] && return 0
  upgrade_visited[$id]=1
  rel=${upgrade_target[$id]}
  while IFS=$'\t' read -r edge_id edge_version; do
    [[ -z $edge_id ]] && continue
    [[ -z ${upgrade_target[$edge_id]:-} ]] && upgrade_target[$edge_id]=$(release "$edge_id" "$edge_version")
    latest=$(jq -r '.version' <<< "${upgrade_target[$edge_id]}")
    if [[ $latest != "$edge_version" ]]; then
      die "$id $(jq -r '.version' <<< "$rel") requires $edge_id $edge_version, but the latest is $latest. Nothing was changed."
    fi
    upgrade_add "$edge_id"
  done < <(jq -r '.required[] | [.id, .version] | @tsv' <<< "$rel")
  local target_version
  target_version=$(jq -r '.version' <<< "$rel")
  current=$(installed_version "$id")
  if [[ -z $current ]]; then
    action=install
  elif [[ $current == "$target_version" ]]; then
    action=current
  elif version_gt "$current" "$target_version"; then
    action="newer $current installed"
  else
    action="upgrade from $current"
  fi
  upgrade_steps+=("$id"$'\t'"$target_version"$'\t'"$action")
}

resolve_upgrade() {
  local id catalog_json
  catalog_json=$(catalog)
  local ids=()
  while read -r id; do
    [[ -z $id || $id == "$BOOTSTRAP_ID" ]] && continue
    jq -e --arg id "$id" 'has($id)' <<< "$catalog_json" > /dev/null || continue
    upgrade_target[$id]=$(release "$id" '')
    ids+=("$id")
  done < <(installed | jq -r 'keys[]' | LC_ALL=C sort)
  for id in "${ids[@]}"; do upgrade_add "$id"; done
}

command_help() {
  echo 'Commands: search <terms> | plan <id> | install <id> [-Version X.Y.Z] [-Related a,b] | upgrade-all | remove <id> | prune | sync | list | load <id>'
}

command_search() {
  local terms rows
  terms=$(jq -Rc 'ascii_downcase | [splits("\\s+") | select(length > 0)]' <<< "$target")
  rows=$(catalog | jq -r --argjson terms "$terms" --arg bootstrap "$BOOTSTRAP_ID" '
    to_entries | sort_by(.key)[] | select(.key != $bootstrap)
    | (([.key, (.value.description // "")] + (.value.tags // [])) | join(" ") | ascii_downcase) as $text
    | select(all($terms[]; . as $term | $text | contains($term)))
    | [.key, .value.version, ((.value.tags // []) | join(", ")), (.value.description // "")] | @tsv')
  if [[ -z $rows ]]; then
    echo "Sorry, we can't find a skill matching '$target'."
  else
    print_table Id Version Facets Description <<< "$rows"
  fi
}

command_plan() {
  require_target
  resolve_plan
  show_plan
}

command_install() {
  require_target
  resolve_plan
  show_plan
  local conflicts step id step_version action reason manifest
  conflicts=$(printf '%s\n' "${plan_steps[@]}" | awk -F'\t' '$3 ~ /^conflict/ { print $1 }' | paste -sd, - | sed 's/,/, /g')
  [[ -n $conflicts ]] && die "Resolve version conflicts first: $conflicts. Nothing was installed."
  printf '%s\n' "${plan_steps[@]}" | awk -F'\t' -v OFS='\t' '$3 == "install" { print $1, $2, $3 }' | invoke_specify
  manifest=$(state_part skills)
  for step in "${plan_steps[@]}"; do
    IFS=$'\t' read -r id step_version action reason <<< "$step"
    if [[ $reason == requested || $reason == 'related, selected' ]]; then
      manifest=$(jq -c --arg id "$id" '.[$id] = {chosen: true}' <<< "$manifest")
    elif [[ $action == install ]]; then
      manifest=$(jq -c --arg id "$id" 'if has($id) then . else .[$id] = {chosen: false} end' <<< "$manifest")
    fi
  done
  save_manifest "$manifest"
  sync_guidance
  echo 'Installed. Run plan for newly installed related skills to see their related offers.'
}

new_related_offers() {
  local before=$1 pending=$2 installed_json step id step_version previous
  installed_json=$(installed)
  while IFS=$'\t' read -r id step_version _; do
    [[ -z $id ]] && continue
    previous='[]'
    local was
    was=$(jq -r --arg id "$id" '.[$id].version // empty' <<< "$before")
    if [[ -n $was ]]; then
      previous=$( (release "$id" "$was") 2> /dev/null | jq -c '[.related[].id]') || previous='[]'
    fi
    release "$id" "$step_version" | jq -r --argjson previous "${previous:-[]}" --argjson installed "$installed_json" --arg by "$id" '
      .related[] | select(.id as $id | ($previous | index($id) | not) and ($installed | has($id) | not))
      | [.id, $by, (.reason // "")] | @tsv'
  done <<< "$pending" | LC_ALL=C sort -t$'\t' -k1,1 -k2,2 -u
}

command_upgrade_all() {
  resolve_upgrade
  if ((${#upgrade_steps[@]} == 0)); then
    echo 'No skills are installed.'
    sync_guidance
    return 0
  fi
  echo 'Upgrade order:'
  printf '%s\n' "${upgrade_steps[@]}" | print_table Id Version Action
  local pending before manifest id step_version action offers count
  pending=$(printf '%s\n' "${upgrade_steps[@]}" | awk -F'\t' '$3 == "install" || $3 ~ /^upgrade/')
  if [[ -z $pending ]]; then
    echo 'All installed skills are at their latest versions.'
  else
    before=$(installed)
    invoke_specify <<< "$pending"
    manifest=$(state_part skills)
    while IFS=$'\t' read -r id step_version action; do
      [[ $action == install ]] && manifest=$(jq -c --arg id "$id" 'if has($id) then . else .[$id] = {chosen: false} end' <<< "$manifest")
    done <<< "$pending"
    save_manifest "$manifest"
    count=$(grep -c . <<< "$pending")
    echo "Upgraded $count skill(s)."
    offers=$(new_related_offers "$before" "$pending")
    if [[ -n $offers ]]; then
      echo 'New related skills you can add with install <id>:'
      print_table Id OfferedBy Reason <<< "$offers"
    fi
  fi
  sync_guidance
  unneeded | show_unneeded
}

command_remove() {
  require_target
  [[ $target == "$BOOTSTRAP_ID" ]] && die "Remove the bootstrap with: specify extension remove $BOOTSTRAP_ID"
  [[ -n $(installed_version "$target") ]] || jq -e --arg id "$target" 'has($id)' <<< "$(installed)" > /dev/null \
    || die "'$target' is not installed."
  local catalog_json dependents=() id
  catalog_json=$(catalog)
  while read -r id; do
    [[ -z $id || $id == "$BOOTSTRAP_ID" || $id == "$target" ]] && continue
    jq -e --arg id "$id" 'has($id)' <<< "$catalog_json" > /dev/null || continue
    if installed_release "$id" "$(installed_version "$id")" | jq -e --arg target "$target" 'any(.required[]; .id == $target)' > /dev/null; then
      dependents+=("$id")
    fi
  done < <(installed | jq -r 'keys[]' | LC_ALL=C sort)
  if ((${#dependents[@]})); then
    die "'$target' is required by $(printf '%s\n' "${dependents[@]}" | paste -sd, - | sed 's/,/, /g'). Remove those first. Nothing was changed."
  fi
  invoke_remove "$target"
  sync_guidance
  unneeded | show_unneeded
}

command_prune() {
  local ids=()
  mapfile -t ids < <(unneeded)
  if ((${#ids[@]} == 0)); then
    echo 'Nothing to prune: every installed skill is chosen or required by one.'
    return 0
  fi
  invoke_remove "${ids[@]}"
  echo "Removed ${#ids[@]} skill(s)."
  sync_guidance
}

command_sync() { sync_guidance; }

command_list() {
  local manifest rows='' id version enabled source
  manifest=$(state_part skills)
  while IFS=$'\t' read -r id version enabled; do
    [[ -z $id || $id == "$BOOTSTRAP_ID" ]] && continue
    [[ -e $workspace/.specify/extensions/$id/resources ]] || continue
    if is_chosen "$manifest" "$id"; then source=chosen; else source=required; fi
    rows+="$id"$'\t'"$version"$'\t'"$enabled"$'\t'"$source"$'\n'
  done < <(installed | jq -r 'to_entries | sort_by(.key)[]
    | [.key, (.value.version // ""), (if .value.enabled == true then "True" elif .value.enabled == false then "False" else "" end)] | @tsv')
  if [[ -z $rows ]]; then
    echo 'No skills are installed.'
    return 0
  fi
  print_table Id Version Enabled Source <<< "${rows%$'\n'}"
  unneeded | show_unneeded
}

command_load() {
  require_target
  local root=$workspace/.specify/extensions/$target/resources
  [[ -e $root ]] || die "'$target' is not installed; run install first."
  echo "Installed files for $target (read SKILL.md first, then instructions, then others as needed):"
  find "$root" -type f | while IFS= read -r file; do
    local rel=${file#"$workspace"/} rank=2
    [[ $rel == */SKILL.md ]] && rank=0
    [[ $rank == 2 && $rel == *.instructions.md ]] && rank=1
    printf '%s\t%s\n' "$rank" "$rel"
  done | LC_ALL=C sort -t$'\t' -k1,1n -k2,2 | cut -f2-
}

main() {
  parse_arguments "$@"
  command -v jq > /dev/null || die "jq is required by the Bash variant; install jq or use the ps or py variant."
  if [[ -z $catalog_url ]]; then
    local packaged
    packaged=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/skill-library.json
    if [[ -f $packaged ]]; then catalog_url=$(jq -r '.catalog_url // ""' "$packaged"); fi
  fi
  workspace=$(cd "$workspace" && pwd)
  if [[ $command_name != help ]]; then report_drift; fi
  case $command_name in
    search | plan | install | upgrade-all | remove | prune | list) ensure_catalog ;;
  esac
  case $command_name in
    help) command_help ;;
    search) command_search ;;
    plan) command_plan ;;
    install) command_install ;;
    upgrade-all) command_upgrade_all ;;
    remove) command_remove ;;
    prune) command_prune ;;
    sync) command_sync ;;
    list) command_list ;;
    load) command_load ;;
  esac
}

main "$@"
