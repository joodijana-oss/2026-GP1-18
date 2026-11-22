# Blind grades: held-out ho_c, dev clean (Lama), dev flawed (Nora)

Graded blind from the six anonymous outputs in each grading sheet:
- atsimprove/grading/ho_c.md against heldout/ho_c.key.md
- atsimprove/grading/dev_clean.md against atscheck/answer_key_clean.md
- atsimprove/grading/dev_flawed.md against atscheck/answer_key_flawed.md

I did not open grading_mapping.json, any sealed/ folder, the runs/ folders, the measure reports, the decision rules or the prompt files. Nothing here says which label is which version.

## How each issue was classified

- **Real (key)**: matches a weakness or planted problem in the answer key, in any area. A wrong area is noted but still counts.
- **Real (not in key)**: true, grounded and reasonable, but the key does not list it and does not call that text fine. Shown on its own so a key-strict reader can count it as an extra.
- **Neutral**: listed in the key as neutral (true but unplanned, an extraction artifact, or a neutral suggestion). No credit and no penalty.
- **False**: factually wrong, or flags something the key says must not be flagged.
- **Padding**: suggests skills, tools or platforms the CV does not have, or nitpicks text the key calls strong or fine.
- **Invented fact (major)**: a suggested rewrite states as fact a number, scope, outcome, model or tool that is not in the CV, with no placeholder and no "if".
- **Invented fact (minor date)**: a suggestion gives a specific month or date the CV does not contain, offered as an "for example" date for a real entry.
- **Misquote**: text in quotation marks presented as the CV's words that is not in the CV. Proposed rewrites, format labels such as "Mon YYYY", and placeholders are not misquotes. Every span the tool flagged as "Quotes not found" was checked by hand.

Unwanted = False + Padding.

---

## 1. Held-out clean: ho_c (Data Analyst, strong CV)

Key: C1 = the weak bullet "Worked on data cleaning tasks for the team"; C2 = no portfolio or Tableau Public link. Everything else is fine. The key says a good review reports at most these two.

Item codes used below:
- ORDER: Projects are listed 2024 then 2025, so not most recent first. Not in the key, and the key does not call the order fine. It is true, and the dev keys use the same most-recent-first rule (dev flawed P4). Graded Real (not in key). All six outputs report it, so it does not separate the labels.
- DATEFMT: Projects and Certifications give only the year while Experience and Education give month and year. Graded **Padding**: it nitpicks lines the key calls fine ("Certifications have name, issuer and year"; CF3 "consistent format"). A strict reader may count it as False.
- DATAMODEL: add "Data Modeling" to Skills because of the star schema. Grounded and not invented, but the key says the Skills list is fine and matches the bullets. Graded Padding (grounded nitpick).
- STATSPEC: change "Statistics" to "Statistics (Regression Analysis)". Grounded (the project used regression), but a nitpick on a Skills list the key calls fine. Graded Padding.

### Per-issue grades

| Label | Area | Issue | Grade | Notes |
|---|---|---|---|---|
| ho_c_01 | sectionOrganization | Projects 2024 before 2025 | Real (not in key) | ORDER |
| ho_c_01 | readability | "Worked on data cleaning tasks for the team" vague | Real (key C1) | Rewrite uses placeholders |
| ho_c_02 | sectionOrganization | Projects order | Real (not in key) | ORDER |
| ho_c_02 | readability | C1 bullet vague | Real (key C1) | |
| ho_c_02 | contentFormatting | Certification dates year-only | Padding | DATEFMT. Suggestion "Microsoft, Aug 2025" gives an invented month: invented fact (minor date) |
| ho_c_03 | sectionOrganization | Projects order | Real (not in key) | ORDER |
| ho_c_03 | readability | C1 bullet vague | Real (key C1) | Rewrite "Cleaned and standardized sales records across 38 stores to improve dashboard accuracy" has no placeholder and asserts a scope (38 stores, taken from another bullet) and an outcome the CV does not state: invented fact (major) |
| ho_c_04 | sectionOrganization | Projects order | Real (not in key) | ORDER |
| ho_c_04 | readability | C1 bullet vague | Real (key C1) | Placeholders |
| ho_c_05 | sectionOrganization | Projects order | Real (not in key) | ORDER |
| ho_c_05 | keywordUsage | Add "Data Modeling" | Padding | DATAMODEL (grounded) |
| ho_c_05 | keywordUsage | Make "Statistics" specific | Padding | STATSPEC (grounded) |
| ho_c_05 | readability | C1 bullet vague | Real (key C1) | |
| ho_c_05 | contentFormatting | Projects and Certifications year-only | Padding | DATEFMT |
| ho_c_06 | sectionOrganization | Projects order | Real (not in key) | ORDER |
| ho_c_06 | readability | C1 bullet vague | Real (key C1) | Template "...to prepare them for the weekly dashboards" assumes a purpose. Borderline, not counted |
| ho_c_06 | contentFormatting | Projects and Certifications year-only | Padding | DATEFMT. Says to add months "if you remember them", so nothing invented |

