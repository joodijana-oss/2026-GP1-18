# Masra (مسرى)

**An AI-powered career intelligence platform for Computing and IT students and fresh graduates in Saudi Arabia.**

Masra analyzes a user's CV against real Saudi job market data, identifies skill gaps, suggests CV improvements, and recommends certifications and opportunities to close those gaps.

> Graduation Project – Group 18 · Information Technology Department, College of Computer and Information Sciences, King Saud University · Supervised by Dr. Hend Albassam

---

## Features (Release 1)

- **User registration and profile:** sign up, log in, log out, password reset, and profile management.
- **AI Career Analysis:** extracts strengths, current skills, education, certifications, projects, and experience from the uploaded CV, compares them with skills requested in Saudi job postings, and identifies skill gaps.
- **CV Improvement Assistant:** reviews the CV in five ATS areas (structure, section organization, keyword usage, readability, and content formatting) and gives suggestions.
- **Certification and Opportunity Recommender:** recommends certifications and opportunities that match the user's skill gaps, career goal, and experience level, and shows why each one fits. Opportunities are ranked with a weighted keyword search (BM25F), and each skill gap is weighted by how often Saudi job postings ask for it.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter, Dart |
| Authentication | Firebase Authentication |
| Database | Cloud Firestore |
| AI | Claude API (Anthropic) |
| Data collection | Python, BeautifulSoup, pandas, JSearch API |

---

## Repository Structure

```
2026-GP1-18/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── config/                   # App settings (admin account)
│   ├── constants/                # Profile options (universities, degrees, career goals)
│   ├── features/                 # Feature screens (career analysis, CV improvement,
│   │                             #   certifications, opportunities, ...)
│   ├── screens/                  # Onboarding, sign-up, log-in, home, explore, profile
│   ├── services/                 # Firebase, AI analysis, and recommender services
│   ├── models/                   # Data models
│   ├── utils/                    # Validators and skill matching
│   ├── widgets/                  # Shared widgets
│   ├── theme/                    # Colors, text styles, and light/dark themes
│   └── assets/
│       ├── data/                 # Career paths, job postings, certifications, opportunities
│       └── images/               # App images
├── test/                         # Unit tests and evaluation test users (fixtures/)
├── evaluation/                   # Saved runs behind the experimental results
├── tools/
│   ├── ats_eval/                 # Evaluation of the CV Improvement (ATS) review
│   ├── gap_eval/                 # Evaluation of the skill gaps and skill matching
│   ├── recommender_eval/         # Offline evaluation of the opportunity recommender
│   ├── upload_certifications/    # Uploads the certifications CSV to Firestore
│   ├── upload_opportunities/     # Uploads the opportunities JSON to Firestore
│   └── welcome_email/            # Email service (Google Apps Script)
├── functions/                    # Firebase Cloud Functions (starter template, no functions yet)
├── hosting/                      # Firebase Hosting (Android App Links file)
├── android/ ios/ web/            # Platform files
├── windows/ macos/ linux/        # Platform files
├── firebase.json                 # Firebase configuration
├── .env.example                  # Template for your local .env file
└── pubspec.yaml                  # Flutter dependencies and assets
```

