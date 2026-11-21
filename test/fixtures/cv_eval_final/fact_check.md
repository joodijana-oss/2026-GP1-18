# Fact check of the final test set

Checked on 2026-11-20 against test_set_spec_final.md. Opened only the spec,
careerPaths.json (career goal ids) and the files in this folder.

## How the check was done

- Read all 16 CVs in full and checked every shown, partly and notShown label
  by hand against the CV text.
- Rules used: shown = named or clearly demonstrated (skills listed in the
  skills section count, as the spec says); notShown = really absent; anything
  with weak or indirect evidence = partly.
- Where a skill is described by what was done without naming it, the writer's
  own standard was applied evenly. The writer counts these as shown: SIEM in
  ho_01, OSPF in ho_08 ("link-state routing protocol in a single backbone
  area") and Docker in ho_13.
- A broad certificate (for example Security+) was not treated as proof of
  every topic it covers, only as its own entry. This matches how the writer
  labelled the set.
- Ran a script check on every file: JSON validity and exact formatting, LF
  endings, no BOM, entry keys and order, `source` values, 1 to 4 `alsoCalled`
  names, every evidence string an exact substring of its CV and at most 200
  characters, no name in two categories, all 20 role skills classified,
  partly at most 5, notShown at least 10, at least 2 near misses, held
  certifications written as in the CV, and no forbidden words.

## Label changes (13 changes in 7 files)

| file | skill | change | reason |
|---|---|---|---|
| ho_01 | Network Security | notShown -> partly | The old reason said "nothing in the CV". But she holds Security+ and watched her own traffic for connections to outside addresses (packet diary). That is weak evidence, but it is not none. |
| ho_06 | Mentoring | partly -> shown (source other) | "Coach the first-year training group every Sunday evening and set their practice problems" is clear evidence. The old reason ("a student activity") goes against spec 5.2, which takes evidence from any section. It also matches Mentoring being shown in ho_16. |
| ho_06 | Unit Testing | notShown (near miss) -> partly | The old reason said he "has written no tests of his own". But the CV says he "added a check so it cannot come back unnoticed" after fixing a bug, which reads like a regression test. This is unclear evidence, not absence. |
| ho_10 | Test Planning | notShown (near miss) -> partly | She estimates the testing effort for each story in sprint planning, and she holds ISTQB CTFL, which covers test planning and estimation. That is indirect evidence, not absence. |
| ho_10 | Python | added to notShown | Keeps notShown at 10 after the move above. Python is asked for in QA automation ads and is absent from the CV. |
| ho_13 | Ansible | partly -> shown (source project) | "a set of playbooks installs the packages, creates the users and brings every service back" clearly shows configuration management, which is one of Ansible's other names. "Playbooks" is that tool's own term. This is the same standard the writer used for Docker in this CV and OSPF in ho_08. |
| ho_13 | Cloud Computing | partly -> shown (source project) | The old reason said "Course in progress". But the CV moves a site to AWS and runs a cloud virtual machine workshop. |
| ho_13 | Static Website Hosting | other names changed from [Amazon S3, CDN] to [Static Site Hosting] | The old other names were a vendor service and a separate technology bundled into one entry, which spec 5.2 forbids. |
| ho_13 | Amazon S3 | added to shown (source project) | Split out of the entry above. Evidence: "the pages sit in a storage bucket" (on AWS). |
| ho_13 | Content Delivery Network | added to shown (source project) | Split out of the same entry. Evidence: "behind the content delivery network". |
| ho_14 | Switching | partly -> shown (source project) | He configured four VLANs and a trunk on his own managed switch from the command line, and he replaced access switches at work. The old reason set the home lab aside, but the same home lab supports VLANs, OSPF, BGP and VPN as shown. |
| ho_15 | Hyperparameter Tuning | notShown -> partly | The old reason said "nothing in the CV". But she ran many experiments and "kept each run's settings and scores in a spreadsheet". That is indirect evidence of trying different settings. |
| ho_15 | Apache Spark | added to notShown | Keeps notShown at 10 after the move above. It is absent from the CV. |
| ho_16 | MongoDB | other name "NoSQL" replaced by "Mongo"; nearMiss false -> true; reason rewritten | Redis, a NoSQL store, is in the skills section. With "NoSQL" as another name, this notShown entry contradicted the CV. MongoDB itself is still absent, so the entry is now a near miss. |

Counts after the changes: every CV has at most 5 partly, at least 10
notShown and at least 2 near misses. All 20 role skills are still classified
in every CV.

## Labels checked and kept

These were close calls and were kept as written:

- ho_01 Incident Response: notShown, near miss. She only practises on a
  staged incident.
- ho_02 Security Operations Center Monitoring: partly. He sorts endpoint
  detections, but not in a SOC.
- ho_02 Vulnerability Assessment: notShown, near miss. He does patching but
  no scanning.
- ho_03 A/B Testing: shown. A t-test comparing two groups, and "Hypothesis
  Testing" is one of its other names.
- ho_04 Microsoft Excel: shown. Pivot tables and formulas in a spreadsheet,
  and "Spreadsheets" is one of its other names.
- ho_10 Test Automation and Selenium: partly. Recorded flows only.
- ho_12: all 5 partly entries kept.
- ho_14 Firewall Configuration: notShown, near miss. Router access lists
  only.
- ho_14 Subnetting: partly.
- ho_16 Microservices: shown. He moved notifications into a separate service
  behind a message queue.

## Format problems

The script check found none. Two layout points differ from the spec text and
were left unchanged, because the task set them this way:

- manifest.json has `"set": "final"`. The spec's example has `"heldout"`.
- The files sit directly in this folder, not in a cv_eval_heldout/ subfolder.

## Notes, no change made

- The manifest `changes` list is still empty. These fixes were made before
  hand-over, during the set's own review (spec S6). If hand-over is counted
  from the writer's delivery, copy the table above into `changes` with
  today's date.
- Some `alsoCalled` lists use loose names that could pull a matching name
  onto a different label:
  - roles.json: High Availability [Load Balancing, Auto Scaling],
    Vulnerability Assessment [Vulnerability Management] and Ansible
    [Configuration Management].
  - Label files: Ensemble Methods [Gradient Boosting] in ho_15, Data
    Collection [Data Labeling] in ho_09 and Redis [Caching] in ho_16.
  - None of these contradicts a label, so none was changed.
- A few soft skills that the CVs clearly show have no entry. Examples:
  teaching in ho_09, tutoring in ho_15 and workshops in ho_08. None is a
  role skill, so scoring is not affected.
