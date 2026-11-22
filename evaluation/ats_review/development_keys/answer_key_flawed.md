# Answer key - flawed test CV (CV_Nora_AlHarbi)

## Changes made by the fact checker
All 12 planted problems were checked against CV_Nora_AlHarbi.html and the text extracted from CV_Nora_AlHarbi.pdf (2 pages). Each one is in the text and is a real issue the review can see in plain text. These changes were made to the key only. The CV was not changed.
- P3: CV Structure added as an alternative area, because a contact issue that merges P2 and P3 may be placed there.
- P12: the "2025 - present" contradiction may now be reported in any area. The review's instructions do not tie timeline problems to one area.
- P1: the "why" now explains the problem more accurately. The tools do appear in the text, so the loss comes from the missing Skills section and the misspelled tool names, not from the tools being absent.
- P5: marked as the softest planted problem. Putting a graduation project under Education is a common style, so missing it is a smaller miss.
- P8: "sorts them into groups" may be renamed as text classification or as clustering. Naming a specific model or architecture, or adding an accuracy figure, counts as inventing.
- P8 and P11: added a note on how to credit the lines that both problems share, so the same line is not counted twice.
- P9: the "why" is corrected. Many ATS ignore letter case, so the casing errors (PYTHON, sql, GIT, power bi) are mainly about consistency and looking professional. The spelling variants (sk-learn, Scikit learn) are what break exact keyword matching. Flagging "Pandas" (official form "pandas") is now marked as acceptable.
- P10: exact length added (118 words, one sentence).
- F1: using "2022 - 2026" as one example of year-only dates inside P12 is not a false alarm.
- F2: 420 ms to 270 ms is a 35.7% cut, so "35%" is a slightly low rounding. A review that points this out is neutral, not a false alarm.
- F5: made clear how a "missing Projects / Experience section" comment is scored against P6 and P7.
- New sections: true but unplanned issues (neutral), extraction artifacts (neutral), and a scoring note for issues pushed out by the 3-per-area cap.

## Setup
Career goal: AI / Machine Learning Engineer. Review date: 22 Nov 2026, so the degree finished in 2026 and all jobs are in the past. The review takes today's date from the device clock. If the emulator's date is different, judge "past" and "present" against that date.
The review shows at most 3 issues per area, so not every planted problem can appear. A problem counts as found if it is reported in the expected area or in the alternative area in brackets.
In the extracted text, headings come out in capitals ("EXPERIANCE", "THINGS I BUILT") and bullet marks are dropped, so the review may quote them that way.

## Planted problems (12)

| # | Expected area (alternative) | Exact text in the CV | Why it is an ATS problem |
|---|---|---|---|
| P1 | CV Structure (Keyword Usage) | There is no "Skills" section. Tools appear only inside paragraphs: "PYTHON and Tensorflow", "sql", "Pandas", "sk-learn", "power bi", "jupyter", "GIT", "Pytorch", "ONNX", "Scikit learn". | Many ATS parsers fill the candidate's skills field from a dedicated Skills section, and recruiters scan for one. With the tools buried in paragraphs, and misspelled (P9), they are easy to miss. |
| P2 | CV Structure (Content Formatting) | Contact line: "Buraydah, Saudi Arabia \| nora.alharbi (at) example dot com". There is no phone number (and no LinkedIn or GitHub link). | Contact information is incomplete, so a recruiter cannot call the candidate. |
| P3 | Content Formatting (CV Structure) | "nora.alharbi (at) example dot com" | The email is not in the standard name@domain form, so a parser will not recognise it as an email address. It may be merged with P2 into one contact issue, in either area. |
| P4 | Section Organization | Order of jobs: "Student Lab Assistant 09/2023 - 05/2024", then "Data Science Trainee (Co-op) March 2025 - June 2025", then "Machine Learning Intern 2025 - present" (a summer internship that ended in September 2025). | The jobs are listed oldest first. The most recent and most relevant role should come first. |
| P5 | Section Organization | Under Education: "Graduation project: I made a phone app that looks at a picture of dates and says which kind it is..." | A project sits inside Education even though the CV has a separate projects section, and it is her strongest machine learning project. This is the softest planted problem, because some CV styles do list the graduation project under the degree. |
| P6 | Section Organization (CV Structure) | Heading "Things I Built" | This is a non-standard heading. ATS expect "Projects". |
| P7 | Content Formatting (Section Organization) | Heading "Experiance" | The section heading is misspelled, so a parser may not recognise the Experience section. |
| P8 | Keyword Usage | "taught the computer to tell them apart"; "decides if the writer is happy, angry or neutral"; "guess which deliveries will arrive late"; "a ready-made language model that I adjusted on my own data"; "the thing that reads customer messages and sorts them into groups"; "guess house prices"; titles "Mood Checker" and "Price Guesser". | The work is real machine learning work, but the standard terms are missing: image classification / computer vision, sentiment analysis / NLP / text classification, fine-tuning a pre-trained model, classification, text classification or clustering (for "sorts them into groups"), regression, and model evaluation / comparison. A valid suggestion renames what was done. It must not invent new work, name a specific model or architecture, or add a number that is not in the CV. Suggesting "CNN" is acceptable only as a conditional ("if you used a CNN"). |
| P9 | Keyword Usage (Content Formatting) | "PYTHON" and "python"; "Tensorflow"; "Pytorch" and "pytorch"; "sk-learn" and "Scikit learn"; "sql" (while the certificate says "SQL"); "power bi"; "jupyter"; "GIT" | The tool names are not in their standard forms (Python, TensorFlow, PyTorch, scikit-learn, SQL, Power BI, Jupyter, Git). "sk-learn" and "Scikit learn" can miss exact keyword matches. The casing errors look careless, although many ATS ignore case. A review that also flags "Pandas" (official form "pandas") is acceptable. |
| P10 | Readability | The Data Science Trainee entry is one paragraph made of a single sentence of 118 words, starting "In this co-op I was part of the data team and I was given many different things to do..." (the project descriptions are also paragraphs, not bullets). | A long run-on paragraph instead of short bullet points is hard to scan and to parse. |
| P11 | Readability | "Responsible for the computer lab during evening hours."; "Responsible for helping first-year students with their python homework."; "Duties included various tasks given by the lab supervisor."; "Worked on AI stuff with the research team."; "Helped with the thing that reads customer messages..."; "it got it right most of the time". | These lines describe duties, not actions. They have no strong action verb, use vague wording and give no measurable result (for example, no accuracy figure for the graduation project). |
| P12 | Content Formatting (the "present" part: any area) | Dates: "09/2023 - 05/2024", "March 2025 - June 2025", "2025 - present", "11/2024", "2025". Also "2025 - present" next to "Ten-week summer internship that finished in September 2025." | The CV uses three different date formats. The internship is also marked "present" although the CV says it ended in September 2025. The two parts may be reported as one issue or as two. |

