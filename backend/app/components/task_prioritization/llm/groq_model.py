import os

from dotenv import load_dotenv
from groq import Groq

load_dotenv()

MODEL_NAME = "openai/gpt-oss-120b"

GROQ_API_KEY = os.getenv("GROQ_API_KEY")

if not GROQ_API_KEY:
    raise ValueError(
        "GROQ_API_KEY is missing. Add it to your .env file."
    )

client = Groq(
    api_key=GROQ_API_KEY
)


def generate_scores(prompt: str) -> str:
    response = client.chat.completions.create(
        model=MODEL_NAME,
        messages=[
            {
                "role": "system",
                "content": (
                    "You are an expert university task prioritization assistant.\n"
                    "Your job is NOT to maximize scores.\n"
                    "Use the FULL range from 0.0 to 1.0.\n"
                    "Most normal tasks should fall between 0.1 and 0.8.\n"
                    "Values above 0.9 should be rare and reserved for very "
                    "important situations.\n"
                    "Return ONLY valid JSON."
                ),
            },
            {
                "role": "user",
                "content": prompt,
            },
        ],
        temperature=0.2,
        max_tokens=150,
    )

    return response.choices[0].message.content.strip()