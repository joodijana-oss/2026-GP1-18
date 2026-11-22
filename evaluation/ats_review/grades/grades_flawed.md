# ATS review test: blind grades for the held-out flawed CVs (ho_a, ho_b, ho_d)

Graded blind: only the anonymous labels in `grading/ho_a.md`, `grading/ho_b.md` and `grading/ho_d.md` were read, against `heldout/ho_X.key.md`. The mapping file, the sealed folders and the measure reports were not opened. Each label is a single output, so nothing here says which version or run a label belongs to.

Per-issue verdicts (one row per issue, same columns as `blind/sheet.csv`): `grades_flawed.csv` in this folder.

## How the grades were given

- Verdicts follow `decision_rule_final2.txt`: PLANTED, NEUTRAL, WRONG, PADDED, FINE_FLAGGED, DUPLICATE (no ARTIFACT case came up). A planted problem counts as found if any issue in the output credits it, in any area (rule (a)).
- DUPLICATE: a later issue in another area that points at the same CV text and asks for the same fix as an earlier issue. An issue on different text, or asking for a different fix on the same text (for example, adding a date versus rewriting the description), is not a duplicate.
- Invented fact: a date, number, issuer, employer, tool, model or result offered as CV content with no bracketed placeholder and no explicit condition. Embellished example rewrites that add no fact of these types (for example "to the development team") are listed in the notes but not counted.
- Misquote: a span presented as CV text that is not in the CV text the review received. Letter case, whitespace, quote marks and "..." are ignored.
- Point label (for consistency): the credited key IDs, or a short label for an issue with no credit, used the same way across all six outputs of a CV.

## Totals per label

Recall = planted problems found / planted problems. Precision = (PLANTED + NEUTRAL) / all graded issues.

| Label | Issues | PLANTED | NEUTRAL | WRONG | PADDED | FINE_FLAGGED | DUPLICATE | Recall | Precision | Invented facts | Misquotes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ho_a_01 | 9 | 8 | 0 | 0 | 0 | 0 | 1 | 8/10 | 8/9 | 0 | 0 |
| ho_a_02 | 11 | 9 | 2 | 0 | 0 | 0 | 0 | 9/10 | 11/11 | 1 (borderline) | 0 |
| ho_a_03 | 10 | 9 | 0 | 0 | 0 | 0 | 1 | 8/10 | 9/10 | 0 | 0 |
| ho_a_04 | 11 | 11 | 0 | 0 | 0 | 0 | 0 | 10/10 | 11/11 | 0 | 0 |
| ho_a_05 | 11 | 10 | 0 | 1 | 0 | 0 | 0 | 10/10 | 10/11 | 0 | 0 |
| ho_a_06 | 10 | 8 | 0 | 0 | 0 | 0 | 2 | 8/10 | 8/10 | 0 | 0 |
| ho_b_01 | 10 | 9 | 1 | 0 | 0 | 0 | 0 | 8/10 | 10/10 | 1 | 0 |
| ho_b_02 | 8 | 5 | 3 | 0 | 0 | 0 | 0 | 4/10 | 8/8 | 0 | 0 |
| ho_b_03 | 12 | 7 | 5 | 0 | 0 | 0 | 0 | 6/10 | 12/12 | 1 | 0 |
| ho_b_04 | 12 | 10 | 1 | 0 | 0 | 0 | 1 | 8/10 | 11/12 | 0 | 0 |
| ho_b_05 | 10 | 8 | 2 | 0 | 0 | 0 | 0 | 8/10 | 10/10 | 0 | 0 |
| ho_b_06 | 0 (empty output) | 0 | 0 | 0 | 0 | 0 | 0 | 0/10 | 0/0 | 0 | 0 |
| ho_d_01 | 5 | 5 | 0 | 0 | 0 | 0 | 0 | 4/6 | 5/5 | 0 | 0 |
| ho_d_02 | 8 | 7 | 0 | 0 | 0 | 1 | 0 | 5/6 | 7/8 | 0 | 0 |
| ho_d_03 | 9 | 7 | 0 | 0 | 0 | 1 | 1 | 5/6 | 7/9 | 0 | 0 |
| ho_d_04 | 8 | 8 | 0 | 0 | 0 | 0 | 0 | 5/6 | 8/8 | 0 | 0 |
| ho_d_05 | 7 | 5 | 0 | 0 | 0 | 1 | 1 | 5/6 | 5/7 | 0 | 0 |
| ho_d_06 | 6 | 5 | 0 | 0 | 0 | 1 | 0 | 5/6 | 5/6 | 0 | 0 |
| **All 18** | **157** | **131** | **14** | **1** | **0** | **4** | **7** | **116/156** | **145/157** | **3** | **0** |

