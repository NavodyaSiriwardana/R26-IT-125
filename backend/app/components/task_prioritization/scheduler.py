from __future__ import annotations

from datetime import datetime, time, timedelta
from typing import Any

from ortools.sat.python import cp_model


def _parse_time(value: str) -> time:
    """Parse HH:mm."""
    return datetime.strptime(value, "%H:%M").time()


def _parse_iso_datetime(value: Any) -> datetime | None:
    """Safely parse Firestore/Flutter ISO datetime strings."""
    if value is None or str(value).strip() == "":
        return None

    try:
        parsed = datetime.fromisoformat(
            str(value).replace("Z", "+00:00")
        )

        if parsed.tzinfo is not None:
            parsed = parsed.astimezone().replace(tzinfo=None)

        return parsed
    except (ValueError, TypeError):
        return None


def _minutes_from_start(
    value: datetime,
    schedule_start: datetime,
) -> int:
    return int(
        (value - schedule_start).total_seconds() // 60
    )


def _round_up_minutes(value: datetime, interval: int = 10) -> datetime:
    """Round current time upward to the next interval."""
    discard = timedelta(
        minutes=value.minute % interval,
        seconds=value.second,
        microseconds=value.microsecond,
    )

    if discard == timedelta(0):
        return value

    return value + timedelta(minutes=interval) - discard

def calculate_break_minutes(
    duration: int,
    cognitive: float,
    energy: float,
) -> int:
    # Base recovery from task duration.
    if duration <= 30:
        base = 0
    elif duration <= 60:
        base = 5
    elif duration <= 90:
        base = 10
    elif duration <= 120:
        base = 15
    elif duration <= 180:
        base = 20
    else:
        base = 25

    # Cognitive recovery.
    if cognitive >= 0.8:
        base += 5
    elif cognitive >= 0.6:
        base += 2

    # Physical / energy recovery.
    if energy >= 0.9:
        base += 10
    elif energy >= 0.8:
        base += 5

    return max(0, min(base, 30))

def get_break_minutes(
    break_strategy: str,
    duration_minutes: int,
    cognitive_load: float,
    energy_level: float = 0.5,
) -> int:

    if break_strategy == "none":
        return 0

    if break_strategy == "fixed_5":
        return 5

    if break_strategy == "fixed_10":
        return 10

    if break_strategy == "fixed_15":
        return 15

    # Default = adaptive.
    return calculate_break_minutes(
        duration_minutes,
        cognitive_load,
        energy_level,
    )

def split_task_duration(
    total_minutes: int,
    maximum_part_minutes: int = 60,
) -> list[int]:
    """
    Split a duration into balanced parts of at most 60 minutes.

    Examples:
    120 -> [60, 60]
    150 -> [50, 50, 50]
    180 -> [60, 60, 60]
    75  -> [38, 37]
    """

    total_minutes = int(total_minutes)

    if total_minutes <= maximum_part_minutes:
        return [total_minutes]

    part_count = (
        total_minutes + maximum_part_minutes - 1
    ) // maximum_part_minutes

    base_duration = total_minutes // part_count
    remainder = total_minutes % part_count

    return [
        base_duration + (1 if index < remainder else 0)
        for index in range(part_count)
    ]


