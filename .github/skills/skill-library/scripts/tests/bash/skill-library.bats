#!/usr/bin/env bats
# Behaviour tests for the Bash skill library helper.
#
# These mirror the Pester scenarios in Invoke-SkillLibrary.Tests.ps1 and the pytest scenarios in
# python/test_skill_library.py so the three helper variants stay in parity. The helper runs against
# the shared catalog fixtures with a fake specify first on PATH. Requires bats-core with the
# bats-support and bats-assert libraries on BATS_LIB_PATH, plus jq.

bats_require_minimum_version 1.5.0

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert
  TESTS=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  REPO=$(cd "$TESTS/../../../../.." && pwd)
  SCRIPT=$REPO/src/skill-library-extension/scripts/bash/skill-library.sh
  CATALOG=$TESTS/fixtures/helper/catalog.json
  CHANGED=$TESTS/fixtures/helper/catalog-changed.json
  WS=$BATS_TEST_TMPDIR/workspace
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$WS/.specify/extensions"
  cp "$TESTS/fixtures/helper/specify" "$BATS_TEST_TMPDIR/bin/specify"
  chmod +x "$BATS_TEST_TMPDIR/bin/specify"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  unset SPECKIT_CATALOG_URL SKILL_LIBRARY_CATALOG_URL
  write_registry '{"skill":{"version":"1.0.0","enabled":true}}'
}

write_registry() { printf '{"schema_version":"1.0","extensions":%s}\n' "$1" > "$WS/.specify/extensions/.registry"; }
lib() { bash "$SCRIPT" "$@" -CatalogUrl "$CATALOG" -Workspace "$WS"; }
changed_lib() { bash "$SCRIPT" "$@" -CatalogUrl "$CHANGED" -Workspace "$WS"; }
state() { jq -r "$1" "$WS/.specify/extensions/.skill-library.json"; }
# Simulates a user running specify extension commands directly, outside the helper.
direct() { (cd "$WS" && specify "$@") > /dev/null; }
set_enabled() {
  jq --arg id "$1" --argjson enabled "$2" '.extensions[$id].enabled = $enabled' "$WS/.specify/extensions/.registry" > "$WS/registry.tmp"
  mv "$WS/registry.tmp" "$WS/.specify/extensions/.registry"
}
MANAGE_HINT='Manage skills with /speckit-skill-library instead of specify extension add, remove, enable or disable.'

@test "lists commands by default" {
  run lib
  assert_success
  assert_output --partial 'Commands: search'
}

@test "searches IDs, descriptions and facets" {
  run lib search architecture
  assert_success
  assert_output --regexp 'alpha[[:space:]]+1\.1\.0'
  refute_output --partial beta
  run lib search nothing
  assert_output --partial "can't find a skill matching 'nothing'"
}

@test "plans required skills first and offers related skills" {
  run lib plan alpha
  assert_success
  assert_output --regexp 'beta[[:space:]]+1\.0\.0[[:space:]]+install[[:space:]]+required by alpha.*alpha[[:space:]]+1\.1\.0[[:space:]]+install[[:space:]]+requested'
  assert_output --regexp 'gamma[[:space:]]+not installed[[:space:]]+alpha[[:space:]]+Optional extra\.'
}

@test "plans an exact older version with a selected related skill and reports conflicts" {
  write_registry '{"beta":{"version":"0.9.0","enabled":true}}'
  run lib plan alpha -Version 1.0.0 -Related gamma
  assert_success
  assert_output --regexp 'beta[[:space:]]+1\.0\.0[[:space:]]+conflict: 0\.9\.0 installed'
  assert_output --regexp 'alpha[[:space:]]+1\.0\.0[[:space:]]+install'
  assert_output --regexp 'gamma[[:space:]]+1\.0\.0[[:space:]]+install[[:space:]]+related, selected'
}

@test "installs in dependency order through specify with the library catalog" {
  run lib install alpha -Related gamma
  assert_success
  run cat "$WS/specify.log"
  assert_output "extension add beta --version 1.0.0 catalog=$CATALOG
extension add alpha --version 1.1.0 catalog=$CATALOG
extension add gamma --version 1.0.0 catalog=$CATALOG"
  run lib install alpha
  assert_success
  [ "$(wc -l < "$WS/specify.log")" -eq 3 ]
}