---

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel) with Dart 3.13.2 or later, as `pubspec.yaml` requires. The app is developed with Flutter 3.47.5.
- Android Studio with an Android emulator, or a physical Android device
- A Firebase project
- [Node.js](https://nodejs.org/), only to upload data to Firestore
- A Claude API key from the [Anthropic Console](https://console.anthropic.com/)

---

## Setup and Run

### 1. Clone the repository

```bash
git clone https://github.com/joodijana-oss/2026-GP1-18.git
cd 2026-GP1-18
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Configure Firebase

1. Create a project in the [Firebase Console](https://console.firebase.google.com/).
2. Add an Android app and download `google-services.json`.
3. Place the file in `android/app/`.
4. Enable **Email/Password** sign-in in Firebase Authentication.
5. Create a Cloud Firestore database.
6. In **Authentication → Settings → Password policy**, require at least 8 characters with an uppercase letter, a lowercase letter, a number, and a special character, so Firebase enforces the same rules as the app.
7. Password reset links open the app only when your signing key is listed in `hosting/public/.well-known/assetlinks.json`. Get your SHA-256 fingerprint with `cd android && ./gradlew signingReport`, add it to `sha256_cert_fingerprints`, then deploy with `firebase deploy --only hosting`.

### 4. Run the app with the Claude API key

The API key is **not stored in the repository**. It is read from a local `.env` file that git ignores.

1. Copy `.env.example` to `.env`.
2. Put your key after `ANTHROPIC_API_KEY=`.
3. Optional: put the web app URL of the email script (`tools/welcome_email/Code.gs`) after `WELCOME_EMAIL_URL=`. The script sends the welcome email and a Masra-designed password reset email. If you leave it empty, no welcome email is sent and Firebase sends its own password reset email.
4. Run the app:

```bash
flutter run --dart-define-from-file=.env
```

In VS Code, pressing F5 does the same (see `.vscode/launch.json`).

To pass the key directly instead of using a file:

```bash
flutter run --dart-define=ANTHROPIC_API_KEY=your_api_key_here
```

> Never commit `.env` or upload it through the GitHub website ("Add files via upload" ignores `.gitignore`).

---

## Tests and Evaluation

Run the static checks and the unit tests:

```bash
flutter analyze
flutter test
```

The opportunity recommender has an offline evaluation. It ranks the bundled opportunities for labelled test users and compares the current recommender with the first version (Precision@5, nDCG@10, and gap coverage):

```bash
dart run tools/recommender_eval/evaluate_recommender.dart --personas test/fixtures/opportunity_eval_personas_heldout.json
```

The held-out file has 8 career paths that were not used while the ranking was designed, so use its numbers. Without `--personas`, the script uses the development set. Add `--ablation` to see the effect of each technique, and `--top` to print the first 10 results for each test user.

The skill gaps of the career analysis have their own evaluation. It runs the analysis steps of the app on test CVs with real AI requests (they use API credit), so start with `--dry-run`, which prints how many requests a run would send. The tool reads the API key from `.env` itself and never prints it:

```bash
dart run tools/gap_eval/evaluate_gaps.dart --set test/fixtures/cv_eval_dev --arms G0E0,G1E1 --runs 3 --dry-run
dart run tools/gap_eval/evaluate_gaps.dart --set test/fixtures/cv_eval_dev --arms G0E0,G1E1 --runs 3
dart run tools/gap_eval/evaluate_gaps.dart --score build/gap_eval/<run folder>
```

It compares the original analysis (`G0E0`: gaps from two lists of skill names) with the one the app runs (`G1E1`: single-skill market names, and every market skill checked against a quote from the CV). Without `--arms`, it also runs `G0E1` (single-skill names only) and `G2E1` (an extra request checks each gap, an approach that lost), which raises the requests on the development set from about 90 to about 144. The development CVs in `test/fixtures/cv_eval_dev` may be used while building; decisions are taken on a held-out set that nobody reads while building.

The saved runs behind the experimental results are in `evaluation/` (see `evaluation/README.md`). To check them all again, with no AI requests and no cost:

```bash
dart run tools/rerun_evaluations.dart
```

It scores the saved runs again, compares the results with the saved ones, and writes a dated log to `evaluation/logs/`.

---

## Upload Data to Firestore (Optional)

The app reads certifications and opportunities from Firestore. If Firestore cannot be reached or has no data yet, it uses the bundled files in `lib/assets/data/`. To upload a new version of the data:

```bash
cd tools/upload_opportunities
npm install
npm run dry-run
node upload_opportunities.js --key path/to/service-account.json
```

`tools/upload_certifications` works the same way. Download the service account key from **Firebase Console → Project settings → Service accounts**, and never commit it.

---

## Security Note

The Claude API key is passed at build time (`--dart-define`) so that it never appears in the source code or the repository. Because such values are still compiled into the app package, this setup is intended for development and testing. Moving Claude API calls to a server-side component (such as Firebase Cloud Functions) is planned before public deployment.

---

## Team

| Name | Role |
|---|---|
| Shatha Bin Mana | Team Leader, Developer |
| Dalal Almuqbil | Developer |
| Jood Alkhneen | Developer |
| Jana Alhumaidi | Developer |

**Supervisor:** Dr. Hend Albassam

---

## Project Management

Sprints and the product backlog are managed in Jira: `2026-1st-gp18.atlassian.net` (project `2026-GP1-18`).