C2 (portfolio link): **missed by all six**. No output flagged the summary, the contact line, the gap, headings, certifications or length, so there are no outright False grades on this sheet.
Misquotes: none. Every quoted CV span is exact. The flagged "not found" spans are all proposed rewrites or format labels.

### Totals per label (ho_c)

| Label | Issues | Real (key) | Real (not in key) | Neutral | False | Padding | Unwanted | Invented major | Invented minor date | Misquotes | Key hits (of 2) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ho_c_01 | 2 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 (C1) |
| ho_c_02 | 3 | 1 | 1 | 0 | 0 | 1 | 1 | 0 | 1 | 0 | 1 (C1) |
| ho_c_03 | 2 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 (C1) |
| ho_c_04 | 2 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 (C1) |
| ho_c_05 | 5 | 1 | 1 | 0 | 0 | 3 | 3 | 0 | 0 | 0 | 1 (C1) |
| ho_c_06 | 3 | 1 | 1 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 1 (C1) |

Key-strict extras (every issue that is not C1, C2 or a key-neutral item): 01 = 1, 02 = 2, 03 = 1, 04 = 1, 05 = 4, 06 = 2.

---

## 2. Development clean: Lama (AI / ML Engineer, well-built CV)

Key weaknesses W1 to W9, all minor. Key-neutral items include first-person wording in the Summary (code FP).

| Label | Area | Issue | Grade | Notes |
|---|---|---|---|---|
| dev_clean_01 | cvStructure | No GitHub / LinkedIn / portfolio link | Real (key W1) | |
| dev_clean_01 | sectionOrganization | Skills near the bottom | Real (key W2) | |
| dev_clean_01 | keywordUsage | Add "deep learning", "convolutional neural networks" | Real (key W5) | Both valid in the key |
| dev_clean_01 | readability | First-person Summary | Neutral (FP) | Rewrite grounded |
| dev_clean_01 | readability | WhatsApp menu and Physics project have no result | Real (key W4) | Asks for numbers, invents none |
| dev_clean_01 | contentFormatting | Mixed date formats | Real (key W8) | |
| dev_clean_02 | cvStructure | No LinkedIn / GitHub link | Real (key W1) | |
| dev_clean_02 | keywordUsage | Add ML, DL, CV to Skills | Real (key W5) | |
| dev_clean_02 | readability | First-person Summary | Neutral (FP) | |
| dev_clean_02 | readability | Dashboard bullet has no result | Real (key W4) | Placeholders |
| dev_clean_02 | contentFormatting | Mixed date formats | Real (key W8) | Suggestion "write your Education dates as Aug 2022 - Jun 2026" gives months the CV does not have: invented fact (minor date) |
| dev_clean_03 | cvStructure | No GitHub / portfolio link | Real (key W1) | |
| dev_clean_03 | cvStructure | Skills after Certifications | Real (key W2) | |
| dev_clean_03 | keywordUsage | "time series forecasting", "if that is the technique you used" | Real (key W5) | Conditional, so not invented |
| dev_clean_03 | keywordUsage | "image classification" | Real (key W5) | |
| dev_clean_03 | readability | First-person Summary | Neutral (FP) | |
| dev_clean_03 | readability | Demand Forecast Service has no result | Real (key W4) | Placeholders |
| dev_clean_03 | contentFormatting | Mixed date formats | Real (key W8) | |
| dev_clean_04 | cvStructure | Physics II project unrelated, remove or replace | Real (key W6) | Key areas are Keyword or Section Org, so the area is off |
| dev_clean_04 | keywordUsage | Power BI listed but never used in a bullet | Real (not in key) | True: no bullet names Power BI. Suggests showing where it was used or removing it, so nothing invented |
| dev_clean_04 | keywordUsage | Add "Machine Learning", "Deep Learning" | Real (key W5) | |
| dev_clean_04 | readability | First-person Summary | Neutral (FP) | Quotes 'I want to start...', but the CV says "and want to start my career": **misquote** |
| dev_clean_04 | contentFormatting | Mixed date formats | Real (key W8) | |
| dev_clean_05 | keywordUsage | Add ML, DL, CV, Model Deployment line | Real (key W5) | |
| dev_clean_05 | readability | First-person Summary | Neutral (FP) | |
| dev_clean_05 | contentFormatting | Mixed date formats | Real (key W8) | |
| dev_clean_06 | cvStructure | No LinkedIn / GitHub link | Real (key W1) | |
| dev_clean_06 | cvStructure | Skills sits late, reorder | Real (key W2) | |
| dev_clean_06 | keywordUsage | Add "Machine Learning", "Deep Learning" | Real (key W5) | |
| dev_clean_06 | keywordUsage | Add "Computer Vision" | Real (key W5) | Same weakness split into a second issue |
| dev_clean_06 | keywordUsage | Use "model deployment" | Real (key W5) | Third W5 issue. "REST API" for a FastAPI service is a fair description, not counted as invented |
| dev_clean_06 | readability | First-person Summary | Neutral (FP) | |
| dev_clean_06 | readability | Dashboard bullet has no result | Real (key W4) | Placeholders |
| dev_clean_06 | readability | Demand Forecast Service has no result | Real (key W4) | Placeholders |
| dev_clean_06 | contentFormatting | Mixed date formats | Real (key W8) | |

