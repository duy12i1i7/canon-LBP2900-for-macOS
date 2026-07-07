#!/bin/bash
#
# Live per-page print progress for the Canon LBP2900 queue.
#
#   ./progress.sh            # watches the Canon_LBP2900 queue
#   ./progress.sh MyQueue    # watches another queue
#
# Shows "printed N / TOTAL pages" for the active job, updating once a second.
# The counter is driven by the driver's PAGE: reports, so it advances as each
# physical page actually comes out. Press Ctrl-C to stop.
#
QUEUE="${1:-Canon_LBP2900}"
T="$(mktemp)"
cat > "$T" <<IPP
{ OPERATION Get-Jobs
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri \$uri
  ATTR keyword which-jobs not-completed
  ATTR keyword requested-attributes job-id,job-name,job-impressions,job-media-sheets-completed
}
IPP
trap 'rm -f "$T"; echo; exit 0' INT TERM

echo "Watching queue: $QUEUE   (Ctrl-C to stop)"
while :; do
  o="$(ipptool -tv "ipp://localhost/printers/$QUEUE" "$T" 2>/dev/null)"
  id="$(echo "$o" | awk -F' = ' '/job-id \(integer\)/{print $2; exit}')"
  if [ -z "$id" ]; then
    printf '\r  idle — no active job                                  '
  else
    name="$(echo "$o" | awk -F' = ' '/job-name \(name/{print $2; exit}')"
    done="$(echo "$o" | awk -F' = ' '/job-media-sheets-completed \(integer\)/{print $2; exit}')"
    total="$(echo "$o" | awk -F' = ' '/job-impressions \(integer\)/{print $2; exit}')"
    printf '\r  job #%s "%s": printed %s%s pages          ' \
        "$id" "${name:-?}" "${done:-0}" "${total:+/$total}"
  fi
  sleep 1
done
