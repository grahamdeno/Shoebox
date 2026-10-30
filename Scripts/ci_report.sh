#!/bin/sh
# Turns a build or test log into annotations that can be read through the GitHub checks API.
# Usage: ci_report.sh <log> <title>
log="$1"; title="$2"
enc() { sed 's/%/%25/g' | awk 'BEGIN{ORS="%0A"} {print}'; }
errs=$(grep -E "error:|✘|failed|Fatal error|Test .* failed|Issue recorded" "$log" | grep -v "^warning" | grep -v "CoreData: error" | sed -E 's#^.*/(Core|App|Share|IssueContent|Widgets|Tests)/#\1/#' | sort -u | head -60)
if [ -n "$errs" ]; then
  echo "::error title=$title::$(printf '%s\n' "$errs" | enc)"
fi
summary=$(grep -E "Test run with|Test Suite .* (passed|failed)|Executed|\*\* (BUILD|TEST) (SUCCEEDED|FAILED)|tests passed|passed after" "$log" | tail -5)
[ -n "$summary" ] && echo "::notice title=$title::$(printf '%s\n' "$summary" | enc)"
exit 0
