# Flattens a spoolway config.toml into one `table.key = value` line per assignment.
# Run by gates.d/machine-keys.sh as: LC_ALL=C sed -E -n -f scripts/gates/machine-keys.sed <file>
# Line-based, not a TOML parser: a multi-line string or array is read line by line.

s/\r$//
/^[[:space:]]*#/d
s/[[:space:]]+#.*$//
s/[[:space:]]+$//

# A table header: drop brackets, spaces and the quotes around plain names, and remember it.
/^[[:space:]]*\[/{
  s/[][[:space:]]//g
  s/["\x27]([A-Za-z0-9_-]+)["\x27]/\1/g
  h
  d
}

# An assignment: tidy the key (quotes around plain names, spaces around dots), then prefix the
# remembered table.
/=/{
  :quotes
  s/^([^=]*)["\x27]([A-Za-z0-9_-]+)["\x27]([^=]*=)/\1\2\3/
  t quotes
  :dots
  s/^([^=]*)[[:space:]]+\.([^=]*=)/\1.\2/
  t dots
  s/^([^=]*)\.[[:space:]]+([^=]*=)/\1.\2/
  t dots
  G
  s/^[[:space:]]*([^=]*[^=[:space:]])[[:space:]]*=[[:space:]]*(.*)\n(.*)$/\3.\1 = \2/
  s/^\.//
  p
}