@test "refuses to install over a different installed version" {
  write_registry '{"beta":{"version":"0.9.0","enabled":true}}'
  run --separate-stderr lib install alpha
  assert_failure 1
  [[ $stderr == *'Resolve version conflicts first: beta'* ]]
  [ ! -e "$WS/specify.log" ]
}

@test "upgrades installed skills to their latest versions, required skills first" {
  lib install alpha -Version 1.0.0 > /dev/null
  rm "$WS/specify.log"
  run lib upgrade-all
  assert_success
  assert_output --regexp 'beta[[:space:]]+1\.0\.0[[:space:]]+current.*alpha[[:space:]]+1\.1\.0[[:space:]]+upgrade from 1\.0\.0'
  run cat "$WS/specify.log"
  assert_output "extension add alpha --version 1.1.0 --force catalog=$CATALOG"
  run lib upgrade-all
  assert_output --partial 'All installed skills are at their latest versions'
}

@test "reports when no skills are installed to upgrade" {
  run lib upgrade-all
  assert_success
  assert_output --partial 'No skills are installed'
}

@test "records chosen and required skills when installing" {
  lib install alpha -Version 1.0.0 -Related gamma > /dev/null
  [ "$(state '.skills.alpha.chosen')" = true ]
  [ "$(state '.skills.gamma.chosen')" = true ]
  [ "$(state '.skills.beta.chosen')" = false ]
  lib install beta > /dev/null
  [ "$(state '.skills.beta.chosen')" = true ]
  run lib list
  assert_output --regexp 'beta[[:space:]]+1\.0\.0[[:space:]]+True[[:space:]]+chosen'
}

@test "upgrades into changed dependencies: installs new required skills, offers new related skills and reports unneeded ones" {
  lib install alpha -Version 1.0.0 > /dev/null
  rm "$WS/specify.log"
  run changed_lib upgrade-all
  assert_success
  assert_output --regexp 'epsilon[[:space:]]+alpha[[:space:]]+New extra\.'
  refute_output --regexp 'gamma[[:space:]]+alpha'
  assert_output --partial 'No longer required by any chosen skill: beta. Run prune to remove them.'
  run cat "$WS/specify.log"
  assert_output "extension add delta --version 1.0.0 catalog=$CHANGED
extension add alpha --version 1.1.0 --force catalog=$CHANGED"
  [ "$(state '.skills.delta.chosen')" = false ]
  run changed_lib list
  assert_output --regexp 'delta[[:space:]]+1\.0\.0[[:space:]]+True[[:space:]]+required'
}

@test "prunes only skills no chosen skill requires" {
  lib install alpha -Version 1.0.0 > /dev/null
  changed_lib upgrade-all > /dev/null
  rm "$WS/specify.log"
  run changed_lib prune
  assert_success
  assert_output --partial 'Removed 1 skill(s).'
  run cat "$WS/specify.log"
  assert_output 'extension remove beta --force catalog='
  run jq -r '.extensions | keys | join(",")' "$WS/.specify/extensions/.registry"
  assert_output 'alpha,delta,skill'
  [ "$(state '.skills | has("beta")')" = false ]
  run changed_lib prune
  assert_output --partial 'Nothing to prune'
}

@test "never prunes skills installed before choices were recorded" {
  write_registry '{"skill":{"version":"1.0.0","enabled":true},"beta":{"version":"1.0.0","enabled":true}}'
  run lib prune
  assert_success
  assert_output --partial 'Nothing to prune'
  [ ! -e "$WS/specify.log" ]
}

@test "lists installed skills and loads their files with SKILL.md first" {
  lib install beta > /dev/null
  run lib list
  assert_output --regexp 'beta[[:space:]]+1\.0\.0[[:space:]]+True[[:space:]]+chosen'
  run lib load beta
  assert_success
  assert_line --index 1 '.specify/extensions/beta/resources/.github/skills/beta/SKILL.md'
  run --separate-stderr lib load gamma
  assert_failure 1
  [[ $stderr == *"'gamma' is not installed"* ]]
}

@test "reports an unknown skill" {
  run --separate-stderr lib plan missing
  assert_failure 1
  [[ $stderr == *"can't find the skill 'missing'"* ]]
}