Per CV: ho_a recall 53/60 and precision 57/62; ho_b recall 34/60 and precision 51/52; ho_d recall 29/36 and precision 37/43.

To get the decision-rule numbers for a version once the mapping is opened, add its 9 flawed labels: recall = sum of found / 78, precision = sum of (PLANTED + NEUTRAL) / sum of issues, and sum invented facts and misquotes. Then add ho_c from its own grading.

## Planted problems caught, by label

Y = caught, . = missed.

### ho_a (10 planted)

| Problem | 01 | 02 | 03 | 04 | 05 | 06 | Caught |
|---|---|---|---|---|---|---|---|
| A1 no phone number | Y | Y | . | Y | Y | Y | 5/6 |
| A2 vague summary | Y | Y | Y | Y | Y | Y | 6/6 |
| A3 "My Journey So Far" heading | Y | Y | Y | Y | Y | Y | 6/6 |
| A4 oldest-first experience | Y | . | Y | Y | Y | Y | 5/6 |
| A5 "Jun 2025 - Aug 2024" | Y | Y | Y | Y | Y | Y | 6/6 |
| A6 help desk fragments | Y | Y | Y | Y | Y | Y | 6/6 |
| A7 run-on paragraph | Y | Y | Y | Y | Y | Y | 6/6 |
| A8 CI described in plain words | . | Y | . | Y | Y | . | 3/6 |
| A9 tool name spellings | Y | Y | Y | Y | Y | Y | 6/6 |
| A10 certifications inside Skills | . | Y | Y | Y | Y | . | 4/6 |

### ho_b (10 planted)

| Problem | 01 | 02 | 03 | 04 | 05 | 06 | Caught |
|---|---|---|---|---|---|---|---|
| B1 unprofessional email | . | . | Y | Y | Y | . | 3/6 |
| B2 personal details | Y | . | . | Y | Y | . | 3/6 |
| B3 degree with no dates | Y | . | Y | . | . | . | 2/6 |
| B4 overlong (pages, course list, high school) | . | . | . | Y | Y | . | 2/6 |
| B5 "Work Experiance" | Y | Y | Y | Y | . | . | 4/6 |
| B6 mixed date formats | Y | Y | Y | Y | Y | . | 5/6 |
| B7 first-person helping/learning lines | Y | Y | Y | Y | Y | . | 5/6 |
| B8 scrambled skills table | Y | . | . | . | Y | . | 2/6 |
| B9 filler office skills | Y | . | . | Y | Y | . | 3/6 |
| B10 certificates with no name, issuer or date | Y | Y | Y | Y | Y | . | 5/6 |

No output mentions the 3-page length (the "Page N of 3" lines). The two B4 credits come from the high-school block (both) and the course list (ho_b_04).

### ho_d (6 planted)

| Problem | 01 | 02 | 03 | 04 | 05 | 06 | Caught |
|---|---|---|---|---|---|---|---|
| D1 letter-spaced name | . | . | . | . | . | . | 0/6 |
| D2 "over 3 years" against the dates | . | Y | Y | Y | Y | Y | 5/6 |
| D3 no Skills section | Y | Y | Y | Y | Y | Y | 6/6 |
| D4 misspelled tool names | Y | Y | Y | Y | Y | Y | 6/6 |
| D5 intern fragments | Y | Y | Y | Y | Y | Y | 6/6 |
| D6 vague graduation project | Y | Y | Y | Y | Y | Y | 6/6 |

