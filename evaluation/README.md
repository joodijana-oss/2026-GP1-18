# Evaluation records (Section 5.1 of the report)

This folder keeps the saved runs behind every number in Section 5.1,
Experimental Results. Each experiment compares a candidate with the version
that was in the app before it, on a held-out set that the builders did not
read, under a decision rule that was written and fixed (with its SHA-256
hash) before the held-out measurement. All test CVs and test users are
fictional and contain no personal data.

## Read the tests and results

`Masra_Evaluation.ipynb` is a Jupyter notebook, saved with its outputs, so
GitHub shows it with every table and chart. It runs the app's automated tests
(`flutter test`), recomputes every number of Section 5.1 in Python from the
saved records, independently of the Dart tools, and ends with a table that
marks each check PASS, FAIL or SKIPPED. It sends no request to the AI service.
To run it again from the repository root:

```bash
python -m nbconvert --to notebook --execute --inplace evaluation/Masra_Evaluation.ipynb
```

It needs Python 3 with pandas, numpy, matplotlib, nbconvert and ipykernel.
Without Dart and Flutter (for example in Colab), the checks that need them
are marked SKIPPED, never PASS.

## Check the results again with the project's tools

```bash
dart run tools/rerun_evaluations.dart
```

It sends no request to the AI service and costs nothing. It copies the saved
runs to `build/rerun/`, scores them again with the project's own tools,
compares the result with the saved output, and writes a dated log to
`evaluation/logs/`. The ATS part needs Python 3 (no packages). The last log
is `logs/rerun_2026-11-22.txt`: 9 checks the same, 0 different, 1 skipped
(the matching scores, explained below).

## Folders

| Folder | Experiment | Section |
|---|---|---|
| `skill_gaps/` | Skill gaps of the AI Career Analysis | 5.1.1 |
| `recommender/` | Ranking of the Opportunity Recommender | 5.1.2 |
| `matching/` | Matching skill gaps to certifications and opportunities by meaning | 5.1.3 |
| `ats_review/` | Review instructions of the CV Improvement Assistant | 5.1.4 |
| `logs/` | Output of `tools/rerun_evaluations.dart` | |

## 1. Skill gaps (5.1.1): adopted

- **Compared:** G0E0, the original gap step (two lists of skill names),
  with G1E1 (single-skill market names, each checked against a quote from
  the CV). G1E1 is what the app runs (`AnalysisSettings.app` in
  `lib/services/career_analysis_pipeline.dart`).
- **Rule:** the six rules are coded in `tools/gap_eval/evaluate_gaps.dart`
  and printed at the end of each `scores.txt`; the hashes of the code, the
  data and the test set are pinned in `tools/gap_eval/freeze.json`.
- **Final measurement:** `skill_gaps/final_run/` (16 CVs in
  `test/fixtures/cv_eval_final/`, 3 runs per CV, versions G0E0 and G1E1).
  - `raw/`: the answers of the AI service;
  - gap names that are not in the answer keys were judged in the set's
    `judgements/names.csv` (194 names for the final set). The run's
    `review/names_review.csv` is empty because no name was left to judge,
    and `review/names_second.csv` is a second-rater sheet that was never
    filled in, so this experiment has no agreement measure between graders;
  - `scores.txt`: the scores and the decision ("G1E1"). Its line "This is
    not the held-out set" appears because the tool prints it for any set
    whose manifest is not named "heldout"; this set is named "final" and was
    kept away from the builders like a held-out set.
- **First held-out round:** `skill_gaps/first_run/`, on the 16 CVs in
  `skill_gaps/first_set/`, with four versions (G0E0, G0E1, G1E1, G2E1).
  Its gap names were judged in `skill_gaps/first_set/judgements/names.csv`
  (182 names). G1E1 was the only version that passed every rule there too. That set was
  used during the quality checks, so a new set was written for the final
  decision.
- **Cost of the final run:** 144 requests and 1.23 USD in all: a 3-request
  smoke test, then the 141 requests that `final_run/requests.log` counts
  (about 1.21 USD).
- **Rerun:** both runs score the same as saved.

## 2. Opportunity recommender (5.1.2): adopted

- **Compared:** the first recommender (frozen in
  `tools/recommender_eval/baseline_recommender.dart`) with the recommender
  the app uses (`lib/services/opportunity_recommender.dart`).
- **Data:** 8 development test users
  (`test/fixtures/opportunity_eval_personas.json`) and 8 held-out test users
  (`test/fixtures/opportunity_eval_personas_heldout.json`). The evaluation
  date is fixed (19 November 2026), so the rankings do not change over time.
- **Target:** none fixed in advance; the new system is compared with the
  baseline, and differences of about 0.02 are noise.
- **Saved output:** `recommender/development_2026-11-22.txt` and
  `recommender/heldout_2026-11-22.txt` (with the ablation). Only the TIMING
  block changes between runs.