@test "copies installed guidance into .github and records each copy" {
  run lib install alpha
  assert_success
  assert_output --partial 'Guidance in .github/: 3 copied, 0 updated, 0 removed.'
  [ "$(cat "$WS/.github/skills/alpha/SKILL.md")" = '# Skill alpha 1.1.0' ]
  [ "$(cat "$WS/.github/skills/beta/SKILL.md")" = '# Skill beta 1.0.0' ]
  [ "$(cat "$WS/.github/instructions/shared.instructions.md")" = '# Shared' ]
  run state '.files | keys | join(",")'
  assert_output '.github/instructions/shared.instructions.md,.github/skills/alpha/SKILL.md,.github/skills/beta/SKILL.md'
  [ "$(state '.files[".github/skills/alpha/SKILL.md"].sha256')" = "$(sha256sum "$WS/.github/skills/alpha/SKILL.md" | cut -d' ' -f1)" ]
  [ "$(state '.files[".github/skills/alpha/SKILL.md"].version')" = 1.1.0 ]
  [ "$(state '.files[".github/instructions/shared.instructions.md"].skill')" = alpha ]
}

@test "updates unmodified copies on upgrade" {
  lib install alpha -Version 1.0.0 > /dev/null
  run lib upgrade-all
  assert_output --partial 'Guidance in .github/: 0 copied, 1 updated, 0 removed.'
  [ "$(cat "$WS/.github/skills/alpha/SKILL.md")" = '# Skill alpha 1.1.0' ]
  [ "$(state '.files[".github/skills/alpha/SKILL.md"].version')" = 1.1.0 ]
}

@test "keeps a modified copy on upgrade and reports it" {
  lib install alpha -Version 1.0.0 > /dev/null
  echo '# Local edit' > "$WS/.github/skills/alpha/SKILL.md"
  run lib upgrade-all
  assert_success
  assert_output --regexp 'Kept \.github/skills/alpha/SKILL\.md: modified since alpha 1\.0\.0 copied it on [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z; alpha 1\.1\.0 was not applied\.'
  [ "$(cat "$WS/.github/skills/alpha/SKILL.md")" = '# Local edit' ]
  [ "$(state '.files[".github/skills/alpha/SKILL.md"].version')" = 1.0.0 ]
}

@test "removes a skill with its unmodified copies and keeps modified ones" {
  lib install gamma > /dev/null
  lib install beta > /dev/null
  run lib remove beta
  assert_success
  assert_output --partial 'Guidance in .github/: 0 copied, 0 updated, 1 removed.'
  [ ! -e "$WS/.github/skills/beta" ]
  [ -e "$WS/.github/instructions/shared.instructions.md" ]
  echo '# Local edit' > "$WS/.github/skills/gamma/SKILL.md"
  run lib remove gamma
  assert_success
  assert_output --regexp 'Kept \.github/skills/gamma/SKILL\.md: modified since gamma 1\.0\.0 copied it on .*\. Review it before deleting it\.'
  assert_output --partial '1 removed.'
  [ "$(cat "$WS/.github/skills/gamma/SKILL.md")" = '# Local edit' ]
  [ ! -e "$WS/.github/instructions" ]
  [ "$(state '.files | length')" -eq 0 ]
  run tail -n 2 "$WS/specify.log"
  assert_output 'extension remove beta --force catalog=
extension remove gamma --force catalog='
}

@test "refuses to remove a skill another installed skill requires" {
  lib install alpha > /dev/null
  run --separate-stderr lib remove beta
  assert_failure 1
  [[ $stderr == *"'beta' is required by alpha"* ]]
  run grep -c 'extension remove beta' "$WS/specify.log"
  assert_output 0
  run --separate-stderr lib remove skill
  assert_failure 1
  [[ $stderr == *'specify extension remove skill'* ]]
}

@test "never overwrites or deletes a file it did not copy" {
  mkdir -p "$WS/.github/skills/beta"
  echo '# Mine' > "$WS/.github/skills/beta/SKILL.md"
  run lib install beta
  assert_success
  assert_output --partial 'Kept .github/skills/beta/SKILL.md: it exists and was not copied by the skill library.'
  [ "$(state '.files | has(".github/skills/beta/SKILL.md")')" = false ]
  lib remove beta > /dev/null
  [ "$(cat "$WS/.github/skills/beta/SKILL.md")" = '# Mine' ]
}

