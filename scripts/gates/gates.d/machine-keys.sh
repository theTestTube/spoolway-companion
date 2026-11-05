# Machine-keys gate:
# no machine override in the tracked spoolway config.
#
# `spoolway sync` writes the machine's override values into the tracked .spoolway/config.toml.
# Committed, a lane cap or a price row would become every machine's setting. The machine-only keys
# are: agents.<profile>.concurrency, every [models] line (only the tracked `prompt_cache_ttl` is
# expected, so a price, `slots` or `context_window` row is RED) and, since an unattended run and
# its cost ceiling are chosen when the dispatcher starts, per machine:
#   unattended.enabled, unattended.max_output_tokens, unattended.max_cost_usd
# 0.15.0 retired dispatch.backend and housekeeping.price_max_age_days. [dispatch] keys are project
# values, not machine values, so the selector does not gate them; housekeeping.retention_days and
# housekeeping.archive_retention_days are tracked project values, not gated here.
#
# Checks:
#   machine-keys/shipped-defaults   those keys, read from the tracked file, are exactly the lines
#                                   of scripts/gates/machine-keys-expected.toml: a changed value,
#                                   an added key and a removed key are each RED
#   machine-keys/config             RED only: the tracked config is missing
#   machine-keys/expected           RED only: the expected values are missing
#
# The verdict depends only on the commit. The expected values are checked in; nothing here reads
# the installed spoolway binary, the machine's ~/.spoolway overrides or the repository history.
#
# A RED gate is fixed with `git checkout -- .spoolway/config.toml`,
# never by editing the expected values. They change in one case only: a controlled spoolway
# update that changes a shipped default changes machine-keys-expected.toml in the same pull
# request, read from that release's documentation at its tag.
#
# The reader (machine-keys.sed) is line-based, not a TOML parser: it flattens `[table]` +
# `key = value` into `table.key = value`, so dotted keys, quoted names and `[models."<glob>"]`
# tables are seen, and an inline table under `agents`, `dispatch` or `unattended` is reported whole. It runs
# under LC_ALL=C so the verdict does not move with the caller's locale. Known limit: a key
# written after a multi-line string that holds a `[...]` line is attributed to the wrong table.
# The printed command is the check itself.

MACHINE_KEYS_CONFIG=.spoolway/config.toml
MACHINE_KEYS_EXPECTED=scripts/gates/machine-keys-expected.toml
MACHINE_KEYS_FLATTEN=scripts/gates/machine-keys.sed
MACHINE_KEYS_SELECT='^(agents\.[^=]*concurrency |agents[^=]* = \{.*concurrency|models[. ]|unattended\.(enabled|max_output_tokens|max_cost_usd) |unattended = \{)'

gate_machine_keys() {
  local config=$GATES_ROOT/$MACHINE_KEYS_CONFIG expected=$GATES_ROOT/$MACHINE_KEYS_EXPECTED
  local tracked shipped delta actual verdict missing=0
  if [ ! -f "$config" ]; then
    gate_result machine-keys/config "test -f $MACHINE_KEYS_CONFIG" "tracked config present" "missing" RED
    missing=1
  fi
  if [ ! -f "$expected" ]; then
    gate_result machine-keys/expected "test -f $MACHINE_KEYS_EXPECTED" "expected values checked in" "missing" RED
    missing=1
  fi
  [ "$missing" -eq 0 ] || return 0

  tracked=$(LC_ALL=C sed -E -n -f "$GATES_DIR/machine-keys.sed" "$config" | { LC_ALL=C grep -E "$MACHINE_KEYS_SELECT" || true; } | LC_ALL=C sort)
  shipped=$({ LC_ALL=C grep -v -E '^[[:space:]]*(#|$)' "$expected" || true; } | LC_ALL=C sort)
  # comm -3: column 1 is only in the tracked file, column 2 (tab-indented) only in the expected.
  delta=$(LC_ALL=C comm -3 <(printf '%s\n' "$tracked") <(printf '%s\n' "$shipped") | sed -e 's/^\t/shipped: /' -e '/^shipped: /!s/^/tracked: /')
  if [ -z "$delta" ]; then
    actual="$(grep -c . <<<"$tracked" || true) machine-only keys, all as shipped"
    verdict=GREEN
  else
    actual="${delta//$'\n'/; }; restore it with: git checkout -- $MACHINE_KEYS_CONFIG"
    verdict=RED
  fi
  gate_result machine-keys/shipped-defaults \
    "export LC_ALL=C; comm -3 <(sed -E -n -f $MACHINE_KEYS_FLATTEN $MACHINE_KEYS_CONFIG | grep -E '$MACHINE_KEYS_SELECT' | sort) <(grep -v -E '^[[:space:]]*(#|\$)' $MACHINE_KEYS_EXPECTED | sort)" \
    "no line printed: every machine-only key as in $MACHINE_KEYS_EXPECTED" \
    "$actual" "$verdict"
}
