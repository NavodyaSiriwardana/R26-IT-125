from datetime import date, datetime, timedelta, timezone
import re
from typing import Optional


_DURATION_PATTERN = re.compile(
    r"^\s*(?:(?P<hours>\d+)\s*h)?\s*(?:(?P<minutes>\d+)\s*m)?\s*$",
    re.IGNORECASE,
)


def get_today_iso() -> str:
    return date.today().isoformat()


def validate_iso_date(date_value: str) -> str:
    try:
        parsed_date = date.fromisoformat(date_value)
        return parsed_date.isoformat()
    except (TypeError, ValueError):
        raise ValueError("Date must be in YYYY-MM-DD format.")


def get_week_bounds(entry_date: str) -> tuple[str, str]:
    """
    Week starts on Monday and ends on Sunday.
    """

    parsed_date = date.fromisoformat(entry_date)

    week_start_date = parsed_date - timedelta(days=parsed_date.weekday())
    week_end_date = week_start_date + timedelta(days=6)

    return week_start_date.isoformat(), week_end_date.isoformat()


def parse_duration_minutes(duration: str) -> int:
    """Convert the diary app's Firestore duration string to whole minutes."""

    if not isinstance(duration, str):
        raise ValueError("Duration must be a string such as '2h' or '45m'.")

    if not duration.strip():
        return 0

    match = _DURATION_PATTERN.fullmatch(duration)
    if match is None or not any(match.groupdict().values()):
        raise ValueError("Duration must use hour/minute notation such as '1h 30m'.")

    hours = int(match.group("hours") or 0)
    minutes = int(match.group("minutes") or 0)
    return (hours * 60) + minutes


def get_current_week_bounds() -> tuple[str, str]:
    today = get_today_iso()
    return get_week_bounds(today)


def validate_week_range(
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
) -> tuple[str, str]:
    """Resolve and validate one complete Monday-to-Sunday week.

    Callers may omit both values to select the current week. Supplying only one
    boundary is rejected so an accidental partial range cannot silently select a
    different week.
    """

    if (week_start is None) != (week_end is None):
        raise ValueError("week_start and week_end must be provided together.")

    if week_start is None and week_end is None:
        return get_current_week_bounds()

    resolved_start = validate_iso_date(week_start)
    resolved_end = validate_iso_date(week_end)
    start_date = date.fromisoformat(resolved_start)
    end_date = date.fromisoformat(resolved_end)

    if start_date.weekday() != 0 or end_date.weekday() != 6:
        raise ValueError("Weeks must start on Monday and end on Sunday.")

    if end_date - start_date != timedelta(days=6):
        raise ValueError("week_start and week_end must describe the same seven-day week.")

    return resolved_start, resolved_end


def is_date_within_range(
    date_value: str,
    start_date: str,
    end_date: str,
) -> bool:
    current = date.fromisoformat(date_value)
    start = date.fromisoformat(start_date)
    end = date.fromisoformat(end_date)

    return start <= current <= end


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
