# Answer key: ho_a.txt

> Fact-check changes (checked line by line against ho_a.txt; all 10 problems and 3 fine items confirmed):
> - A5: the intended range could be Jun 2024 - Aug 2024 (a summer internship right after the May 2024
>   help-desk job) as well as Jun 2025 - Aug 2025. Either correction, or none, counts; the hit is for
>   saying the end date comes before the start date. A4 holds under both readings.
> - A9: added that "JavaScript" never appears in its standard spelling anywhere (Skills has only `JS`).
> - Added neutral items: the `Languages:` label inside Skills clashing with the spoken `Languages`
>   heading; Education placed above Experience; tools used in bullets (PostgreSQL, REST) missing from Skills.

Career goal: Software Engineer

Area names below are generic (Contact, Summary, Headings/Structure, Dates, Experience content,
Skills/Keywords, Formatting). Map them to whatever areas the ATS review uses. A finding counts as
a hit if it points at the quoted text (or clearly the same thing) and gives the same kind of reason,
in the best area or any acceptable area.

## Planted problems (10)

### A1 - Missing phone number
- Best area: Contact. Acceptable: Structure, Formatting.
- Exact text: the header block is only
  `Faisal Al-Dossari` / `Dammam, Saudi Arabia` / `faisal.aldossari@example.com` / `github.com/faisal-aldossari-dev`
- Why: no phone number anywhere in the CV; recruiters and ATS contact fields expect one.
  (A missing LinkedIn link is NOT the planted problem; mentioning it alone is not a hit.)

### A2 - Vague, generic summary
- Best area: Summary. Acceptable: Experience content, Skills/Keywords.
- Exact text: `Hard-working team player with excellent skills and a great passion for technology. I am a fast learner who always gives 100% and I am looking for a good opportunity in a good company where I can grow.`
- Why: only soft cliches; no role, no technologies, no evidence, nothing tied to software engineering.
  The heading `About Me` is slightly informal; flagging the heading alone is not a hit for A2 and is not a false alarm either (neutral).

### A3 - Unusual heading for work experience
- Best area: Headings/Structure. Acceptable: Formatting, Experience.
- Exact text: `My Journey So Far`
- Why: an ATS looks for "Experience" / "Work Experience"; this heading may not be recognised, so the jobs under it may not be parsed as employment.

### A4 - Experience in oldest-first order
- Best area: Headings/Structure. Acceptable: Experience, Dates, Formatting.
- Exact text: order of entries: `Campus IT Help Desk ... Sep 2023 - May 2024`, then `Najm Logistics Solutions ... Software Engineering Intern`, then `Rimal Tech ... Oct 2025 - Present` last.
- Why: the current and most relevant job is at the bottom; the standard is reverse chronological (newest first).

### A5 - Impossible date range
- Best area: Dates. Acceptable: Experience, Structure.
- Exact text: `Jun 2025 - Aug 2024`
- Why: the end date is before the start date. The intended range is probably Jun 2025 - Aug 2025 (after graduation, before the Oct 2025 job) or Jun 2024 - Aug 2024 (summer after the help-desk job); a reviewer suggesting either, or no correction, still scores the hit.

### A6 - Duty fragments with no verb and no result
- Best area: Experience content. Acceptable: Formatting, Skills/Keywords.
- Exact text: `Responsible for bugs` / `Meetings with team` / `Tickets and emails from students`
- Why: noun fragments, no action verb, no scope, no outcome; says nothing about what he did.

### A7 - One long run-on paragraph instead of bullets
- Best area: Experience content. Acceptable: Formatting, Structure.
- Exact text: the paragraph starting `During my internship I was placed in the shipment tracking team where I was working on many different things` and ending `before the code reaches the customers.`
- Why: a single 9-line sentence, first person, no separate achievements, no numbers ("loads faster" is not quantified); hard to scan and hard to parse.

### A8 - Plain-word description of work that has a standard term
- Best area: Skills/Keywords. Acceptable: Experience content.
- Exact text: `I made the app check itself automatically every time someone saved new code so that mistakes are found early`
- Why: this is continuous integration / an automated test pipeline (CI); the standard keyword and the tool used are missing, so keyword matching will not find it.
- Note: a reviewer may report A7 and A8 as one finding; credit both only if both ideas (paragraph format AND missing standard term) are stated.

### A9 - Inconsistent and misspelled technology names
- Best area: Skills/Keywords. Acceptable: Formatting, Projects/Experience content.
- Exact text: `Reactjs, java script, Postgress` and `Javascript and React.JS` and `JS` (also `PostgreSQL` spelled correctly in one place, `React` in Skills).
- Why: the same tools are written several ways and "Postgress" is misspelled; the correct forms are JavaScript, React, PostgreSQL. "JavaScript" is never written in its standard form anywhere in the CV (the Skills section has only `JS`). Exact keyword matching can miss them.
- A hit needs at least one of: the Postgress misspelling, or the inconsistent JavaScript / React spellings.

### A10 - Certifications placed inside the Skills section
- Best area: Headings/Structure. Acceptable: Skills/Keywords, Certifications.
- Exact text: `AWS Certified Cloud Practitioner (Amazon Web Services, 2025)` and `Scrum Fundamentals Certified (SCRUMstudy, 2024)` under `Skills`
- Why: certifications belong in their own "Certifications" section; inside Skills they may be parsed as skill names or missed.

## Fine items (must NOT be flagged)

### AF1 - Education block
- Text: `Bachelor of Science in Software Engineering` / `Eastern Gulf University, Dammam` / `Sep 2021 - Jun 2025` / `GPA: 4.52 / 5.00`
- Why fine: standard heading, full degree name, institution, dates and GPA with scale.

### AF2 - Quantified achievement bullet
- Text: `Reduced the average response time of the product search page from 1.9 s to 0.7 s by adding database indexes and caching`
- Why fine: action verb, measurable result, method stated.

### AF3 - Languages line
- Text: `Arabic (native), English (IELTS 7.0)`
- Why fine: standard heading, proficiency given with a recognised test score.

## Notes for the judge
- `Oct 2025 - Present` is fine (today is Nov 2026).
- The Rimal Tech bullets and the two project descriptions (apart from the tool-name spellings) are sound.
- Flagging the missing LinkedIn URL or the informal `About Me` heading is neutral: not a planted hit, not a false alarm.
- Also neutral: noting that the `Languages:` label for programming languages inside Skills could be confused with the spoken-language `Languages` heading (this does not count against AF3); suggesting Experience move above Education; noting that PostgreSQL or REST appear in bullets but not in the Skills list.
