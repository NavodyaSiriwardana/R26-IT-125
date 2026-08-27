import json

from app.components.task_prioritization.llm.groq_model import (
    client,
    MODEL_NAME,
)


REFLECTION_SYSTEM_PROMPT = """
You are a productivity reflection assistant for university students.

You receive verified productivity analytics calculated by the system.

Your job is to interpret those analytics and generate a concise daily
reflection.

IMPORTANT RULES:

1. Do not calculate or modify any numeric values.
2. Do not invent facts.
3. Use only the supplied analytics.
4. Do not claim a behavioural pattern unless the supplied data supports it.
5. Be realistic and constructive.
6. Avoid exaggerated praise or criticism.
7. Give practical recommendations for the next day.
8. Return ONLY valid JSON.
9. Prefer direct observations over speculative interpretations.
10. Do not treat a low count of negative behaviours as a strength unless the supplied analytics clearly support that conclusion.
11. Do not infer motivation, intention, or ability unless it is directly supported by the supplied data.
12. When priority adherence is low, explain it using unfinished Critical/High-priority work when the data supports that conclusion.
13. Avoid vague phrases such as "no adherence to priority".
14. Use natural, student-friendly language.
15. Do not say a task "had to be postponed"; simply state that it was postponed.
16. Never list the absence of a negative behaviour as a strength.
Examples such as "you did not postpone tasks" or
"you did not snooze difficult tasks" are NOT strengths.
17. If unfinished Critical or High-priority tasks are provided,
the tomorrow_focus should prioritize those tasks before lower-priority work,
unless the supplied data indicates they are not relevant tomorrow.
18. When a specific Critical/High task is provided, mention its title when useful.
19. Treat overdue tasks as more urgent than merely pending tasks.
20. If an overdue Critical or High-priority task exists,
the reflection should explicitly mention it.
21. The tomorrow_focus should prioritize overdue Critical/High tasks
before lower-priority pending work, unless the supplied data says
the task is no longer actionable.
22. Distinguish between on-time completion, late completion,
and tasks that are still overdue.
23. A task completed after its deadline is a completed task,
not an overdue pending task. You may mention that it was
completed late.
24. If completed_late is greater than 0, acknowledge that
the work was completed while accurately noting that some
completion occurred after the deadline.
25. If overdue_pending is greater than 0, treat those tasks
as unresolved and requiring attention.
26. Do not describe a completed-late task as still overdue.
27. If an overdue Critical or High-priority task remains
unfinished, prioritize it over lower-priority pending work
in the improvement and tomorrow-focus sections.

28. The strengths array must contain only positive actions
that the student actually performed.

29. If snoozes and postponements are both zero, you may
omit them completely. Do not describe their absence using
words such as "avoided", "successfully avoided", "maintained",
or "demonstrated".

30. Express completion rate and priority adherence as
percentages exactly as supplied. Do not display them as
decimal ratios.

31. Improvement items should be action-oriented. Avoid
repeating the summary without giving the student a practical
next step.

Return exactly this structure:

{
  "summary": "short overall reflection",
  "strengths": [
    "strength 1",
    "strength 2"
  ],
  "improvements": [
    "improvement 1",
    "improvement 2"
  ],
  "tomorrow_focus": "one practical recommendation"
}
"""

def _is_absence_only_strength(item: str) -> bool:
    """
    Detect statements that present the absence of undesirable
    behaviour as a positive action.
    """

    normalized = " ".join(
        item.strip().lower().split()
    )

    prohibited_patterns = (
        "no overdue",
        "without overdue",
        "avoided overdue",
        "did not become overdue",

        "no snooz",
        "without snooz",
        "avoided snooz",
        "did not snooze",

        "no postpon",
        "without postpon",
        "avoided postpon",
        "did not postpone",

        "no late complet",
        "without late complet",
    )

    return any(
        pattern in normalized
        for pattern in prohibited_patterns
    )


