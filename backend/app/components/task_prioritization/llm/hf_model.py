from transformers import AutoTokenizer, AutoModelForCausalLM
import torch

MODEL_NAME = "Qwen/Qwen2.5-3B-Instruct"

print("Loading Hugging Face model...")

# Detect device
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Using device: {DEVICE}")

# Tokenizer
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

# Model
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32,
    device_map="auto"
)

model.eval()

print("Model loaded successfully.")


def generate_scores(prompt: str) -> str:
    """
    Generates a JSON response from the local Qwen model.
    """

    messages = [
        {
            "role": "system",
            "content": (
                "You are an expert university task prioritization assistant.\n"
                "Your job is NOT to maximize scores.\n"
                "Use the FULL range from 0.0 to 1.0.\n"
                "Most everyday tasks should receive low or moderate scores.\n"
                "Only exams, deadlines, emergencies and critical academic work "
                "should receive values close to 1.0.\n"
                "Return ONLY valid JSON."
            )
        },
        {
            "role": "user",
            "content": prompt
        }
    ]

    text = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True
    )

    print("\n========== FULL INPUT TO MODEL ==========\n")
    print(text)
    print("\n=========================================\n")

    inputs = tokenizer(
        text,
        return_tensors="pt"
    )

    # Move tensors to GPU/CPU
    inputs = {k: v.to(model.device) for k, v in inputs.items()}

    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=80,

            # Sampling
            do_sample=False,
            temperature=None,
            top_p=None,

            # Stop generation correctly
            eos_token_id=tokenizer.eos_token_id,
            pad_token_id=tokenizer.eos_token_id,

            # Avoid repetitive output
            repetition_penalty=1.1,
        )

    generated_tokens = outputs[0][inputs["input_ids"].shape[-1]:]

    response = tokenizer.decode(
        generated_tokens,
        skip_special_tokens=True
    ).strip()

    print("\n========== MODEL RAW RESPONSE ==========\n")
    print(response)
    print("\n========================================\n")

    return response