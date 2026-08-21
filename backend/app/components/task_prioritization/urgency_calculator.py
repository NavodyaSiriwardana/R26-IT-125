def clamp01(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def calculate_temporal_urgency(
    deadline_hours: float,
    time_pressure: float,
) -> float:
    """
    Calculate temporal urgency using:

    1. Remaining hours until the deadline.
    2. Remaining time relative to required work duration.

    Lower deadline hours and lower time-pressure ratios
    produce higher urgency.
    """

    deadline_hours = max(float(deadline_hours), 0.0)
    time_pressure = max(float(time_pressure), 0.0)

    # Deadline proximity
    if deadline_hours <= 3:
        deadline_score = 1.00
    elif deadline_hours <= 12:
        deadline_score = 0.85
    elif deadline_hours <= 24:
        deadline_score = 0.70
    elif deadline_hours <= 72:
        deadline_score = 0.50
    elif deadline_hours <= 168:
        deadline_score = 0.30
    else:
        deadline_score = 0.15

    # Available time relative to required work
    if time_pressure <= 1:
        pressure_score = 1.00
    elif time_pressure <= 3:
        pressure_score = 0.80
    elif time_pressure <= 10:
        pressure_score = 0.55
    else:
        pressure_score = 0.25

    urgency = (
        0.60 * deadline_score
        + 0.40 * pressure_score
    )

    return round(clamp01(urgency), 4)