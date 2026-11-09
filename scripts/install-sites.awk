# Lists every write or delete site in install.sh: rm, rmdir, mv, cp, ln, install -m, a > or >> redirect
# to a quoted path, and tee -a. Prints "line<TAB>function<TAB>trimmed text". Used by check.sh herdr,
# which requires every site to be classified in scripts/install-writes.tsv.
/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $1; sub(/\(\).*/, "", fn) }
/^\}/ { fn = "main" }
/^[[:space:]]*#/ { next }
/(^|[^a-z_-])(rm|rmdir|mv|cp|ln)[[:space:]]+-?|(^|[^a-z_-])install -m|>>?[[:space:]]*"|tee -a/ {
  t = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t); print NR "\t" (fn ? fn : "main") "\t" t }
