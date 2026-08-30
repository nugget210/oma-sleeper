[.events[]?] as $events |
if any($events[]; .status.type.state == "in") then "live"
elif any($events[]; .status.type.state == "pre" and
     ((.date | fromdateiso8601) * 1000 - $now) >= 0 and
     ((.date | fromdateiso8601) * 1000 - $now) <= 10800000) then "pregame"
else "idle" end