def generate_schedule(
    tasks: list[dict[str, Any]],
    schedule_date: str,
    available_start: str,
    available_end: str,
    break_strategy: str = "adaptive",
    planning_mode: str = "include_upcoming",

    # Internal options used for alternative generation.
    _protected_task_id: str | None = None,
    _include_alternative: bool = True,
) -> dict[str, Any]:
    """
    Generate a one-day priority-aware constraint schedule.

    planning_mode:
    - due_today_only
    - include_upcoming
    """

    planning_mode = planning_mode.strip().lower()

    if planning_mode == "today_only":
        planning_mode = "due_today_only"

    valid_planning_modes = {
        "due_today_only",
        "include_upcoming",
    }

    if planning_mode not in valid_planning_modes:
        raise ValueError(
            f"Unsupported planning mode: {planning_mode}"
        )

    selected_date = datetime.strptime(
        schedule_date,
        "%Y-%m-%d",
    ).date()

    requested_day_start = datetime.combine(
        selected_date,
        _parse_time(available_start),
    )

    day_end = datetime.combine(
        selected_date,
        _parse_time(available_end),
    )

    if day_end <= requested_day_start:
        raise ValueError(
            "Available end time must be later than start time."
        )

    now = datetime.now()

    # Never generate a new daily plan for a past date.
    if selected_date < now.date():
        raise ValueError(
            "A daily plan cannot be generated for a past date."
        )

    # When generating today's plan, do not schedule tasks in the past.
    if selected_date == now.date():
        rounded_now = _round_up_minutes(now, 10)
        day_start = max(requested_day_start, rounded_now)
    else:
        day_start = requested_day_start

    if day_start >= day_end:
        return {
            "schedule_date": schedule_date,
            "solver_status": "no_available_time",
            "planning_mode": planning_mode,
            "requested_available_start": requested_day_start.isoformat(),
            "effective_available_start": day_start.isoformat(),
            "available_end": day_end.isoformat(),
            "total_available_minutes": 0,
            "total_scheduled_minutes": 0,
            "total_break_minutes": 0,
            "remaining_free_minutes": 0,
            "utilization_percentage": 0.0,
            "workload_status": "Unavailable",
            "scheduled_task_count": 0,
            "unscheduled_task_count": 0,
            "not_considered_task_count": len(tasks),
            "scheduled_tasks": [],
            "unscheduled_tasks": [],
            "not_considered_tasks": [
                {
                    "_doc_id": str(
                        task.get("_doc_id")
                        or task.get("id")
                        or ""
                    ),
                    "title": task.get("title", "Untitled task"),
                    "reason": (
                        "The selected availability period has "
                        "already ended."
                    ),
                }
                for task in tasks
            ],
        }

    horizon = int(
        (day_end - day_start).total_seconds() // 60
    )

    

    model = cp_model.CpModel()

    task_variables: list[dict[str, Any]] = []
    unscheduled_tasks: list[dict[str, Any]] = []
    not_considered_tasks: list[dict[str, Any]] = []

    # ------------------------------------------------------------
    # Prepare task variables
    # ------------------------------------------------------------
    for index, task in enumerate(tasks):
        task_id = str(
            task.get("_doc_id")
            or task.get("id")
            or index
        )

        title = str(task.get("title", "Untitled task"))

        try:
            duration = int(
                task.get("estimated_duration_minutes", 60)
            )
        except (TypeError, ValueError):
            duration = 60

        if duration <= 0:
            unscheduled_tasks.append({
                "_doc_id": task_id,
                "title": title,
                "schedule_status": "unscheduled",
                "reason_code": "invalid_duration",
                "reason": "The estimated duration is invalid.",
            })
            continue

        available_from = _parse_iso_datetime(
            task.get("available_from")
        )

        deadline = _parse_iso_datetime(
            task.get("deadline")
        )

        is_fixed = bool(task.get("is_fixed", False))

        fixed_start = _parse_iso_datetime(
            task.get("fixed_start")
        )

        fixed_end = _parse_iso_datetime(
            task.get("fixed_end")
        )

        if is_fixed:
            if fixed_start is None or fixed_end is None:
                unscheduled_tasks.append({
                    "_doc_id": task_id,
                    "title": title,
                    "schedule_status": "unscheduled",
                    "reason_code": "invalid_fixed_event",
                    "reason": (
                        "The fixed event does not have a valid "
                        "start and end time."
                    ),
                })
                continue

            if fixed_end <= fixed_start:
                unscheduled_tasks.append({
                    "_doc_id": task_id,
                    "title": title,
                    "schedule_status": "unscheduled",
                    "reason_code": "invalid_fixed_event_range",
                    "reason": (
                        "The fixed event end time must be after "
                        "the start time."
                    ),
                })
                continue

            if fixed_start.date() != selected_date:
                not_considered_tasks.append({
                    "_doc_id": task_id,
                    "title": title,
                    "schedule_status": "not_considered",
                    "reason_code": "fixed_event_other_date",
                    "reason": (
                        "This fixed event takes place on "
                        f"{fixed_start.strftime('%b %d')}."
                    ),
                })
                continue

            if fixed_start < day_start or fixed_end > day_end:
                unscheduled_tasks.append({
                    "_doc_id": task_id,
                    "title": title,
                    "schedule_status": "unscheduled",
                    "reason_code": "fixed_event_outside_window",
                    "reason": (
                        "The fixed event falls outside the "
                        "selected planning window."
                    ),
                })
                continue

            duration = int(
                (fixed_end - fixed_start).total_seconds() // 60
            )

            fixed_start_minutes = _minutes_from_start(
                fixed_start,
                day_start,
            )

            fixed_end_minutes = _minutes_from_start(
                fixed_end,
                day_start,
            )

            is_scheduled = model.new_bool_var(
                f"is_scheduled_{index}"
            )

            start = model.new_int_var(
                fixed_start_minutes,
                fixed_start_minutes,
                f"start_{index}",
            )

            end = model.new_int_var(
                fixed_end_minutes,
                fixed_end_minutes,
                f"end_{index}",
            )

            # Fixed events must be placed in their exact slot.
            model.add(is_scheduled == 1)

            task_variables.append({
                "task": task,
                "task_id": task_id,
                "title": title,
                "duration": duration,
                "start": start,
                "end": end,
                "is_scheduled": is_scheduled,
                "index": index,
                "is_fixed": True,
                "fixed_start_dt": fixed_start,
                "fixed_end_dt": fixed_end,
                "is_splittable": False,
                "part_number": 1,
                "part_count": 1,
                "original_duration": duration,
                "reward_owner": True,
            })

            continue

        # Task becomes available after the selected day.
        if (
            available_from is not None
            and available_from.date() > selected_date
        ):
            not_considered_tasks.append({
                "_doc_id": task_id,
                "title": title,
                "schedule_status": "not_considered",
                "reason_code": "available_on_future_date",
                "reason": (
                    "This task becomes available on "
                    f"{available_from.strftime('%b %d')}."
                ),
            })
            continue

        # Deadline already passed before the planning window.
        if deadline is not None and deadline <= day_start:
            unscheduled_tasks.append({
                "_doc_id": task_id,
                "title": title,
                "schedule_status": "unscheduled",
                "reason_code": "deadline_passed",
                "reason": (
                    "The deadline passed before the available "
                    "planning period."
                ),
            })
            continue

        # Only include tasks due on the selected date in this mode.
        if (
            planning_mode == "due_today_only"
            and deadline is not None
            and deadline.date() != selected_date
        ):
            not_considered_tasks.append({
                "_doc_id": task_id,
                "title": title,
                "schedule_status": "not_considered",
                "reason_code": "not_due_selected_date",
                "reason": (
                    "This task is due on "
                    f"{deadline.strftime('%b %d')}, not on the "
                    "selected date."
                ),
            })
            continue

        earliest_start = 0

        if available_from is not None:
            earliest_start = max(
                0,
                _minutes_from_start(
                    available_from,
                    day_start,
                ),
            )

        if earliest_start >= horizon:
            not_considered_tasks.append({
                "_doc_id": task_id,
                "title": title,
                "schedule_status": "not_considered",
                "reason_code": "available_after_window",
                "reason": (
                    "This task becomes available after the "
                    "selected planning window."
                ),
            })
            continue

        latest_end = horizon

        if deadline is not None:
            latest_end = min(
                horizon,
                _minutes_from_start(
                    deadline,
                    day_start,
                ),
            )

        if latest_end <= 0:
            unscheduled_tasks.append({
                "_doc_id": task_id,
                "title": title,
                "schedule_status": "unscheduled",
                "reason_code": "deadline_before_window",
                "reason": (
                    "The task deadline is before the selected "
                    "planning window."
                ),
            })
            continue

        available_minutes_before_deadline = (
            latest_end - earliest_start
        )

        if duration > available_minutes_before_deadline:
            unscheduled_tasks.append({
                "_doc_id": task_id,
                "title": title,
                "schedule_status": "unscheduled",
                "reason_code": "insufficient_time_before_deadline",
                "reason": (
                    f"Requires {duration} minutes, but only "
                    f"{max(0, available_minutes_before_deadline)} "
                    "minutes are available before the deadline."
                ),
            })
            continue

        is_splittable = bool(
            task.get("is_splittable", False)
        )

        if is_splittable:
            part_durations = split_task_duration(duration)
        else:
            part_durations = [duration]

        # All parts share one decision variable. Therefore, either
        # every part is scheduled or none of them is scheduled.
        parent_is_scheduled = model.new_bool_var(
            f"is_scheduled_{index}"
        )

        if (
            _protected_task_id is not None
            and task_id == str(_protected_task_id)
        ):
            model.add(parent_is_scheduled == 1)

        part_count = len(part_durations)

        for part_index, part_duration in enumerate(
            part_durations
        ):
            part_number = part_index + 1
            latest_start = latest_end - part_duration

            start = model.new_int_var(
                earliest_start,
                latest_start,
                f"start_{index}_part_{part_number}",
            )

            end = model.new_int_var(
                earliest_start + part_duration,
                latest_end,
                f"end_{index}_part_{part_number}",
            )

            model.add(
                end == start + part_duration
            ).only_enforce_if(parent_is_scheduled)

            model.add(
                start == earliest_start
            ).only_enforce_if(
                parent_is_scheduled.Not()
            )

            model.add(
                end == earliest_start + part_duration
            ).only_enforce_if(
                parent_is_scheduled.Not()
            )

            task_variables.append({
                "task": task,
                "task_id": task_id,
                "title": title,
                "duration": part_duration,
                "original_duration": duration,
                "start": start,
                "end": end,
                "is_scheduled": parent_is_scheduled,
                "index": f"{index}_{part_number}",
                "parent_index": index,
                "is_fixed": False,
                "is_splittable": is_splittable,
                "part_number": part_number,
                "part_count": part_count,

                # Only the first part receives the task-ranking
                # reward. This prevents split tasks from receiving
                # an unfair reward for every generated part.
                "reward_owner": part_number == 1,
            })

    # ------------------------------------------------------------
    # Pairwise non-overlap and breaks
    # ------------------------------------------------------------
    for i in range(len(task_variables)):
        for j in range(i + 1, len(task_variables)):
            first = task_variables[i]
            second = task_variables[j]

            first_before_second = model.new_bool_var(
                f"task_{i}_before_{j}"
            )

            second_before_first = model.new_bool_var(
                f"task_{j}_before_{i}"
            )

            model.add(
                first_before_second + second_before_first == 1
            ).only_enforce_if([
                first["is_scheduled"],
                second["is_scheduled"],
            ])

            same_split_task = (
                first["task_id"] == second["task_id"]
                and first.get("part_count", 1) > 1
            )

            if same_split_task:
                if (
                    first.get("part_number", 1)
                    < second.get("part_number", 1)
                ):
                    model.add(
                        first_before_second == 1
                    ).only_enforce_if([
                        first["is_scheduled"],
                        second["is_scheduled"],
                    ])
                else:
                    model.add(
                        second_before_first == 1
                    ).only_enforce_if([
                        first["is_scheduled"],
                        second["is_scheduled"],
                    ])

            model.add(
                first_before_second == 0
            ).only_enforce_if(first["is_scheduled"].Not())

            model.add(
                second_before_first == 0
            ).only_enforce_if(first["is_scheduled"].Not())

            model.add(
                first_before_second == 0
            ).only_enforce_if(second["is_scheduled"].Not())

            model.add(
                second_before_first == 0
            ).only_enforce_if(second["is_scheduled"].Not())

            first_break = (
                0
                if first.get("is_fixed", False)
                else get_break_minutes(
                    break_strategy,
                    first["duration"],
                    float(
                        first["task"].get("cognitive_load", 0.5)
                    ),
                    float(
                        first["task"].get("energy_level", 0.5)
                    ),
                )
            )

            model.add(
                first["end"] + first_break <= second["start"]
            ).only_enforce_if(first_before_second)

            second_break = (
                0
                if second.get("is_fixed", False)
                else get_break_minutes(
                    break_strategy,
                    second["duration"],
                    float(
                        second["task"].get("cognitive_load", 0.5)
                    ),
                    float(
                        second["task"].get("energy_level", 0.5)
                    ),
                )
            )

            model.add(
                second["end"] + second_break <= first["start"]
            ).only_enforce_if(second_before_first)

    # ------------------------------------------------------------
    # Objective
    # ------------------------------------------------------------
    objective_terms = []

    # Priority levels are optimized lexicographically:
    # one Critical task outweighs all lower-priority tasks combined,
    # and one High task outweighs all Medium/Low tasks combined.
    priority_levels = {
        "Low": 0,
        "Medium": 1,
        "High": 2,
        "Critical": 3,
    }

    candidate_count = max(
        1,
        len({
            item["task_id"]
            for item in task_variables
        }),
    )
    priority_base = candidate_count + 1
    

    for item in task_variables:
        task = item["task"]

        try:
            normalized_score = int(
                task.get("normalized_score", 50)
            )
        except (TypeError, ValueError):
            normalized_score = 50

        normalized_score = max(
            0,
            min(100, normalized_score),
        )

        try:
            pred_score = float(
                task.get("pred_score", 0.0)
            )
        except (TypeError, ValueError):
            pred_score = 0.0

        priority_name = str(
            task.get("priority", "Medium")
        ).strip().title()

        priority_level = priority_levels.get(
            priority_name,
            1,
        )

        # Because priority_base is greater than the total number of
        # candidate tasks:
        #
        # - one Critical task outweighs all High/Medium/Low tasks;
        # - one High task outweighs all Medium/Low tasks;
        # - one Medium task outweighs all Low tasks.
        #
        # normalized_score differentiates tasks within the same level.
        priority_reward = (
            (priority_base ** priority_level) * 1_000_000
            + normalized_score * 1_000
            + int(max(pred_score, 0.0) * 100)
        )

        if item.get("reward_owner", True):
            objective_terms.append(
                priority_reward * item["is_scheduled"]
            )

        active_start = model.new_int_var(
            0,
            horizon,
            f"active_start_{item['index']}",
        )

        model.add(
            active_start == item["start"]
        ).only_enforce_if(item["is_scheduled"])

        model.add(
            active_start == 0
        ).only_enforce_if(item["is_scheduled"].Not())

        # Higher-ranked tasks receive a larger penalty for starting late.
        early_weight = max(
            1,
            normalized_score // 5,
        )

        objective_terms.append(
            -early_weight * active_start
        )

        active_end = model.new_int_var(
            0,
            horizon,
            f"active_end_{item['index']}",
        )

        model.add(
            active_end == item["end"]
        ).only_enforce_if(item["is_scheduled"])

        model.add(
            active_end == 0
        ).only_enforce_if(item["is_scheduled"].Not())

        # Small preference for compact schedules.
        objective_terms.append(-active_end)

    if objective_terms:
        model.maximize(sum(objective_terms))

    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = 10.0
    solver.parameters.num_search_workers = 8

    status = solver.solve(model)

    valid_statuses = {
        cp_model.OPTIMAL,
        cp_model.FEASIBLE,
    }

    if status not in valid_statuses:
        overlapping_fixed_ids = set()

        fixed_items = [
            item
            for item in task_variables
            if item.get("is_fixed", False)
        ]

        for i in range(len(fixed_items)):
            for j in range(i + 1, len(fixed_items)):
                first = fixed_items[i]
                second = fixed_items[j]

                overlaps = (
                    first["fixed_start_dt"] < second["fixed_end_dt"]
                    and second["fixed_start_dt"] < first["fixed_end_dt"]
                )

                if overlaps:
                    overlapping_fixed_ids.add(first["task_id"])
                    overlapping_fixed_ids.add(second["task_id"])

        model_unscheduled_ids: set[str] = set()

        for item in task_variables:
            task_id = item["task_id"]

            if task_id in model_unscheduled_ids:
                continue

            model_unscheduled_ids.add(task_id)

            if task_id in overlapping_fixed_ids:
                reason_code = "overlapping_fixed_events"
                reason = (
                    "This fixed event overlaps another mandatory "
                    "fixed event."
                )
            else:
                is_split = item.get("part_count", 1) > 1

                if is_split:
                    reason_code = "split_task_could_not_fit"
                    reason = (
                        "All required parts of this splittable task "
                        "could not fit within its availability, "
                        "deadline, break, and planning constraints."
                    )
                else:
                    reason_code = "capacity_conflict"
                    reason = (
                        "This task could not be included after the scheduler "
                        "selected the strongest feasible combination of tasks "
                        "within the available planning time."
                    )

            unscheduled_tasks.append({
                "_doc_id": task_id,
                "title": item["title"],
                "schedule_status": "unscheduled",
                "reason_code": reason_code,
                "reason": reason,
            })

            unscheduled_tasks.append({
                "_doc_id": item["task_id"],
                "title": item["title"],
                "schedule_status": "unscheduled",
                "reason_code": reason_code,
                "reason": reason,
            })

        return {
            "schedule_date": schedule_date,
            "solver_status": solver.status_name(status),
            "planning_mode": planning_mode,
            "requested_available_start": (
                requested_day_start.isoformat()
            ),
            "effective_available_start": day_start.isoformat(),
            "available_end": day_end.isoformat(),
            "break_strategy": break_strategy,
            "total_available_minutes": horizon,
            "total_scheduled_minutes": 0,
            "total_break_minutes": 0,
            "total_used_minutes": 0,
            "remaining_free_minutes": horizon,
            "utilization_percentage": 0.0,
            "workload_status": "Light",
            "scheduled_task_count": 0,
            "unscheduled_task_count": len(unscheduled_tasks),
            "not_considered_task_count": len(
                not_considered_tasks
            ),
            "scheduled_tasks": [],
            "unscheduled_tasks": unscheduled_tasks,
            "not_considered_tasks": not_considered_tasks,
        }


    scheduled_tasks: list[dict[str, Any]] = []
    model_unscheduled_ids: set[str] = set()

    for item in task_variables:
        if solver.value(item["is_scheduled"]) == 1:
            start_minutes = solver.value(item["start"])
            end_minutes = solver.value(item["end"])

            scheduled_start = day_start + timedelta(
                minutes=start_minutes
            )

            scheduled_end = day_start + timedelta(
                minutes=end_minutes
            )

            task = item["task"]

            scheduled_tasks.append({
                "_doc_id": item["task_id"],
                "title": item["title"],
                "scheduled_start": scheduled_start.isoformat(),
                "scheduled_end": scheduled_end.isoformat(),
                "estimated_duration_minutes": item["duration"],
                "priority": task.get("priority", "Medium"),
                "pred_score": task.get("pred_score", 0.0),
                "normalized_score": task.get(
                    "normalized_score",
                    50,
                ),
                "is_fixed": bool(task.get("is_fixed", False)),
                "schedule_status": "scheduled",

                "is_splittable": item.get(
                    "is_splittable",
                    False,
                ),
                "part_number": item.get("part_number", 1),
                "part_count": item.get("part_count", 1),
                "original_duration_minutes": item.get(
                    "original_duration",
                    item["duration"],
                ),
            })
        else:
            task_id = item["task_id"]

            # Multiple parts share the same original task ID.
            # Report the parent task only once.
            if task_id in model_unscheduled_ids:
                continue

            model_unscheduled_ids.add(task_id)

            is_split_task = item.get("part_count", 1) > 1

            if is_split_task:
                reason_code = "split_task_could_not_fit"
                reason = (
                    "All required parts of this splittable task "
                    "could not fit within its availability, "
                    "deadline, break, and planning constraints."
                )
            else:
                reason_code = "capacity_conflict"
                reason = (
                    "This task could not be included after the scheduler "
                    "selected the strongest feasible combination of tasks "
                    "within the available planning time."
                )              

            unscheduled_tasks.append({
                "_doc_id": task_id,
                "title": item["title"],
                "schedule_status": "unscheduled",
                "reason_code": reason_code,
                "reason": reason,
            })

    scheduled_tasks.sort(
        key=lambda item: item["scheduled_start"]
    )

    total_scheduled_minutes = sum(
        int(item["estimated_duration_minutes"])
        for item in scheduled_tasks
    )

    total_break_minutes = 0

    for i in range(len(scheduled_tasks)):
        current_task = scheduled_tasks[i]

        # The final task does not require a break after it.
        if i == len(scheduled_tasks) - 1:
            current_task["break_after_minutes"] = 0
            continue

        next_task = scheduled_tasks[i + 1]

        current_end = datetime.fromisoformat(
            current_task["scheduled_end"]
        )

        next_start = datetime.fromisoformat(
            next_task["scheduled_start"]
        )

        gap = int(
            (next_start - current_end).total_seconds() // 60
        )

        if current_task.get("is_fixed", False):
            expected_break = 0
        else:
            source_task = next(
                item["task"]
                for item in task_variables
                if item["task_id"] == current_task["_doc_id"]
            )

            expected_break = get_break_minutes(
                break_strategy,
                int(current_task["estimated_duration_minutes"]),
                float(source_task.get("cognitive_load", 0.5)),
                float(source_task.get("energy_level", 0.5)),
            )

        actual_break = min(
            max(0, gap),
            expected_break,
        )

        current_task["break_after_minutes"] = actual_break
        total_break_minutes += actual_break


    # Calculate this after the loop.
    # This works with zero, one, or many scheduled tasks.
    total_used_minutes = (
        total_scheduled_minutes + total_break_minutes
    )

    remaining_free_minutes = max(
        0,
        horizon - total_used_minutes,
    )

    utilization_percentage = round(
        (
            total_used_minutes / horizon * 100
            if horizon > 0
            else 0
        ),
        1,
    )

    if utilization_percentage < 40:
        workload_status = "Light"
    elif utilization_percentage < 75:
        workload_status = "Balanced"
    elif utilization_percentage <= 95:
        workload_status = "Heavy"
    else:
        workload_status = "Overloaded"

    scheduled_original_task_ids = {
        item["_doc_id"]
        for item in scheduled_tasks
    }

    result = {
        "schedule_date": schedule_date,
        "solver_status": (
            "optimal"
            if status == cp_model.OPTIMAL
            else "feasible"
        ),
        "planning_mode": planning_mode,
        "requested_available_start": (
            requested_day_start.isoformat()
        ),
        "effective_available_start": day_start.isoformat(),
        "available_end": day_end.isoformat(),
        "break_strategy": break_strategy,
        "total_available_minutes": horizon,
        "total_scheduled_minutes": total_scheduled_minutes,
        "total_break_minutes": total_break_minutes,
        "total_used_minutes": total_used_minutes,
        "remaining_free_minutes": remaining_free_minutes,
        "utilization_percentage": utilization_percentage,
        "workload_status": workload_status,
        "scheduled_task_count": len(
            scheduled_original_task_ids
        ),
        "scheduled_part_count": len(scheduled_tasks),
        "unscheduled_task_count": len(unscheduled_tasks),
        "not_considered_task_count": len(
            not_considered_tasks
        ),
        "scheduled_tasks": scheduled_tasks,
        "unscheduled_tasks": unscheduled_tasks,
        "not_considered_tasks": not_considered_tasks,
    }

    if _include_alternative:
        result["deadline_focused_alternative"] = (
            _generate_deadline_focused_alternative(
                tasks=tasks,
                base_result=result,
                schedule_date=schedule_date,
                available_start=available_start,
                available_end=available_end,
                break_strategy=break_strategy,
                planning_mode=planning_mode,
            )
        )

    return result

