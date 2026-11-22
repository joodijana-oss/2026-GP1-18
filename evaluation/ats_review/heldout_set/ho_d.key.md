# Answer key: ho_d.txt

> Fact-check changes (checked line by line against ho_d.txt; all 6 problems, 3 fine items and the
> strong parts confirmed; the gap Sep 2025 - Feb 2026 is six months):
> - D2: job time is Mar 2026 - Nov 2026, about 8-9 months; wording adjusted. Also credit D2 when the
>   reviewer says the summary overstates seniority against the dates; pointing out only that the
>   summary drops "Junior" is neutral.
> - D3: tools appear in bullets, projects and certifications, not only bullets; wording adjusted.
> - D5: "Helping with tickets" has a verb form, so the title now says "no action verb".

Career goal: Cloud / DevOps Engineer

A mixed CV: several strong parts and 6 planted problems. A good review finds the problems AND
says what is strong. Area names are generic (Contact, Summary, Headings/Structure, Dates,
Experience content, Projects, Skills/Keywords, Formatting); map them to the ATS review's areas.
A finding is a hit if it points at the quoted text (or clearly the same thing) with the same kind
of reason, in the best area or any acceptable area.

## Planted problems (6)

### D1 - Letter-spaced name that extracts as single letters
- Best area: Formatting. Acceptable: Contact, Structure.
- Exact text: `T U R K I   A L - H A R B I`
- Why: decorative letter spacing makes the name extract as separate characters, so an ATS cannot read the candidate's name. Write it as normal text ("Turki Al-Harbi").

### D2 - Summary claim contradicts the dates
- Best area: Summary. Acceptable: Dates, Experience.
- Exact text: `DevOps Engineer with over 3 years of professional experience` versus `Mar 2026 - Present` and `Jun 2025 - Aug 2025`
- Why: the CV shows about 8-9 months in a job (Mar 2026 - Nov 2026) plus a 3-month internship (about one year in total), and graduation was Jun 2025; "over 3 years" is not supported and will damage trust.
- Also a hit if the reviewer says the summary overstates seniority or experience against the dates. Pointing out only that the summary says "DevOps Engineer" while the title is "Junior DevOps Engineer" is neutral.

### D3 - No Skills section
- Best area: Skills/Keywords. Acceptable: Headings/Structure.
- Exact text: the sections are `Summary`, `Experience`, `Education`, `Projects`, `Certifications`, `Languages`; there is no Skills / Technical Skills section.
- Why: tools appear only scattered inside bullets, the home-lab project and the certifications; an ATS and recruiters expect a dedicated skills list (cloud, containers, IaC, CI/CD, monitoring, scripting) for keyword matching.

### D4 - Misspelled tool names
- Best area: Skills/Keywords. Acceptable: Experience content, Formatting.
- Exact text: `Kubernets`, `Git Hub Actions`, `Terrafrom`
- Why: the correct names are Kubernetes, GitHub Actions and Terraform; misspelled core keywords will not match a job description and look careless.
- A hit needs at least one of the three.

### D5 - Fragment duties with no action verb, scope or result
- Best area: Experience content. Acceptable: Skills/Keywords.
- Exact text: `Monitoring` / `Server stuff and deployments` / `Helping with tickets`
- Why: one- to four-word fragments, informal ("stuff"), no tool, no numbers, no outcome.

### D6 - Vague project entry with no name, date, technologies or outcome
- Best area: Projects. Acceptable: Experience content, Skills/Keywords, Dates.
- Exact text: `Graduation project` / `A system for the university. I worked on the servers part with my team and it was successful.`
- Why: no project title, no year, no technologies, no description of what was built or the candidate's contribution, and "it was successful" is unsupported.

## Fine items (must NOT be flagged)

### DF1 - Strong quantified bullets
- Text: `Set up Prometheus and Grafana alerting that lowered the mean time to detect incidents from 20 minutes to 4 minutes` and `Wrote a Bash script that rotates application logs on 30 Linux servers, freeing 120 GB of disk space`
- Why fine: action verb, standard tools, measured result.
- The three Sadeem bullets containing misspelled tool names are otherwise strong too: flag the spelling only, not the content.

### DF2 - Certifications
- Text: `AWS Certified Solutions Architect - Associate (Amazon Web Services, Feb 2026)` and `HashiCorp Certified: Terraform Associate (HashiCorp, Nov 2025)`
- Why fine: exact names, issuers and dates, in their own section, directly relevant. (The certificate name wraps onto a second line; that is normal PDF wrapping, not a problem.)

### DF3 - Home lab project
- Text: `Self-hosted Git server on a home lab (2025)` / `Deployed Gitea, a container registry and nightly backups on a 3-node K3s cluster using Ansible playbooks and Helm charts`
- Why fine: named, dated, concrete tools and scope. `K3s`, `Gitea`, `EKS`, `VPCs`, `RDS` are correct real names, not misspellings.

## Other strong parts the review should recognise
- Contact block (apart from the name line) is complete: city, phone, email, LinkedIn, GitHub.
- Education block is complete with dates and GPA.
- Experience is newest first with one consistent date format.
- Languages line has a test score.

## Neutral (neither a hit nor a false alarm)
- Noting the 6-month gap between Aug 2025 and Mar 2026.
- Suggesting expansion of abbreviations such as CI/CD or EKS.
- Pointing out only that the summary says "DevOps Engineer" while the current title is "Junior DevOps Engineer".