No output flagged any must-not-flag item: no missing sections, no "degree ongoing", no ordering complaint, no spelling or grouping complaint, and no skill the CV lacks (no TensorFlow, cloud, MLOps, NLP, LLM or generative AI). So there are no False or Padding grades on this sheet.
Missed by all six: W3 (projects as paragraphs, allowed but not expected), W7 (certificate has no issuer) and W9 (Git under Programming, allowed but not expected).

### Totals per label (dev clean)

| Label | Issues | Real (key) | Real (not in key) | Neutral | False | Padding | Unwanted | Invented major | Invented minor date | Misquotes | Distinct key weaknesses (of 9) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| dev_clean_01 | 6 | 5 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 5 (W1 W2 W4 W5 W8) |
| dev_clean_02 | 5 | 4 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 4 (W1 W4 W5 W8) |
| dev_clean_03 | 7 | 6 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 5 (W1 W2 W4 W5 W8) |
| dev_clean_04 | 5 | 3 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 3 (W5 W6 W8) |
| dev_clean_05 | 3 | 2 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2 (W5 W8) |
| dev_clean_06 | 9 | 8 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 5 (W1 W2 W4 W5 W8) |

---

## 3. Development flawed: Nora (12 planted problems)

Key-neutral items: no LinkedIn or GitHub link (LINKS), first-person writing (FP), vague Summary (SUMV). P12 counts as caught only when both parts are found (date formats and the false "present"). All six found both parts.

Crediting decisions:
- One issue that covers two planted problems gets credit for both: P2 + P3 (allowed by the key) and P6 + P7 in dev_flawed_05.
- P2 partial: dev_flawed_03 reports only the missing links, not the missing phone. The key lists links as neutral but says they "also fit under P2", so this is partial and not counted as caught.
- P11 partial: dev_flawed_02 never addresses the duty lines ("Responsible for", "Duties included", "Worked on AI stuff"). It does flag missing results on the late-delivery model, the Mood Checker and the House Price Guesser. That is real and is the result half of P11, so it is partial.
- Crowded out: dev_flawed_01 has P3, P12a and P12b in Content Formatting and no P7. This is exactly the case in the key's cap note, so P7 is "crowded out", not missed.
- Invented start months for the internship ("06/2025", "June", "July", "Jun") are minor-date inventions. The CV says only "ten-week summer internship that finished in September 2025". dev_flawed_04 used "[start month]" and is clean.