Count by expected area: CV Structure 2, Section Organization 3, Keyword Usage 2, Readability 2, Content Formatting 3.

### Crediting lines that two problems share
- "Worked on AI stuff" and "the thing that reads customer messages" appear in both P8 and P11. Credit the issue to P8 if it asks for the standard technical term, and to P11 if it is about the weak verb or the missing result. Never credit the same reported issue to both.
- A review issue that says the Projects or Experience section is missing, but names "Things I Built" or "Experiance" as the heading to fix, counts as P6 or P7 (see F5).

### Scoring note: the 3-issue cap
If P3, P7 and both parts of P12 all land in Content Formatting, the cap forces one of them out. A planted problem missed only because its area already holds 3 valid planted issues should be marked "crowded out", not "missed".

## Fine items - must NOT be flagged

| # | Text | Why it is fine |
|---|---|---|
| F1 | "Bachelor of Science in Computer Science", "2022 - 2026", "Qassim University, Buraydah \| GPA 4.45 / 5.00" | The degree, university, dates and GPA are complete and correct, and the degree is finished. Only the project text below it is a problem (P5). Saying the degree is still ongoing, or that the degree line is wrong or incomplete, is a false alarm. Citing "2022 - 2026" as one example of year-only dates in P12 is not a false alarm. |
| F2 | "Reduced model response time by 35% (from 420 ms to 270 ms) by converting a Pytorch model to ONNX and batching requests." | It has a strong action verb, concrete numbers and a clear method. It may be mentioned only for the spelling "Pytorch" (P9), never as weak wording or as lacking a result. The exact cut is 35.7%, so a review that notes "35%" is slightly low is neutral, not a false alarm. |
| F3 | Certifications section: "Machine Learning Specialization, Saudi Digital Academy, 2025"; "Deep Learning Fundamentals, Saudi Digital Academy, 2025"; "SQL for Data Analysis, Qassim University Continuing Education, 2024" | The heading is standard, each line has a name, issuer and year, and the newest come first. |
| F4 | "Languages" section: "Arabic (native), English (fluent)" | It is clear and standard. See the extraction artifacts below: the extracted text may run this heading onto the last certificate line. |
| F5 | Summary, Education, Experience, projects and Certifications sections are all present | These sections exist. Saying there are no projects or no work experience at all is a false alarm, and only Skills is truly missing. A comment that the Projects or Experience section is missing because its heading is "Things I Built" or "Experiance", and that names that heading, counts as P6 or P7. |

## True but unplanned issues (neutral: no credit, no penalty)
These are real, but they were not planted. Do not count them as false alarms:
- The Summary is vague and has no keywords ("likes working with data and smart systems").
- First-person writing ("I made", "I was part of", "I gathered").
- No LinkedIn or GitHub link (this also fits under P2).
- "Pandas" is not written in its official lowercase form.
- The email domain looks like a placeholder ("example dot com"). This comes from the test data.

## Extraction artifacts (neutral)
The PDF shows bullets, but the extracted text drops the bullet marks and may join lines together. Do not count these as false alarms, and do not count them as planted problems:
- "The Lab Assistant or Machine Learning Intern points have no bullets" or "they run together as one paragraph". In the extracted text, the three Lab Assistant lines and the four internship lines each come out on one line.
- "The last certificate line and the Languages heading run together" ("...Continuing Education, 2024 LANGUAGES Arabic (native)...").

## Other things that would be mistakes by the review
- Inventing skills, tools or results the CV does not contain (for example, a specific accuracy number, a named model, or tools never mentioned).
- Commenting on fonts, colours, columns or page layout (none of these are visible in the extracted text).
- Reporting the same problem in two areas.
- More than 3 issues in one area, or an issue or suggestion longer than two sentences.
