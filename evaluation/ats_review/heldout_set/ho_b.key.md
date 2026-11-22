# Answer key: ho_b.txt

> Fact-check changes (checked line by line against ho_b.txt; all 10 problems and 3 fine items confirmed,
> the course list really has 29 entries, and the three date formats are as quoted):
> - B2: made explicit that flagging `Nationality: Saudi` on its own is neutral.
> - B4: noted that the 3-page length is visible in the text only through the `Page N of 3` lines.
> - Added neutral items: suggesting the strong Projects section move higher (it sits last, on page 3),
>   and flagging the `Curriculum Vitae` title line on its own.

Career goal: Cybersecurity Analyst

Area names are generic (Contact, Summary, Headings/Structure, Dates, Education, Experience content,
Skills/Keywords, Certifications, Formatting, Length). Map them to the areas the ATS review uses.
A finding is a hit if it points at the quoted text (or clearly the same thing) with the same kind of
reason, in the best area or any acceptable area.

## Planted problems (10)

### B1 - Unprofessional email address
- Best area: Contact. Acceptable: Formatting, Structure.
- Exact text: `h4ck3r_queen99@example.com`
- Why: a nickname address with leetspeak looks unprofessional (worse for a security role); use a name-based address.

### B2 - Unnecessary personal details
- Best area: Contact. Acceptable: Structure, Formatting, Length.
- Exact text: `Personal Details` / `Date of Birth: 14 March 2002` / `Marital Status: Single` / `Nationality: Saudi` / `Gender: Female`
- Why: date of birth, marital status and gender are not needed, invite bias and use space. (Nationality alone can be kept in the Saudi market; the hit is for date of birth / marital status / gender or the section as a whole. Flagging only the nationality line is neutral.)

### B3 - Education entry with no dates
- Best area: Education. Acceptable: Dates, Structure.
- Exact text: `Bachelor of Science in Cybersecurity` / `Najd University of Technology, Riyadh` / `GPA: 4.38 / 5.00`
- Why: no start or graduation date, so an ATS cannot tell when or whether the degree was completed.

### B4 - Overlong CV padded with irrelevant content
- Best area: Length. Acceptable: Structure, Education, Formatting.
- Exact text: `Page 1 of 3` ... `Page 3 of 3`; the `Courses Studied` list of 29 courses (`Introduction to Computing, Programming 1, ... Graduation Project 2`); the `High School` block (`Al-Noor Secondary School for Girls ... reading competition in grade 10`).
- Why: three pages for a fresh graduate; the full course list (including general courses) and high-school details add length without value. One page (two at most) with only relevant coursework is expected.
- In plain text the page count is shown only by the `Page 1 of 3` / `Page 2 of 3` / `Page 3 of 3` lines; a reviewer citing them is enough for the length part.
- A hit needs at least one of: the 3-page length, the full course list, or the high-school block. The repeated `Curriculum Vitae ... Page N of 3` header lines appearing in the text may be reported with this or as a formatting issue; either way it counts toward B4.

### B5 - Misspelled section heading
- Best area: Headings/Structure. Acceptable: Formatting, Experience.
- Exact text: `Work Experiance`
- Why: misspelled standard heading ("Experience"); an ATS matching on heading names may not recognise the section, and it looks careless.

### B6 - Inconsistent date formats
- Best area: Dates. Acceptable: Formatting, Experience.
- Exact text: `03/2025 – 06/2025`, `2023-09 to Dec 23`, `Summer 2022`
- Why: three different date styles, one with no months at all ("Summer 2022") and one mixing two styles in a single range; ATS date parsing is unreliable and it looks inconsistent. Use one format such as "Mar 2025 - Jun 2025".

### B7 - First-person, passive "helping / learning" bullets with no result
- Best area: Experience content. Acceptable: Skills/Keywords.
- Exact text: `I was helping my supervisor to look at the phishing emails that the employees reported` / `I learned how the team writes the weekly report and I was sometimes writing parts of it` / `I was answering the students questions during the lab`
- Why: written in first person, describe assisting or learning rather than what she did, no action verb, no numbers, no outcome.

### B8 - Skills table that extracted with scrambled columns
- Best area: Formatting. Acceptable: Skills/Keywords, Structure.
- Exact text: `Tool            Level           Tool            Level` / `Wireshark       Nmap            Advanced        Intermediate` / `Splunk          Burp Suite      Intermediate    Beginner` / `Metasploit      Nessus          Beginner        Intermediate` / `Kali Linux      Python          Advanced        Intermediate`
- Why: a multi-column table; the extracted text no longer pairs each tool with its level, so the content is unreadable to a parser. Use a simple one-column list.

### B9 - Irrelevant / outdated filler skills
- Best area: Skills/Keywords. Acceptable: Length, Structure.
- Exact text: `Microsoft Word, Typing (45 WPM), Internet browsing, Email, Windows XP, Printing and scanning`
- Why: basic or obsolete office skills that carry no weight for a Cybersecurity Analyst and dilute the relevant keywords.

### B10 - Certification entries with no name, issuer or date
- Best area: Certifications. Acceptable: Skills/Keywords, Structure.
- Exact text: `Security course certificate` / `Networking certificate - completed`
- Why: no certificate name, issuing body or date; cannot be verified or keyword-matched.

## Fine items (must NOT be flagged)

### BF1 - Properly written certification
- Text: `CompTIA Security+ (CompTIA, issued May 2025)`
- Why fine: exact name, issuer and date.

### BF2 - Strong quantified bullets
- Text: `Triaged an average of 40 SIEM alerts per shift in Splunk and escalated confirmed incidents to Tier 2 within the 15-minute SLA` and `Wrote 5 Splunk detection rules for brute-force logins, cutting false positives on that use case by 30%`
- Why fine: action verb, standard terms (SIEM, SOC tiers, SLA), numbers, result.

### BF3 - Phone number and LinkedIn link
- Text: `+966 55 010 2233` and `linkedin.com/in/hanan-alqahtani-sec`
- Why fine: international format phone and a clean profile URL.

## Notes for the judge
- The `Profile` paragraph is short, specific and names the target role: fine.
- The two `Projects` entries are strong.
- `References available upon request` is unneeded filler; flagging it is neutral (not a planted hit, not a false alarm).
- The experience order is newest first: fine.
- Neutral: suggesting the Projects section move higher (the two strongest entries sit last, on page 3); flagging the `Curriculum Vitae` title line on its own (if tied to the repeated page headers or length, it counts toward B4).