| Label | Area | Issue | Grade |
|---|---|---|---|
| dev_flawed_01 | cvStructure | No Skills section | Real P1 |
| dev_flawed_01 | sectionOrganization | Jobs oldest first | Real P4 |
| dev_flawed_01 | sectionOrganization | "THINGS I BUILT" heading | Real P6 |
| dev_flawed_01 | keywordUsage | "guess which deliveries will arrive late", rename as a classification model | Real P8 (grounded: the CV says sk-learn was used) |
| dev_flawed_01 | keywordUsage | "the thing that reads customer messages...", rename as NLP text classification | Real P8 |
| dev_flawed_01 | readability | Casual first-person narrative | Neutral FP. Rewrite says "using a CNN trained on ~4,000 labeled photos" with no "if". The key says a named architecture counts as inventing: **invented fact (major)** |
| dev_flawed_01 | readability | Lab Assistant duty lines | Real P11. Rewrite "Assisted 30+ first-year students weekly..." invents a number: **invented fact (major)** |
| dev_flawed_01 | readability | Trainee entry is one run-on sentence | Real P10 |
| dev_flawed_01 | contentFormatting | "2025 - present" against "finished in September 2025" | Real P12b. "Jun 2025 - Sep 2025": invented fact (minor date) |
| dev_flawed_01 | contentFormatting | Mixed date formats | Real P12a |
| dev_flawed_01 | contentFormatting | Email not standard | Real P3 |
| dev_flawed_02 | cvStructure | No Skills section | Real P1 |
| dev_flawed_02 | cvStructure | Phone and links missing, email not standard | Real P2 + P3 |
| dev_flawed_02 | sectionOrganization | "EXPERIANCE" misspelled | Real P7 |
| dev_flawed_02 | sectionOrganization | "THINGS I BUILT" | Real P6 |
| dev_flawed_02 | sectionOrganization | Jobs oldest first | Real P4 |
| dev_flawed_02 | keywordUsage | Tool names inconsistent | Real P9 |
| dev_flawed_02 | keywordUsage | Use "sentiment analysis" | Real P8 |
| dev_flawed_02 | keywordUsage | Use "image classification" | Real P8 (second issue) |
| dev_flawed_02 | readability | Trainee entry is one run-on sentence | Real P10 |
| dev_flawed_02 | readability | First-person stories, "I made" / "I gathered" | Neutral FP |
| dev_flawed_02 | readability | Late-delivery model, Mood Checker and Price Guesser have no result | Real (P11 partial). Placeholders |
| dev_flawed_02 | contentFormatting | False "present" | Real P12b. "July 2025 - September 2025": invented fact (minor date) |
| dev_flawed_02 | contentFormatting | Mixed date formats | Real P12a |
| dev_flawed_03 | cvStructure | No Skills section | Real P1 |
| dev_flawed_03 | cvStructure | No GitHub / portfolio / LinkedIn | Neutral LINKS (P2 partial: phone not mentioned) |
| dev_flawed_03 | sectionOrganization | "EXPERIANCE" misspelled | Real P7 (alternative area) |
| dev_flawed_03 | sectionOrganization | Jobs oldest first | Real P4 |
| dev_flawed_03 | keywordUsage | Plain wording, use image classification / sentiment analysis / text classification | Real P8 |
| dev_flawed_03 | readability | First-person narration ("I made", "I collected", "I gathered") | Neutral FP |
| dev_flawed_03 | readability | "it got it right most of the time" is vague | Real P11. Suggestion quotes "the '35% reduction in response time' example used elsewhere", but the CV says "Reduced model response time by 35%": **misquote** |
| dev_flawed_03 | readability | "Duties included various tasks..." | Real P11 (second issue) |
| dev_flawed_03 | contentFormatting | Mixed date formats | Real P12a |
| dev_flawed_03 | contentFormatting | False "present" | Real P12b. "06/2025 - 09/2025 (or the exact months)": invented fact (minor date) |
| dev_flawed_04 | cvStructure | No Skills section | Real P1 |
| dev_flawed_04 | cvStructure | Email not standard, no phone, no links | Real P2 + P3 |
| dev_flawed_04 | sectionOrganization | "EXPERIANCE" | Real P7 |
| dev_flawed_04 | sectionOrganization | "THINGS I BUILT" | Real P6 |
| dev_flawed_04 | sectionOrganization | Jobs oldest first | Real P4 |
| dev_flawed_04 | keywordUsage | "sk-learn" / "Scikit learn" | Real P9 |
| dev_flawed_04 | keywordUsage | Pytorch / Tensorflow / PYTHON casing | Real P9 (second issue) |
| dev_flawed_04 | keywordUsage | Plain wording, add standard terms "if that is what you built" | Real P8 |
| dev_flawed_04 | readability | Trainee entry is one run-on sentence | Real P10 |
| dev_flawed_04 | readability | "Responsible for" / "Duties included" | Real P11 |
| dev_flawed_04 | readability | "it got it right most of the time", "worked well enough" | Real P11 (second issue). Placeholder |
| dev_flawed_04 | contentFormatting | Mixed date formats | Real P12a |
| dev_flawed_04 | contentFormatting | False "present" | Real P12b. Uses "[start month]", so nothing invented |
| dev_flawed_05 | cvStructure | No Skills section | Real P1 |
| dev_flawed_05 | cvStructure | Phone missing, email not standard, no links | Real P2 + P3 |
| dev_flawed_05 | sectionOrganization | "EXPERIANCE" and "THINGS I BUILT" in one issue | Real P7 + P6 |
| dev_flawed_05 | sectionOrganization | Graduation project inside Education | Real P5 |
| dev_flawed_05 | sectionOrganization | Jobs oldest first | Real P4 |
| dev_flawed_05 | keywordUsage | Python / TensorFlow / PyTorch casing | Real P9 |
| dev_flawed_05 | keywordUsage | "sk-learn" / "Scikit learn" | Real P9 (second issue) |
| dev_flawed_05 | keywordUsage | Plain wording, use sentiment analysis / classification / fine-tuning | Real P8 |
| dev_flawed_05 | readability | Trainee entry is one long story | Real P10 |
| dev_flawed_05 | readability | First person, plus "Responsible for" lines | Real P11 |
| dev_flawed_05 | readability | "it got it right most of the time", "worked well enough" | Real P11 (second issue). Placeholder |
| dev_flawed_05 | contentFormatting | False "present" | Real P12b. "June 2025 - September 2025": invented fact (minor date) |
| dev_flawed_05 | contentFormatting | Mixed date formats | Real P12a |
| dev_flawed_06 | cvStructure | No Skills section | Real P1 |
| dev_flawed_06 | sectionOrganization | Jobs oldest first | Real P4 |
| dev_flawed_06 | sectionOrganization | "EXPERIANCE" | Real P7 |
| dev_flawed_06 | sectionOrganization | "THINGS I BUILT" | Real P6 |
| dev_flawed_06 | keywordUsage | Tool names inconsistent (incl. power bi, GIT, jupyter) | Real P9 |
| dev_flawed_06 | readability | Summary vague | Neutral SUMV |
| dev_flawed_06 | readability | Graduation project is a casual first-person narrative | Neutral FP. Rewrite uses only CV facts (Python, TensorFlow, 4,000 images) |
| dev_flawed_06 | readability | "Responsible for" lines | Real P11 |
| dev_flawed_06 | contentFormatting | Mixed date formats | Real P12a |
| dev_flawed_06 | contentFormatting | False "present" | Real P12b. "Jun 2025 - Sep 2025": invented fact (minor date) |
| dev_flawed_06 | contentFormatting | Email not standard | Real P3 |