- **Rerun:** both outputs are the same apart from the timing.

## 3. Matching by meaning (5.1.3): not adopted

- **Compared:** A0 (word matching) with B and B-opp (typed skill links from
  the AI service, with a support check), and the word control L1g.
- **Rule:** `tools/gap_eval/decision_rule_r2.txt`, pinned by
  `tools/gap_eval/freeze_r2.json`. The speed guard was changed once after a
  development result had been seen (`tools/gap_eval/freeze_r2_amendment_timing.json`);
  B failed the precision guard in any case, so this did not affect the
  decision.
- **Final measurement:** `matching/final_run/`.
  - `raw/`: the link answers and market lists;
  - `judgements/teaching.csv` and `teaching_second.csv`: the blind grades of
    618 item and gap pairs, and of 124 pairs by a second grader (Cohen's
    kappa 0.840);
  - `guards/`: the persona guard and the five timing runs;
  - `review/matching_scores_r2.txt`: the scores and the decision ("no
    candidate passes these rules. A0 stays").
- `matching/persona_links/`: the link files of the persona guard.
- `matching/first_round/matching_scores.txt`: the earlier round. No
  candidate had been frozen before its measurement, so only A0 and the word
  control were scored on 40 unseen names, and A0 was kept. Its
  grades are in `test/fixtures/cv_eval_final/judgements/teaching.csv`.
- **Cost of the final round:** 91 requests, about 1.09 USD.
- **Why the scores are not computed again:** the scoring tool compares the
  app's code and data with the hashes in `freeze_r2.json` and refuses to run
  when they differ. After the measurement, and before they were committed,
  two files were edited: `lib/assets/data/Masra_Opportunities.json` (link
  fixes) and `lib/services/job_postings.dart` (job-title matching). So no
  commit holds the exact state of the measurement, and the score cannot be
  repeated byte for byte. The rerun script checks instead that the saved
  grades and the saved score output still have the SHA-256 recorded when
  they were saved.

## 4. ATS review instructions (5.1.4): not adopted

- **Compared:** OLD, the review instructions the app sends
  (`tools/ats_eval/old_improve_cv_prompt.txt`), with NEW, the rewritten
  instructions (`ats_review/new_review_text.txt`).
- **Rule:** `tools/ats_eval/decision_rule.txt`.
- **Held-out set:** `ats_review/heldout_set/`: four fictional CVs and their
  answer keys (ho_a, ho_b and ho_d with planted problems, ho_c clean).
- **Runs:** `ats_review/runs/heldout/` and `ats_review/runs/dev/`.
  `blind/outputs/` holds the outputs under anonymous labels, as the graders
  saw them; `sealed/` holds the raw answers, the failed attempts and the
  label mapping.
- **Grades:** `ats_review/grades/`. The graders saved them before the labels
  were revealed, with these SHA-256 values, which the files still have:
  - `grades_flawed.csv`: f50ba497518900ea93f74c4cdc4bef4ddd77491925f3e8e8171a6d29d659264b
  - `grades_flawed.md`: d78a282f5e3ec1105a96837b5e2ec10b683d71d5e42b47f877824f4f86ada5d2
  - `grades_clean_dev.md`: c3f64d86763b51d618269358109a605393c7fb940f04a0a8a690a69d9274ead7

  The grade files name the folders they came from at the time:
  `atsimprove/grading/` is `ats_review/grading_sheets/` here, and
  `atscheck/answer_key_*.md` is `ats_review/development_keys/`.
- **Scorers:** `ats_review/score_heldout.py` (decides) and
  `ats_review/score_dev.py` (development, reported only).
- **Time and tokens:** `ats_review/measure/times.txt` and `totals.txt`.
  45 requests, 3.19 USD.
- **Rerun:** both scorers give the same counts and the decision "KEEP OLD".

## Changes made when the records were copied here

Stated so that nothing is hidden:

- Local folder paths were replaced with paths inside the project in
  `skill_gaps/*/config.json`, the first line of `skill_gaps/*/scores.txt`,
  `ats_review/grades/grading_mapping.json` and
  `ats_review/measure/totals.txt`. Nothing else in these files changed. The
  mapping had SHA-256 c0ea0427b6c948f9c88ab598fcccc23b9b35643f0245e32feb99d852d8eb4c2f
  before this change.
- `ats_review/score_heldout.py`: the copy used for the decision compared the
  recall gain with 0.300 instead of the rule's 0.100 (one line). The gain
  was -0.103, which fails both, so the decision is the same; the copy here
  uses 0.100, and its header says so.
- Review sheets that repeat course descriptions from the app's data were
  left out (`review/teaching_review.csv`, `review/teaching_second.csv`,
  `review/parts/`, and `judgements/teaching.csv` of the first held-out set).
  The scores do not read them. In `matching/final_run/judgements/`, catalogue
  texts that named an AI product were replaced before the grades were saved;
  the scorer does not read that column.
