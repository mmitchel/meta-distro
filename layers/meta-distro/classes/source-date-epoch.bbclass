# source-date-epoch.bbclass
#
# Enforce a minimum SOURCE_DATE_EPOCH for Python recipes to keep builds
# reproducible and avoid timestamps prior to Jan 1, 1980.
#
# Behavior:
# - Applies only to recipes whose PN starts with "python3"
# - If SOURCE_DATE_EPOCH is unset or older than 1980-01-01 (315532800),
#   it sets SOURCE_DATE_EPOCH to that minimum and exports it.
#
# Rationale:
# - Some Python tooling and archive formats do not handle pre-1980 timestamps
#   reliably. This ensures consistent, deterministic outputs.

python __anonymous () {
  pn = d.getVar("PN") or ""
  if pn.startswith("python3"):
    epoch_min = 315532800
    epoch_cur = d.getVar("SOURCE_DATE_EPOCH") or ""
    if not epoch_cur or int(epoch_cur) < epoch_min:
      d.setVar("SOURCE_DATE_EPOCH", str(epoch_min))
      d.setVarFlag("SOURCE_DATE_EPOCH", "export", "1")
}