No output flagged a fine item: F1 degree, F2 ONNX bullet, F3 certifications, F4 languages, and F5 sections present. No output suggested a tool the CV lacks. Every tool in the "add a Skills section" lists appears in the CV. So there are no False or Padding grades on this sheet.

### Planted problems caught (of 12)

| Label | Caught | Partial | Crowded out | Missed |
|---|---|---|---|---|
| dev_flawed_01 | 8 (P1 P3 P4 P6 P8 P10 P11 P12) | - | P7 | P2 P5 P9 |
| dev_flawed_02 | 10 (P1 P2 P3 P4 P6 P7 P8 P9 P10 P12) | P11 | - | P5 |
| dev_flawed_03 | 6 (P1 P4 P7 P8 P11 P12) | P2 | - | P3 P5 P6 P9 P10 |
| dev_flawed_04 | 11 (all but P5) | - | - | P5 |
| dev_flawed_05 | 12 (all) | - | - | - |
| dev_flawed_06 | 8 (P1 P3 P4 P6 P7 P9 P11 P12) | - | - | P2 P5 P8 P10 |

Scored as caught = 1, partial = 0.5, crowded out = not a miss: 01 = 8 (+1 crowded out), 02 = 10.5, 03 = 6.5, 04 = 11, 05 = 12, 06 = 8.

