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
    startdate: datetime.date,
    timezone: zoneinfo.ZoneInfo,
    reminders: list[int],
    attendees: list[str],
    interval: int,
    max_days: int,
    output: Path,
):
    cal = Calendar()
    calname = f"days since {startdate.isoformat()}"
    cal.add("PRODID", "-//Google Inc//Google Calendar//EN")
    cal.add("VERSION", "2.0")
    cal.add("CALSCALE", "GREGORIAN")
    cal.add("X-WR-CALNAME", calname)
    cal.add("X-WR-TIMEZONE", timezone)

    # Google Calendar 似乎"强制"以 UTC 时间存储 DTSTART 和 DTEND
    # 转换为当地时间时使用全局的 X-WR-TIMEZONE
    utc = zoneinfo.ZoneInfo("UTC")
    for days in range(interval, max_days, interval):
        age = round(days / 365.25, 2)
        # 设定 DTSTART 为 当地时间 的 09:00
        localtime = datetime.datetime.combine(
            date=startdate + datetime.timedelta(days=days),
            time=datetime.time(9, 0),
            tzinfo=timezone,
        )
        # 将 localtime "强制"转换为 UTC 时间
        dtstart = localtime.replace(tzinfo=utc) - localtime.utcoffset()
        dtend = dtstart + datetime.timedelta(hours=1)
        summary = f"{days} days since {startdate.isoformat()} (age: {age})"

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

    if not output:
        output = Path(f"days_since_date.{startdate.isoformat()}.ics")

    with output.open("wb") as f:
        f.write(cal.to_ical())
    print(f"iCal file saved to {output}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate iCal events for days since date."
    )
    parser.add_argument(
        "startdate", type=str, help="Start date in the format YYYY-MM-DD."
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
        "-i",
        "--interval",
        type=int,
        default=1000,
        help="Interval in days to generate events (default: %(default)s).",
    )
    parser.add_argument(
        "-d",
        "--max-days",
        type=int,
        default=31000,
        help="Max days to generate events (default: %(default)s).",
    )
    parser.add_argument(
        "-o", "--output", type=Path, help="Path to save the generated iCal file."
    )

    args = parser.parse_args()

    try:
        startdate = datetime.datetime.strptime(args.startdate, "%Y-%m-%d").date()
    except ValueError:
        parser.error("Invalid date format. Use YYYY-MM-DD.")

    try:
        timezone = zoneinfo.ZoneInfo(args.timezone)
    except Exception:
        parser.error(f"Invalid timezone: {args.timezone}")

    days_since_date(
        startdate,
        timezone,
        args.reminders,
        args.attendees,
        args.interval,
        args.max_days,
        args.output,
    )


if __name__ == "__main__":
    main()
