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
from lunar_python import Lunar, LunarYear


def get_future_lunar_equivalent_date(
    past_solar_date: datetime.date, age: int
) -> datetime.date:
    """
    Calculate the equivalent future solar date for a given past solar date and a target lunar year.
    """
    # 获取输入日期对应的农历
    past_solar_datetime = datetime.datetime.combine(
        past_solar_date, datetime.time(0, 0, 0)
    )
    # .fromDate 所接受的类型为 datetime.datetime, 实际上处理后会把 time 部分丢弃
    lunar = Lunar.fromDate(past_solar_datetime)
    year = past_solar_date.year + age
    lunar_year = LunarYear.fromYear(year)

    # 获取闰月
    leap_month = lunar_year.getLeapMonth()

    # 确定目标年份的农历月
    if lunar.getMonth() > 0:
        lunar_month = lunar_year.getMonth(lunar.getMonth())
    elif abs(lunar.getMonth()) == leap_month:
        lunar_month = lunar_year.getMonth(lunar.getMonth())
    else:
        lunar_month = lunar_year.getMonth(abs(lunar.getMonth()))

    # 确定农历日
    lunar_day = min(lunar.getDay(), lunar_month.getDayCount())

    # 创建目标年份的农历日期
    future_lunar = Lunar.fromYmd(year, lunar_month.getMonth(), lunar_day)

    # 转换为公历日期
    future_solar_date = datetime.datetime.strptime(
        future_lunar.getSolar().toYmd(), "%Y-%m-%d"
    ).date()
    return future_solar_date


def local_datetime_to_utc_datetime(
    local_date: datetime.date, local_time: datetime.time, timezone: zoneinfo.ZoneInfo
) -> datetime.datetime:
    local_datetime = datetime.datetime.combine(local_date, local_time, timezone)
    # 将 local_datetime "强制"转换为 UTC 时间
    utc = zoneinfo.ZoneInfo("UTC")
    utc_datetime = local_datetime.replace(tzinfo=utc) - local_datetime.utcoffset()

    return utc_datetime


def add_reminders_to_event(event: Event, reminders: list, summary: str):
    # 添加提醒
    for reminder_days in reminders:
        alarm = Alarm()
        trigger_time = datetime.timedelta(days=-reminder_days)
        alarm.add("action", "DISPLAY")
        alarm.add("description", f"Reminder: {summary}")
        alarm.add("trigger", trigger_time)
        event.add_component(alarm)


def add_attendees_to_event(event: Event, attendees: list):
    # 添加与会者
    for attendee_email in attendees:
        attendee = vCalAddress(f"mailto:{attendee_email}")
        attendee.params["cn"] = vText(attendee_email.split("@")[0])
        attendee.params["role"] = vText("REQ-PARTICIPANT")
        event.add("attendee", attendee)


def add_lunar_event_to_calendar(
    calendar: Calendar,
    startdate: datetime.date,
    timezone: zoneinfo.ZoneInfo,
    reminders: list[int],
    attendees: list[str],
    age: int,
):
    # 设定 DTSTART 为 当地时间 的 09:00
    event_time = datetime.time(hour=9, minute=0)
    # 设定 VEVENT 的时长为 1 小时
    event_duration = datetime.timedelta(hours=1)

    event_date = get_future_lunar_equivalent_date(startdate, age)
    dtstart = local_datetime_to_utc_datetime(event_date, event_time, timezone)
    dtend = dtstart + event_duration
    summary = f"{event_date.year} 年农历生日快乐"

    event = Event()
    event.add("summary", summary)
    event.add("dtstart", vDatetime(dtstart))
    event.add("dtend", vDatetime(dtend))
    add_reminders_to_event(event, reminders, summary)
    add_attendees_to_event(event, attendees)

    calendar.add_component(event)


def add_days_event_to_calendar(
    calendar: Calendar,
    startdate: datetime.date,
    timezone: zoneinfo.ZoneInfo,
    reminders: list[int],
    attendees: list[str],
    days: int,
):
    # 设定 DTSTART 为 当地时间 的 09:00
    event_time = datetime.time(hour=9, minute=0)
    # 设定 VEVENT 的时长为 1 小时
    event_duration = datetime.timedelta(hours=1)

    age = round(days / 365.25, 2)
    startdate_utc = local_datetime_to_utc_datetime(startdate, event_time, timezone)
    dtstart = startdate_utc + datetime.timedelta(days=days)
    dtend = dtstart + event_duration
    summary = f"{days} days since {startdate.isoformat()} (age: {age})"

    event = Event()
    event.add("summary", summary)
    event.add("dtstart", vDatetime(dtstart))
    event.add("dtend", vDatetime(dtend))
    add_reminders_to_event(event, reminders, summary)
    add_attendees_to_event(event, attendees)

    calendar.add_component(event)


def create_calendar(
    startdate: datetime.date,
    timezone: zoneinfo.ZoneInfo,
    reminders: list[int],
    attendees: list[str],
    interval: int,
    max_days: int,
    max_ages: int,
    output: Path,
):
    calendar = Calendar()
    calendar.add("PRODID", "-//Google Inc//Google Calendar//EN")
    calendar.add("VERSION", "2.0")
    calendar.add("CALSCALE", "GREGORIAN")
    calendar.add("X-WR-CALNAME", f"days since {startdate.isoformat()}")
    calendar.add("X-WR-TIMEZONE", timezone)

    for days in range(interval, max_days + 1, interval):
        add_days_event_to_calendar(
            calendar=calendar,
            startdate=startdate,
            timezone=timezone,
            reminders=reminders,
            attendees=attendees,
            days=days,
        )

    for age in range(0, max_ages + 1):
        add_lunar_event_to_calendar(
            calendar=calendar,
            startdate=startdate,
            timezone=timezone,
            reminders=reminders,
            attendees=attendees,
            age=age,
        )

    if not output:
        output = Path(f"calendar_for.{startdate.isoformat()}.ics")

    with output.open("wb") as f:
        f.write(calendar.to_ical())
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
        "--max-days",
        type=int,
        default=30000,
        help="Max days for days since events (default: %(default)s).",
    )
    parser.add_argument(
        "--max-ages",
        type=int,
        default=100,
        help="Max ages for lunar birthday events (default: %(default)s).",
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

    create_calendar(
        startdate,
        timezone,
        args.reminders,
        args.attendees,
        args.interval,
        args.max_days,
        args.max_ages,
        args.output,
    )


if __name__ == "__main__":
    main()
