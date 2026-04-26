#!/usr/bin/env bats
load helper

setup() { require_built date; }

@test "date prints DDD Mon DD HH:MM:SS UTC YYYY" {
    out=$(applet date)
    [[ "$out" =~ ^(Sun|Mon|Tue|Wed|Thu|Fri|Sat)\ (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\ [\ 0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\ UTC\ [0-9]{4}$ ]]
}

@test "date year is reasonable (post-2024 sanity check)" {
    out=$(applet date)
    year=$(echo "$out" | awk '{print $NF}')
    [ "$year" -ge 2024 ]
    [ "$year" -lt 2100 ]
}