### Totals per label (dev flawed)

| Label | Issues | Real (planted) | Neutral | False | Padding | Unwanted | Invented major | Invented minor date | Misquotes | Planted caught (of 12) |
|---|---|---|---|---|---|---|---|---|---|---|
| dev_flawed_01 | 11 | 10 | 1 | 0 | 0 | 0 | 2 | 1 | 0 | 8 (+P7 crowded out) |
| dev_flawed_02 | 13 | 12 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 10 (+P11 partial) |
| dev_flawed_03 | 10 | 8 | 2 | 0 | 0 | 0 | 0 | 1 | 1 | 6 (+P2 partial) |
| dev_flawed_04 | 13 | 13 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 11 |
| dev_flawed_05 | 13 | 13 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 12 |
| dev_flawed_06 | 11 | 9 | 2 | 0 | 0 | 0 | 0 | 1 | 0 | 8 |

---

## 4. Run-to-run consistency (blind)

I cannot tell which labels share a version. The figures below cover all six labels in each sheet. The pairwise matrices let whoever holds the mapping average the within-version pairs (three runs give three pairs per version) and compare them with the cross-version pairs.

Item sets used for Jaccard. ho_c: ORDER, C1, DATEFMT, DATAMODEL, STATSPEC. Dev clean: W1 to W9, FP, PBI. Dev flawed: full planted catches only, P1 to P12.

### Issue count spread

| Sheet | Counts (01..06) | Mean | SD | Range |
|---|---|---|---|---|
| ho_c | 2, 3, 2, 2, 5, 3 | 2.83 | 1.17 | 2-5 |
| dev clean | 6, 5, 7, 5, 3, 9 | 5.83 | 2.04 | 3-9 |
| dev flawed | 11, 13, 10, 13, 13, 11 | 11.83 | 1.33 | 10-13 |

### How many of the six outputs reported each item

- ho_c: C1 6/6, ORDER 6/6, DATEFMT 3/6 (02, 05, 06), DATAMODEL 1/6 (05), STATSPEC 1/6 (05), C2 0/6.
- Dev clean: W5 6/6, W8 6/6, FP 6/6, W1 4/6 (01 02 03 06), W4 4/6 (01 02 03 06), W2 3/6 (01 03 06), W6 1/6 (04), PBI 1/6 (04), W3 W7 W9 0/6.
- Dev flawed: P1 6/6, P4 6/6, P12 6/6, P3 5/6, P6 5/6, P7 5/6, P8 5/6, P11 5/6, P9 4/6, P10 4/6, P2 3/6, P5 1/6.

### Pairwise Jaccard similarity of item sets

ho_c (mean of 15 pairs 0.69)

| | 01 | 02 | 03 | 04 | 05 | 06 |
|---|---|---|---|---|---|---|
| 01 | 1.00 | 0.67 | 1.00 | 1.00 | 0.40 | 0.67 |
| 02 | 0.67 | 1.00 | 0.67 | 0.67 | 0.60 | 1.00 |
| 03 | 1.00 | 0.67 | 1.00 | 1.00 | 0.40 | 0.67 |
| 04 | 1.00 | 0.67 | 1.00 | 1.00 | 0.40 | 0.67 |
| 05 | 0.40 | 0.60 | 0.40 | 0.40 | 1.00 | 0.60 |
| 06 | 0.67 | 1.00 | 0.67 | 0.67 | 0.60 | 1.00 |

Dev clean (mean of 15 pairs 0.65)