## Each reported issue

Format: area n: verdict (credits). The notes column in `grades_flawed.csv` has the reasons.

**ho_a_01**: cvStructure 1 PLANTED (A1); sectionOrganization 1 PLANTED (A3), 2 PLANTED (A4), 3 PLANTED (A7); keywordUsage 1 PLANTED (A9); readability 1 PLANTED (A2), 2 PLANTED (A6), 3 DUPLICATE (A7: same paragraph and same bullets fix as sectionOrganization 3, with no CI term); contentFormatting 1 PLANTED (A5).

**ho_a_06**: cvStructure 1 PLANTED (A3), 2 PLANTED (A1); sectionOrganization 1 PLANTED (A4); keywordUsage 1 PLANTED (A9), 2 PLANTED (A6); readability 1 PLANTED (A2), 2 DUPLICATE (A6, same lines and fix as keywordUsage 2), 3 PLANTED (A7); contentFormatting 1 PLANTED (A5), 2 DUPLICATE (A7, same paragraph and fix as readability 3).

**ho_a_02**: cvStructure 1 PLANTED (A1); sectionOrganization 1 NEUTRAL (About Me heading, neutral in the key), 2 PLANTED (A3), 3 PLANTED (A10); keywordUsage 1 PLANTED (A9), 2 PLANTED (A8), 3 NEUTRAL (PostgreSQL missing from Skills, neutral in the key); readability 1 PLANTED (A7), 2 PLANTED (A6), 3 PLANTED (A2); contentFormatting 1 PLANTED (A5) + 1 borderline invented date.

**ho_a_04**: cvStructure 1 PLANTED (A1); sectionOrganization 1 PLANTED (A3), 2 PLANTED (A10), 3 PLANTED (A4); keywordUsage 1 PLANTED (A9, Maktabati spellings), 2 PLANTED (A9, different text: JS in Skills and Souq Tracker), 3 PLANTED (A8); readability 1 PLANTED (A7), 2 PLANTED (A2), 3 PLANTED (A6); contentFormatting 1 PLANTED (A5; its date example has an "if" condition, so it is not counted).

**ho_a_03**: cvStructure 1 PLANTED (A10); sectionOrganization 1 PLANTED (A3), 2 PLANTED (A4); keywordUsage 1 PLANTED (A9); readability 1 PLANTED (A2), 2 PLANTED (A6), 3 PLANTED (A7); contentFormatting 1 PLANTED (A5), 2 PLANTED (A9, java script and Postgress: different text from keywordUsage 1), 3 DUPLICATE (A7).

**ho_a_05**: cvStructure 1 PLANTED (A1); sectionOrganization 1 PLANTED (A3), 2 PLANTED (A10), 3 PLANTED (A4); keywordUsage 1 PLANTED (A9), 2 PLANTED (A8), 3 WRONG (says REST endpoints were built in both the Najm and Rimal Tech roles; the Najm text never says REST and only says he worked with backend developers on some endpoints); readability 1 PLANTED (A7), 2 PLANTED (A2, A6), 3 PLANTED (A7, "loads faster" not quantified, a separate fix); contentFormatting 1 PLANTED (A5).

**ho_b_06**: no issues at all (the sheet marks it EMPTY). Counts as an output with no issues.

**ho_b_03**: cvStructure 1 PLANTED (B1), 2 NEUTRAL (move Projects higher, neutral in the key); sectionOrganization 1 PLANTED (B5), 2 NEUTRAL (projects not newest first); keywordUsage 1 NEUTRAL (SIEM missing from Skills), 2 NEUTRAL (CVSS missing from Skills), 3 NEUTRAL (phishing simulation missing from Skills); readability 1 PLANTED (B7), 2 PLANTED (B7, lab line); contentFormatting 1 PLANTED (B6) + 1 invented fact, 2 PLANTED (B3), 3 PLANTED (B10).