def generate_daily_reflection(data: dict) -> dict:

    completion_rate = data.get(
        "completion_rate",
        0,
    )

    completion_percentage = round(
        completion_rate * 100
    )

    priority_adherence = data.get(
        "priority_adherence",
        0,
    )

    priority_adherence_percentage = round(
        priority_adherence * 100
    )

    prompt = f"""
The following values are verified by the productivity analytics system.

Completion rate: 
{completion_percentage}%

Priority adherence:
{priority_adherence_percentage}%

Completed tasks:
{data.get("completed", 0)}

Pending tasks:
{data.get("pending", 0)}

Actionable pending tasks:
{data.get("actionable_pending", 0)}

Upcoming tasks:
{data.get("upcoming", 0)}

Tasks included in today's provisional score:
{data.get("scored_task_count", 0)}

Is the current score provisional:
{data.get("is_provisional", True)}

Snoozes:
{data.get("snoozes", 0)}

Postponements:
{data.get("postpones", 0)}

High-cognitive tasks postponed:
{data.get("high_cognitive_postponed", 0)}

Completed tasks by category:
{json.dumps(data.get("completed_by_category", {}))}

Pending tasks by category:
{json.dumps(data.get("pending_by_category", {}))}

High-priority tasks for tomorrow:
{data.get("tomorrow_high_priority_count", 0)}

High/Critical tasks today:
{data.get("high_priority_total", 0)}

High/Critical tasks completed:
{data.get("high_priority_completed", 0)}

Pending High/Critical tasks:
{data.get("pending_high_priority_count", 0)}

Pending High/Critical task details:
{json.dumps(data.get("pending_high_priority_tasks", []))}

Overdue tasks:
{data.get("overdue_task_count", 0)}

Overdue High/Critical tasks:
{data.get("overdue_high_priority_count", 0)}

Overdue task details:
{json.dumps(data.get("overdue_tasks", []))}

Overdue High/Critical task details:
{json.dumps(data.get("overdue_high_priority_tasks", []))}

Completed on time:
{data.get("completed_on_time", 0)}

Completed late:
{data.get("completed_late", 0)}

Currently overdue and incomplete:
{data.get("overdue_pending", 0)}

Generate the student's daily reflection.

Remember:
- The numbers are already calculated.
- Do not recalculate them.
- Do not invent behaviour.
- Keep the reflection concise.
- Return only valid JSON.
- If the reflection is provisional and actionable tasks remain,
  recommend the most relevant currently actionable work.
- Do not imply that an actionable task should wait until tomorrow
  merely because the word "tomorrow" appears in its title.
- Upcoming tasks are not currently actionable.
"""

    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {
                    "role": "system",
                    "content": REFLECTION_SYSTEM_PROMPT,
                },
                {
                    "role": "user",
                    "content": prompt,
                },
            ],

            # Use deterministic generation for analytics interpretation.
            temperature=0,

            # Provide sufficient space to finish the JSON object.
            max_tokens=1000,

            stream=False,

            # Do not mix model reasoning with the final JSON response.
            include_reasoning=False,

            # Enforce valid JSON output.
            response_format={
                "type": "json_object",
            },
        )

        choice = response.choices[0]

        print("\n========== GROQ REFLECTION DEBUG ==========")
        print("Model:", MODEL_NAME)
        print("Finish reason:", choice.finish_reason)
        print(
            "Raw content:",
            repr(choice.message.content),
        )
        print("===========================================\n")

        if choice.finish_reason == "length":
            raise ValueError(
                "The reflection response was truncated because "
                "the maximum output-token limit was reached."
            )

        raw_output = choice.message.content

        if not raw_output or not raw_output.strip():
            raise ValueError(
                "Groq returned empty reflection content."
            )

        try:
            result = json.loads(raw_output)
        except json.JSONDecodeError as error:
            print("Invalid JSON returned by Groq:")
            print(raw_output)

            raise ValueError(
                "Groq returned invalid reflection JSON."
            ) from error

        if not isinstance(result, dict):
            raise ValueError(
                "The reflection response must be a JSON object."
            )

        required_fields = {
            "summary",
            "strengths",
            "improvements",
            "tomorrow_focus",
        }

        missing_fields = required_fields.difference(
            result.keys()
        )

        if missing_fields:
            raise ValueError(
                "The reflection response is missing fields: "
                + ", ".join(sorted(missing_fields))
            )

        summary = result["summary"]
        strengths = result["strengths"]
        improvements = result["improvements"]
        tomorrow_focus = result["tomorrow_focus"]

        if not isinstance(summary, str):
            raise ValueError(
                "The reflection summary must be a string."
            )

        if not isinstance(strengths, list):
            raise ValueError(
                "The reflection strengths must be a list."
            )

        if not isinstance(improvements, list):
            raise ValueError(
                "The reflection improvements must be a list."
            )

        if not isinstance(tomorrow_focus, str):
            raise ValueError(
                "The tomorrow focus must be a string."
            )

        # Keep only valid, non-empty string items.
        cleaned_strengths = [
            item.strip()
            for item in strengths
            if isinstance(item, str) and item.strip()
        ]

        strengths = [
            item
            for item in cleaned_strengths
            if not _is_absence_only_strength(item)
        ]

        removed_strengths = [
            item
            for item in cleaned_strengths
            if _is_absence_only_strength(item)
        ]

        if removed_strengths:
            print(
                "Removed unsupported absence-only strengths:",
                removed_strengths,
            )

        improvements = [
            item.strip()
            for item in improvements
            if isinstance(item, str) and item.strip()
        ]

        return {
            "summary": summary.strip(),
            "strengths": strengths,
            "improvements": improvements,
            "tomorrow_focus": tomorrow_focus.strip(),
        }

    except Exception as error:
        print(
            "Reflection generation error:",
            f"{type(error).__name__}: {error}",
        )

        return {
            "summary":
                "Your productivity data was recorded successfully.",
            "strengths": [],
            "improvements": [],
            "tomorrow_focus":
                "Review your pending tasks and focus on your "
                "highest-priority work tomorrow.",
        }