| | 01 | 02 | 03 | 04 | 05 | 06 |
|---|---|---|---|---|---|---|
| 01 | 1.00 | 0.83 | 1.00 | 0.38 | 0.50 | 1.00 |
| 02 | 0.83 | 1.00 | 0.83 | 0.43 | 0.60 | 0.83 |
| 03 | 1.00 | 0.83 | 1.00 | 0.38 | 0.50 | 1.00 |
| 04 | 0.38 | 0.43 | 0.38 | 1.00 | 0.60 | 0.38 |
| 05 | 0.50 | 0.60 | 0.50 | 0.60 | 1.00 | 0.50 |
| 06 | 1.00 | 0.83 | 1.00 | 0.38 | 0.50 | 1.00 |

Dev flawed, planted catches (mean of 15 pairs 0.66)

| | 01 | 02 | 03 | 04 | 05 | 06 |
|---|---|---|---|---|---|---|
| 01 | 1.00 | 0.64 | 0.56 | 0.73 | 0.67 | 0.60 |
| 02 | 0.64 | 1.00 | 0.45 | 0.91 | 0.83 | 0.64 |
| 03 | 0.56 | 0.45 | 1.00 | 0.55 | 0.50 | 0.56 |
| 04 | 0.73 | 0.91 | 0.55 | 1.00 | 0.92 | 0.73 |
| 05 | 0.67 | 0.83 | 0.50 | 0.92 | 1.00 | 0.67 |
| 06 | 0.60 | 0.64 | 0.56 | 0.73 | 0.67 | 1.00 |

Blind observations, with no claim about versions:
- ho_c: labels 01, 03 and 04 give identical item sets, and 02 and 06 give identical item sets. Label 05 stands apart: it has the most padding (3).
- Dev clean: labels 01, 03 and 06 give identical item sets. Label 04 is the outlier (W6, PBI and a misquote) and label 05 is the sparsest.
- Dev flawed: labels 02, 04 and 05 form a tight cluster (Jaccard 0.83 to 0.92, 10 to 12 caught). Labels 01, 03 and 06 are looser (0.56 to 0.60, 6 to 8 caught), and all invented-fact majors and the misquote fall in that group.

---

## 5. Summary totals per label (all three sheets)

| Label | Issues | Real (key) | Real (not in key) | Neutral | False | Padding | Invented major | Invented minor date | Misquotes | Key / planted hits |
|---|---|---|---|---|---|---|---|---|---|---|
| ho_c_01 | 2 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | C1 (1/2) |
| ho_c_02 | 3 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0 | C1 (1/2) |
| ho_c_03 | 2 | 1 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | C1 (1/2) |
| ho_c_04 | 2 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | C1 (1/2) |
| ho_c_05 | 5 | 1 | 1 | 0 | 0 | 3 | 0 | 0 | 0 | C1 (1/2) |
| ho_c_06 | 3 | 1 | 1 | 0 | 0 | 1 | 0 | 0 | 0 | C1 (1/2) |
| dev_clean_01 | 6 | 5 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 5/9 |
| dev_clean_02 | 5 | 4 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 4/9 |
| dev_clean_03 | 7 | 6 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 5/9 |
| dev_clean_04 | 5 | 3 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 3/9 |
| dev_clean_05 | 3 | 2 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 2/9 |
| dev_clean_06 | 9 | 8 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 5/9 |
| dev_flawed_01 | 11 | 10 | 0 | 1 | 0 | 0 | 2 | 1 | 0 | 8/12 (+1 crowded out) |
| dev_flawed_02 | 13 | 12 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 10/12 (+1 partial) |
| dev_flawed_03 | 10 | 8 | 0 | 2 | 0 | 0 | 0 | 1 | 1 | 6/12 (+1 partial) |
| dev_flawed_04 | 13 | 13 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 11/12 |
| dev_flawed_05 | 13 | 13 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 12/12 |
| dev_flawed_06 | 11 | 9 | 0 | 2 | 0 | 0 | 0 | 1 | 0 | 8/12 |

Grading judgement calls to re-check after unblinding. None of them changes a label's False count, because the sheets have no False grades at all:
1. ho_c ORDER counted as Real (not in key). All six report it, so it does not separate the labels.
2. ho_c DATEFMT, DATAMODEL and STATSPEC counted as Padding. A strict reader of CF3 could call DATEFMT False instead.
3. Example dates with an invented month are counted as minor inventions, separate from the major ones (numbers, named architecture, invented scope).
4. Partial credits: dev_flawed_03 P2 and dev_flawed_02 P11. Crowded out: dev_flawed_01 P7.