**ho_b_05**: cvStructure 1 PLANTED (B2), 2 PLANTED (B4, high school), 3 NEUTRAL (references line); sectionOrganization 1 NEUTRAL (projects order); keywordUsage 1 PLANTED (B10), 2 PLANTED (B9); readability 1 PLANTED (B7); contentFormatting 1 PLANTED (B1), 2 PLANTED (B6), 3 PLANTED (B8).

**ho_b_04**: cvStructure 1 PLANTED (B2), 2 PLANTED (B4, high school), 3 PLANTED (B4, course list); sectionOrganization 1 NEUTRAL (projects order), 2 PLANTED (B10); keywordUsage 1 DUPLICATE (B10, same certificate lines and fix as sectionOrganization 2), 2 PLANTED (B9); readability 1 PLANTED (B7), 2 PLANTED (B7); contentFormatting 1 PLANTED (B6), 2 PLANTED (B1), 3 PLANTED (B5).

**ho_b_01**: cvStructure 1 PLANTED (B2), 2 NEUTRAL (references line); sectionOrganization 1 PLANTED (B10), 2 PLANTED (B8); keywordUsage 1 PLANTED (B9); readability 1 PLANTED (B7), 2 PLANTED (B7); contentFormatting 1 PLANTED (B3) + 1 invented fact, 2 PLANTED (B6), 3 PLANTED (B5).

**ho_b_02**: cvStructure 1 NEUTRAL (move Projects higher); sectionOrganization 1 PLANTED (B5), 2 NEUTRAL (projects order); keywordUsage 1 PLANTED (B7, phishing line in plain words), 2 NEUTRAL (CVSS missing from Skills); readability 1 PLANTED (B7, covers two more lines, so not a duplicate); contentFormatting 1 PLANTED (B6), 2 PLANTED (B10).

**ho_d_02**: cvStructure 1 PLANTED (D3); keywordUsage 1, 2, 3 PLANTED (D4, one misspelling each); readability 1 PLANTED (D5), 2 PLANTED (D6); contentFormatting 1 PLANTED (D2), 2 FINE_FLAGGED (DF3 date "(2025)").

**ho_d_01**: cvStructure 1 PLANTED (D3); keywordUsage 1 PLANTED (D4); readability 1 PLANTED (D5), 2 PLANTED (D6); contentFormatting 1 PLANTED (D6, graduation project has no date; DF3 is used only as the reference).

**ho_d_03**: cvStructure 1 PLANTED (D3); sectionOrganization 1 PLANTED (D6, no date); keywordUsage 1 PLANTED (D4), 2 PLANTED (D6, no technologies); readability 1 PLANTED (D2), 2 PLANTED (D5), 3 PLANTED (D6, broader rewrite); contentFormatting 1 FINE_FLAGGED (DF3 date), 2 DUPLICATE (D5, same fragments and fix as readability 2).

**ho_d_04**: cvStructure 1 PLANTED (D3); keywordUsage 1, 2, 3 PLANTED (D4); readability 1 PLANTED (D2), 2 PLANTED (D5), 3 PLANTED (D6); contentFormatting 1 PLANTED (D6, graduation project has no date).

**ho_d_05**: cvStructure 1 PLANTED (D3); keywordUsage 1 PLANTED (D4), 2 PLANTED (D5); readability 1 DUPLICATE (D5, same fragments and fix as keywordUsage 2), 2 PLANTED (D6); contentFormatting 1 PLANTED (D2), 2 FINE_FLAGGED (DF3 date).

**ho_d_06**: cvStructure 1 PLANTED (D3); keywordUsage 1 PLANTED (D4); readability 1 PLANTED (D5), 2 PLANTED (D6); contentFormatting 1 PLANTED (D2), 2 FINE_FLAGGED (DF3 date).

## Invented facts (3 counted)

| Label | Issue | What was invented |
|---|---|---|
| ho_a_02 | contentFormatting 1 | "for example Jun 2025 - Aug 2025" as the corrected internship dates, with no placeholder or condition. **Borderline**: the key accepts this correction for the A5 hit, but the invented-fact rule only excuses placeholders and explicit conditions. Without it the total is 2. |
| ho_b_01 | contentFormatting 1 | "for example '2021 – 2025'" as the degree dates. The CV gives no education dates. |
| ho_b_03 | contentFormatting 1 | "Summer 2022" rewritten as "Jun 2022 – Aug 2022": the months are not in the CV. |

