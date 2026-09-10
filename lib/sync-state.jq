# ESPN stamps kickoff times as "2026-09-10T00:20Z", omitting the seconds that
# fromdateiso8601 requires, so the seconds are restored before parsing and an
# unparseable stamp yields null rather than aborting the whole classification.
def kickoff_epoch:
  if type != "string" then null
  else (if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$") then sub("Z$"; ":00Z") else . end)
    | (try fromdateiso8601 catch null)
  end;
[.events[]?] as $events |
if any($events[]; .status.type.state == "in") then "live"
elif any($events[]; .status.type.state == "pre" and
     ((.date | kickoff_epoch) as $kickoff | $kickoff != null and
      ($kickoff * 1000 - $now) >= 0 and
      ($kickoff * 1000 - $now) <= 10800000)) then "pregame"
else "idle" end
