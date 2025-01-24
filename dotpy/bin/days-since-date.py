#!/usr/bin/env python3
# author: ak1ra
# date: 2025-01-24
# python3 -m pip install PyYAML icalendar lunar_python
# https://github.com/collective/icalendar
# https://github.com/6tail/lunar-python

import argparse
import datetime
import logging
import time
import zoneinfo
from pathlib import Path

import yaml
from icalendar import (
    Alarm,
    Calendar,
    Event,
    vCalAddress,
    vDatetime,
    vText,
)
from lunar_python import Lunar, LunarYear

logging.basicConfig(
    format="[%(asctime)s][%(name)s][%(levelname)s] %(message)s", level=logging.DEBUG
)
logger = logging.getLogger(__name__)


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


def add_days_event_to_calendar(
    calendar: Calendar,
    startdate: datetime.date,
    timezone: zoneinfo.ZoneInfo,
    event_time: datetime.time,
    event_duration: datetime.timedelta,
    reminders: list[int],
    attendees: list[str],
    username: str,
    days: int,
):
    age = round(days / 365.25, 2)
    startdate_utc = local_datetime_to_utc_datetime(startdate, event_time, timezone)
    dtstart = startdate_utc + datetime.timedelta(days=days)
    dtend = dtstart + event_duration
    summary = f"{username} 来到地球已经 {days} 天啦! (age: {age})"

    event = Event()
    event.add("summary", summary)
    event.add("dtstart", vDatetime(dtstart))
    event.add("dtend", vDatetime(dtend))
    add_reminders_to_event(event, reminders, summary)
    add_attendees_to_event(event, attendees)

    calendar.add_component(event)


def add_lunar_event_to_calendar(
    calendar: Calendar,
    startdate: datetime.date,
    timezone: zoneinfo.ZoneInfo,
    event_time: datetime.time,
    event_duration: datetime.timedelta,
    reminders: list[int],
    attendees: list[str],
    username: str,
    age: int,
):
    event_date = get_future_lunar_equivalent_date(startdate, age)
    dtstart = local_datetime_to_utc_datetime(event_date, event_time, timezone)
    dtend = dtstart + event_duration
    summary = f"{username} {event_date.year} 年农历生日快乐 (age: {age})"

    event = Event()
    event.add("summary", summary)
    event.add("dtstart", vDatetime(dtstart))
    event.add("dtend", vDatetime(dtend))
    add_reminders_to_event(event, reminders, summary)
    add_attendees_to_event(event, attendees)

    calendar.add_component(event)


def create_calendar(config: dict, output: Path):
    calendar_name = config.get("global").get("calendar_name")
    timezone_name = config.get("global").get("timezone")
    try:
        timezone = zoneinfo.ZoneInfo(timezone_name)
    except Exception:
        logger.error("Invalid timezone: %s", timezone_name)

    calendar = Calendar()
    calendar.add("PRODID", "-//Google Inc//Google Calendar//EN")
    calendar.add("VERSION", "2.0")
    calendar.add("CALSCALE", "GREGORIAN")
    calendar.add("X-WR-CALNAME", calendar_name)
    calendar.add("X-WR-TIMEZONE", timezone)

    for item in config.get("startdate_list"):
        username = item.get("username")
        startdate = item.get("startdate")

        birthday = item.get("birthday") or config.get("global").get("birthday")
        max_ages = item.get("max_ages") or config.get("global").get("max_ages")
        max_days = item.get("max_days") or config.get("global").get("max_days")
        interval = item.get("interval") or config.get("global").get("interval")
        reminders = item.get("reminders") or config.get("global").get("reminders")
        attendees = item.get("attendees") or config.get("global").get("attendees")

        event_time = datetime.datetime.strptime(
            item.get("event_time") or config.get("global").get("event_time"), "%H:%M:%S"
        ).time()
        event_duration = datetime.timedelta(
            hours=item.get("event_duration")
            or config.get("global").get("event_duration")
        )

        for days in range(interval, max_days + 1, interval):
            add_days_event_to_calendar(
                calendar=calendar,
                startdate=startdate,
                timezone=timezone,
                event_time=event_time,
                event_duration=event_duration,
                reminders=reminders,
                attendees=attendees,
                username=username,
                days=days,
            )

        if not birthday:
            continue
        for age in range(0, max_ages + 1):
            add_lunar_event_to_calendar(
                calendar=calendar,
                startdate=startdate,
                timezone=timezone,
                event_time=event_time,
                event_duration=event_duration,
                reminders=reminders,
                attendees=attendees,
                username=username,
                age=age,
            )

    if not output:
        output = Path(f"{calendar_name}.{startdate.isoformat()}.ics")

    with output.open("wb") as f:
        f.write(calendar.to_ical())
    logger.info("iCal file saved to %s", output)


def main():
    parser = argparse.ArgumentParser(
        description="Generate iCal events for days since date."
    )
    parser.add_argument("input", type=Path, help="input config.yaml")
    parser.add_argument(
        "-o", "--output", type=Path, help="Path to save the generated iCal file."
    )

    args = parser.parse_args()
    with open(args.input, "r") as f:
        config = yaml.safe_load(f)

    start = time.perf_counter()
    create_calendar(config, args.output)
    elapsed = time.perf_counter() - start
    logger.debug("iCal generation elapsed at %.6fs", elapsed)


if __name__ == "__main__":
    main()
