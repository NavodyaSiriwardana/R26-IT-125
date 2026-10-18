# Mood Reset study protocol (draft)

A short protocol for collecting evidence that the Mood Reset helps, and that the
facial stress score means something. Adjust it to what your supervisor and the
faculty require. This project has not claimed ethics approval; check whether your
faculty needs one before recruiting.

## Questions
1. **Validity.** Does the facial stress score track how stressed participants say they feel?
2. **Effect.** After a guided breathing reset, does stress fall more than after the same
   time spent resting quietly (the control)?

## Participants
- 15 to 30 university students, volunteers, aged 18 or over.
- Each person uses the app on a laptop with a working webcam, in reasonable light.

## Procedure (about 15 minutes per person)
1. Participant signs in with a coded ID (for example `P01`), not their name.
2. In the app: Profile > turn on **Research study mode**. The consent screen appears; the
   participant reads it and ticks both boxes.
3. Run **4 Mood Resets** in one sitting, at least 3 minutes apart. The app assigns the
   condition itself: breathing and quiet rest, balanced, in random order. Do not tell the
   participant which is the "real" one.
4. For each reset the app records: self-rating before (1-5), facial stress before,
   self-rating after (1-5, asked before the result is shown), facial stress after.
5. Optionally ask the participant to complete the SUS usability questionnaire at the end.

Keep lighting, seating and distance to the webcam the same within a session.

## Collecting and exporting
```
cd backend
python -m app.components.self_bias_identification.evaluation.export_study_data ^
    --out study_resets.csv --salt "<a secret string you keep>"
python app/components/self_bias_identification/evaluation/analyze_reset_study.py study_resets.csv
```
Only participants who consented **and** switched study mode on are exported, with
their IDs replaced by a salted hash. Keep the salt private.

## What the analysis reports
- Spearman correlation between facial stress and self-rated stress (validity).
- Change in facial stress and in self-rated stress, breathing versus control, with
  confidence intervals, a paired Wilcoxon test over people who did both, and Cohen's d.
- The share of resets whose facial change is within measurement noise.

## How to report it
- Say "the facial stress signal fell", not "stress was cured".
- Report effect sizes and confidence intervals, and say the sample is small.
- State that the facial stress score is derived from an emotion classifier that was not
  trained to measure stress, and give the correlation with self-report as the evidence
  for or against its validity.
- State that the bias classifier was trained on synthetic data, and what real-data
  evaluation you did.

## Privacy checklist
- [x] Face photos are not stored (server and app both strip them).
- [x] Consent shown before the first camera use; recorded with a version.
- [x] Participants can delete their data from Profile > Research & Privacy.
- [ ] Run `scrub_stored_face_images.py` (dry run, then `--apply`) once to remove photos
      saved by older versions of the app.
- [ ] Do not share the export salt or any file that links coded IDs to names.