Not counted, because they are not a counted fact type or are conditional or placeholders: example rewrites that add "and staff" (ho_a_01), "to the development team" (ho_a_02, ho_a_04), "via email and in-person requests" (ho_a_03), "summarizing triaged alerts and findings" (ho_b_01), "troubleshooting VM configuration issues" (ho_b_04), "configuring VirtualBox and Kali Linux environments" (ho_b_05) and "for production systems" (ho_d_01); the example address "hanan.alqahtani@example.com" (ho_b_03, ho_b_04); the Wireshark - Advanced, Nmap - Intermediate pairing (ho_b_01, ho_b_05), which is the natural reading of the scrambled row; and the "if" date example in ho_a_04.

## Misquotes: 0

Every quoted span of CV text was checked by hand. The mechanical "NOT in CV" hits in the issue text are all standard or corrected terms, not quotes of the CV: "Experience" and "Work Experience" (ho_a_01, ho_a_03, ho_a_06), "REST APIs" given as the missing Skills term (ho_a_05), "Kubernetes" as the correct spelling (ho_d_01, ho_d_05), and the format pattern "Mon YYYY - Mon YYYY" (ho_d_03). "Wireshark Nmap Advanced Intermediate" matches the CV once whitespace is ignored.

## Fine items wrongly flagged: 4, all DF3

ho_d_02, ho_d_03, ho_d_05 and ho_d_06 each ask for a month on the home-lab project date "(2025)". The key lists that project as fine (named and dated). No output flags AF1-AF3, BF1-BF3, DF1 or DF2. Several outputs cite those items as good examples.

## Run-to-run consistency

Each label is one run, so consistency per version needs the mapping. Below are the point-label sets and the Jaccard similarity for every pair of labels. Once the mapping is opened, the consistency of a version on a CV is the mean of the 3 pairs among its 3 labels. Two empty sets count as 1.0; an empty set against a non-empty set counts as 0.

### Point sets

| Label | Points |
|---|---|
| ho_a_01 | A1 A2 A3 A4 A5 A6 A7 A9 |
| ho_a_02 | A1 A2 A3 A5 A6 A7 A8 A9 A10, about-me-heading, postgresql-missing-from-skills |
| ho_a_03 | A2 A3 A4 A5 A6 A7 A9 A10 |
| ho_a_04 | A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 |
| ho_a_05 | A1 A2 A3 A4 A5 A6 A7 A8 A9 A10, rest-missing-from-skills |
| ho_a_06 | A1 A2 A3 A4 A5 A6 A7 A9 |
| ho_b_01 | B2 B3 B5 B6 B7 B8 B9 B10, references-line |
| ho_b_02 | B5 B6 B7 B10, projects-move-higher, projects-order, cvss-missing-from-skills |
| ho_b_03 | B1 B3 B5 B6 B7 B10, projects-move-higher, projects-order, siem-missing-from-skills, cvss-missing-from-skills, phishing-sim-missing-from-skills |
| ho_b_04 | B1 B2 B4 B5 B6 B7 B9 B10, projects-order |
| ho_b_05 | B1 B2 B4 B6 B7 B8 B9 B10, references-line, projects-order |
| ho_b_06 | (empty) |
| ho_d_01 | D3 D4 D5 D6 |
| ho_d_02 | D2 D3 D4 D5 D6, df3-date-month |
| ho_d_03 | D2 D3 D4 D5 D6, df3-date-month |
| ho_d_04 | D2 D3 D4 D5 D6 |
| ho_d_05 | D2 D3 D4 D5 D6, df3-date-month |
| ho_d_06 | D2 D3 D4 D5 D6, df3-date-month |

### Pairwise Jaccard

ho_a (mean over all 15 pairs 0.75)

