#!/usr/bin/env python3
# apt install python3-icalendar

import argparse
import datetime
import zoneinfo
from pathlib import Path

from icalendar import (
    Alarm,
    Calendar,
    Event,
    vCalAddress,
    vDatetime,
    vText,
)


def days_since_date(
    date: datetime.date,
    output_file: Path,
    tz_name: str,
    reminders: list[int],
    attendees: list[str],
    max_days: int,
    interval: int,
):
    calname = "Days since date"
    timezone = zoneinfo.ZoneInfo(tz_name)
    cal = Calendar()
    cal.add("PRODID", "-//Google Inc//Google Calendar//EN")
    cal.add("VERSION", "2.0")
    cal.add("X-WR-CALNAME", calname)
    cal.add("X-WR-TIMEZONE", timezone)
    cal.add("X-WR-CALDESC", f"{calname} {date.isoformat()}")

    # Google Calendar 似乎 UTC 存储 dtstart 和 dtend
    now = datetime.datetime.now(timezone)
    utcoffset = int(now.utcoffset().seconds / 3600)
    for days in range(interval, max_days, interval):
        age = round(days / 365.25, 2)
        dtstart = datetime.datetime.combine(
            date + datetime.timedelta(days=days),
            datetime.time(9 + utcoffset, 0),
            tzinfo=zoneinfo.ZoneInfo("UTC"),
        )
        dtend = dtstart + datetime.timedelta(hours=1)
        summary = f"{days} days since {date.isoformat()} (age: {age})"

        event = Event()
        event.add("summary", summary)
        event.add("dtstart", vDatetime(dtstart))
        event.add("dtend", vDatetime(dtend))

        # 添加提醒
        for reminder_days in reminders:
            alarm = Alarm()
            trigger_time = datetime.timedelta(days=-reminder_days)
            alarm.add("action", "DISPLAY")
            alarm.add("description", f"Reminder: {summary}")
            alarm.add("trigger", trigger_time)
            event.add_component(alarm)

        # 添加与会者
        for attendee_email in attendees:
            attendee = vCalAddress(f"mailto:{attendee_email}")
            attendee.params["cn"] = vText(attendee_email.split("@")[0])
            attendee.params["role"] = vText("REQ-PARTICIPANT")
            event.add("attendee", attendee)

        cal.add_component(event)

    if not output_file:
        output_file = Path(f"days_since_date.{date.isoformat()}.ics")

    ical_data = cal.to_ical()
    with output_file.open("wb") as f:
        f.write(ical_data)
    print(f"iCal file saved to {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate iCal events for days since date."
    )
    parser.add_argument("date", type=str, help="Date in the format YYYY-MM-DD.")
    parser.add_argument(
        "-o", "--output", type=Path, help="Path to save the generated iCal file."
    )
    parser.add_argument(
        "-t",
        "--timezone",
        type=str,
        default="Asia/Shanghai",
        help="Timezone for the events (default: %(default)s).",
    )
    parser.add_argument(
        "-r",
        "--reminders",
        type=int,
        nargs="+",
        default=[1, 3, 7],
        help="Days before the event to set reminders (default: 1, 3, 7).",
    )
    parser.add_argument(
        "-a",
        "--attendees",
        type=str,
        nargs="+",
        default=[],
        help="Email addresses of attendees (default: none).",
    )
    parser.add_argument(
        "-d",
        "--max-days",
        type=int,
        default=31000,
        help="Max days to generate events (default: %(default)s).",
    )
    parser.add_argument(
        "-i",
        "--interval",
        type=int,
        default=1000,
        help="Interval in days to generate events (default: %(default)s).",
    )

    args = parser.parse_args()

    try:
        date = datetime.datetime.strptime(args.date, "%Y-%m-%d").date()
    except ValueError:
        parser.error("Invalid date format. Use YYYY-MM-DD.")

    try:
        zoneinfo.ZoneInfo(args.timezone)
    except Exception:
        parser.error(f"Invalid timezone: {args.timezone}")

    days_since_date(
        date,
        args.output,
        args.timezone,
        args.reminders,
        args.attendees,
        args.max_days,
        args.interval,
    )


if __name__ == "__main__":
    main()