def _generate_deadline_focused_alternative(
    tasks: list[dict[str, Any]],
    base_result: dict[str, Any],
    schedule_date: str,
    available_start: str,
    available_end: str,
    break_strategy: str,
    planning_mode: str,
) -> dict[str, Any] | None:
    """
    Generate one alternative that protects an unscheduled
    deadline-sensitive task.

    Model scores and priorities are never modified.
    """

    eligible_reason_codes = {
        "capacity_conflict",
        "split_task_could_not_fit",
    }

    eligible_unscheduled = [
        item
        for item in base_result.get(
            "unscheduled_tasks",
            [],
        )
        if item.get("reason_code")
        in eligible_reason_codes
    ]

    if not eligible_unscheduled:
        return None

    task_by_id = {
        str(
            task.get("_doc_id")
            or task.get("id")
            or index
        ): task
        for index, task in enumerate(tasks)
    }

    selected_date = datetime.strptime(
        schedule_date,
        "%Y-%m-%d",
    ).date()

    effective_start = _parse_iso_datetime(
        base_result.get("effective_available_start")
    )

    candidate_tasks = []

    for unscheduled_item in eligible_unscheduled:
        task_id = str(
            unscheduled_item.get("_doc_id", "")
        )

        source_task = task_by_id.get(task_id)

        if source_task is None:
            continue

        priority = str(
            source_task.get("priority", "Low")
        ).strip().lower()

        try:
            normalized_score = float(
                source_task.get(
                    "normalized_score",
                    0,
                )
            )
        except (TypeError, ValueError):
            normalized_score = 0.0

        # Keep alternatives aligned with the priority model.
        # Critical, High and Medium tasks are eligible.
        # Low-priority tasks require a meaningful ranking score.
        if (
            priority not in {
                "critical",
                "high",
                "medium",
            }
            and normalized_score < 50
        ):
            continue

        deadline = _parse_iso_datetime(
            source_task.get("deadline")
        )

        # An alternative requires a real deadline on the
        # selected planning date.
        if deadline is None:
            continue

        if deadline.date() != selected_date:
            continue

        if (
            effective_start is not None
            and deadline <= effective_start
        ):
            continue

        candidate_tasks.append({
            "task_id": task_id,
            "task": source_task,
            "deadline": deadline,
            "normalized_score": normalized_score,
        })

        candidate_tasks.append({
            "task_id": task_id,
            "task": source_task,
            "deadline": deadline,
            "normalized_score": normalized_score,
        })

    if not candidate_tasks:
        return None

    # Protect the earliest unresolved deadline first.
    # Score resolves equal-deadline cases.
    candidate_tasks.sort(
        key=lambda item: (
            item["deadline"],
            -item["normalized_score"],
        )
    )

    candidate = candidate_tasks[0]

    protected_task_id = candidate["task_id"]
    protected_task = candidate["task"]

    alternative = generate_schedule(
        tasks=tasks,
        schedule_date=schedule_date,
        available_start=available_start,
        available_end=available_end,
        break_strategy=break_strategy,
        planning_mode=planning_mode,
        _protected_task_id=protected_task_id,
        _include_alternative=False,
    )

    alternative_scheduled_ids = {
        str(item.get("_doc_id", ""))
        for item in alternative.get(
            "scheduled_tasks",
            [],
        )
    }

    # The protected task must actually appear in the alternative.
    if protected_task_id not in alternative_scheduled_ids:
        return None

    recommended_scheduled_ids = {
        str(item.get("_doc_id", ""))
        for item in base_result.get(
            "scheduled_tasks",
            [],
        )
    }

    # Do not return an identical schedule.
    if (
        alternative_scheduled_ids
        == recommended_scheduled_ids
    ):
        return None

    removed_ids = (
        recommended_scheduled_ids
        - alternative_scheduled_ids
    )

    added_ids = (
        alternative_scheduled_ids
        - recommended_scheduled_ids
    )

    removed_tasks = [
        {
            "_doc_id": task_id,
            "title": str(
                task_by_id.get(
                    task_id,
                    {},
                ).get(
                    "title",
                    "Untitled task",
                )
            ),
        }
        for task_id in removed_ids
    ]

    added_tasks = [
        {
            "_doc_id": task_id,
            "title": str(
                task_by_id.get(
                    task_id,
                    {},
                ).get(
                    "title",
                    "Untitled task",
                )
            ),
        }
        for task_id in added_ids
    ]

    protected_title = str(
        protected_task.get(
            "title",
            "Untitled task",
        )
    )

    if removed_tasks:
        removed_titles = ", ".join(
            item["title"]
            for item in removed_tasks
        )

        tradeoff_message = (
            f'Protects the deadline for "{protected_title}", '
            f"but removes {removed_titles} from this plan."
        )
    else:
        tradeoff_message = (
            f'Protects the deadline for "{protected_title}".'
        )

    # Add metadata without changing the normal schedule fields.
    alternative["protected_task_id"] = protected_task_id
    alternative["protected_task_title"] = protected_title
    alternative["protected_deadline"] = (
        candidate["deadline"].isoformat()
    )
    alternative["removed_tasks"] = removed_tasks
    alternative["added_tasks"] = added_tasks
    alternative["tradeoff_message"] = tradeoff_message

    return alternative