| | 01 | 02 | 03 | 04 | 05 | 06 |
|---|---|---|---|---|---|---|
| 01 | - | 0.58 | 0.78 | 0.80 | 0.73 | 1.00 |
| 02 | 0.58 | - | 0.58 | 0.75 | 0.69 | 0.58 |
| 03 | 0.78 | 0.58 | - | 0.80 | 0.73 | 0.78 |
| 04 | 0.80 | 0.75 | 0.80 | - | 0.91 | 0.80 |
| 05 | 0.73 | 0.69 | 0.73 | 0.91 | - | 0.73 |
| 06 | 1.00 | 0.58 | 0.78 | 0.80 | 0.73 | - |

ho_b (mean over all 15 pairs 0.31; ho_b_06 is empty, so every pair with it is 0)

| | 01 | 02 | 03 | 04 | 05 | 06 |
|---|---|---|---|---|---|---|
| 01 | - | 0.33 | 0.33 | 0.50 | 0.58 | 0.00 |
| 02 | 0.33 | - | 0.64 | 0.45 | 0.31 | 0.00 |
| 03 | 0.33 | 0.64 | - | 0.43 | 0.31 | 0.00 |
| 04 | 0.50 | 0.45 | 0.43 | - | 0.73 | 0.00 |
| 05 | 0.58 | 0.31 | 0.31 | 0.73 | - | 0.00 |
| 06 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | - |

ho_d (mean over all 15 pairs 0.85)

| | 01 | 02 | 03 | 04 | 05 | 06 |
|---|---|---|---|---|---|---|
| 01 | - | 0.67 | 0.67 | 0.80 | 0.67 | 0.67 |
| 02 | 0.67 | - | 1.00 | 0.83 | 1.00 | 1.00 |
| 03 | 0.67 | 1.00 | - | 0.83 | 1.00 | 1.00 |
| 04 | 0.80 | 0.83 | 0.83 | - | 0.83 | 0.83 |
| 05 | 0.67 | 1.00 | 1.00 | 0.83 | - | 1.00 |
| 06 | 0.67 | 1.00 | 1.00 | 0.83 | 1.00 | - |

## Areas at the 3-issue cap (rule (a): a problem cut by the cap counts as missed)

These are only possible cap losses; the outputs do not say whether anything was cut.

- ho_a_01: sectionOrganization is full; A10 is missed, although cvStructure still had room.
- ho_a_02: sectionOrganization is full; A4 (entry order) is missed.
- ho_b_03: keywordUsage and contentFormatting are full; B9 and B8 are missed.
- ho_b_04: cvStructure and contentFormatting are full; B3 and B8 are missed.
- ho_b_05: cvStructure and contentFormatting are full; B3 is missed.
- No ho_d output is full in an area where a missed problem (D1, D2) belongs.

## Judgement calls that could move the numbers

1. **ho_a_05 keywordUsage 3 = WRONG.** It is partly false (REST "in both roles"). As NEUTRAL, ho_a_05 precision would be 11/11 and the overall total 146/157.
2. **ho_a_02 borderline invented date.** As not invented, the invented-fact total is 2.
3. **"Projects not newest first" (ho_b_02, 03, 04, 05) = NEUTRAL.** It is true but minor and not in the key. As PADDED, those four outputs each lose one precision point (overall 141/157).
4. **Same-text, same-fix duplicates** (7 issues: ho_a_01, ho_a_03, ho_a_06 x2, ho_b_04, ho_d_03, ho_d_05). Issues on different text, or asking for a different fix on the same text, were kept as separate PLANTED issues (for example ho_a_04 keywordUsage 1 and 2, ho_a_05 readability 1 and 3, and ho_d_03 with three issues on the graduation project).
5. **D3 wording.** "Tools mentioned only inside bullet points" (ho_d_03, ho_d_04) is loose, since AWS and Terraform also appear in the summary and certifications. The core point is true, so it was credited, not marked WRONG.
6. **DF3 date = FINE_FLAGGED** (4 issues), following the key's fine list. The project is also dated, so the issues do not describe it wrongly.