@test "restores missing copies on sync" {
  lib install beta > /dev/null
  rm "$WS/.github/skills/beta/SKILL.md"
  run lib sync
  assert_success
  assert_output --partial 'Guidance in .github/: 1 copied, 0 updated, 0 removed.'
  [ "$(cat "$WS/.github/skills/beta/SKILL.md")" = '# Skill beta 1.0.0' ]
}

@test "records the version and enabled flag of every installed skill" {
  run lib install alpha -Version 1.0.0
  assert_success
  refute_output --partial 'Warning:'
  [ "$(state '.schema_version')" = 1.2 ]
  [ "$(state '.skills.alpha.version')" = 1.0.0 ]
  [ "$(state '.skills.alpha.enabled')" = true ]
  [ "$(state '.skills.beta.version')" = 1.0.0 ]
  run lib upgrade-all
  refute_output --partial 'Warning:'
  [ "$(state '.skills.alpha.version')" = 1.1.0 ]
}

@test "warns about a skill removed outside the skill library until sync deletes its guidance" {
  lib install gamma > /dev/null
  direct extension remove gamma --force
  run lib list
  assert_success
  assert_output --partial 'Warning: gamma was removed outside the skill library. Run install gamma to restore it, or sync to delete its guidance from .github/.'
  assert_output --partial "$MANAGE_HINT"
  run lib help
  refute_output --partial 'Warning:'
  run lib sync
  assert_output --partial 'Guidance in .github/: 0 copied, 0 updated, 2 removed.'
  [ ! -e "$WS/.github/skills/gamma" ]
  run lib list
  refute_output --partial 'Warning:'
}

@test "warns about skills installed or upgraded outside the skill library until sync copies their guidance" {
  lib install alpha -Version 1.0.0 > /dev/null
  direct extension add gamma --version 1.0.0
  direct extension add alpha --version 1.1.0 --force
  run lib list
  assert_success
  assert_output --partial 'Warning: alpha changed from 1.0.0 to 1.1.0 outside the skill library. Run sync to update its guidance in .github/.'
  assert_output --partial 'Warning: gamma 1.0.0 was installed outside the skill library. Run sync to copy its guidance into .github/.'
  assert_output --partial "$MANAGE_HINT"
  run lib sync
  assert_output --partial 'Guidance in .github/: 1 copied, 1 updated, 0 removed.'
  [ "$(cat "$WS/.github/skills/alpha/SKILL.md")" = '# Skill alpha 1.1.0' ]
  [ "$(cat "$WS/.github/skills/gamma/SKILL.md")" = '# Skill gamma 1.0.0' ]
  run lib list
  refute_output --partial 'Warning:'
  assert_output --regexp 'gamma[[:space:]]+1\.0\.0[[:space:]]+True[[:space:]]+chosen'
}

@test "warns about a skill disabled or enabled outside the skill library until sync applies it" {
  lib install beta > /dev/null
  set_enabled beta false
  run lib list
  assert_output --partial 'Warning: beta was disabled outside the skill library. Run sync to delete its guidance from .github/.'
  run lib sync
  assert_output --partial 'Guidance in .github/: 0 copied, 0 updated, 2 removed.'
  run lib list
  refute_output --partial 'Warning:'
  set_enabled beta true
  run lib list
  assert_output --partial 'Warning: beta was enabled outside the skill library. Run sync to copy its guidance into .github/.'
  run lib sync
  assert_output --partial 'Guidance in .github/: 2 copied, 0 updated, 0 removed.'
  run lib list
  refute_output --partial 'Warning:'
}

@test "does not treat skills missing from an older state file as installed outside" {
  echo '{"schema_version":"1.1","skills":{},"files":{}}' > "$WS/.specify/extensions/.skill-library.json"
  direct extension add beta --version 1.0.0
  run lib list
  assert_success
  refute_output --partial 'Warning:'
  lib sync > /dev/null
  [ "$(state '.skills.beta.chosen')" = true ]
  run lib list
  refute_output --partial 'Warning:'
}
