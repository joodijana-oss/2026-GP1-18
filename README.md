# Masra (مسرى)

**An AI-powered career intelligence platform for Computing and IT students and fresh graduates in Saudi Arabia.**

Masra analyzes a user's CV against real Saudi job market data, identifies skill gaps, suggests CV improvements, and recommends certifications and opportunities to close those gaps.

> Graduation Project – Group 18 · Information Technology Department, College of Computer and Information Sciences, King Saud University · Supervised by Dr. Hend Albassam

---

## Features (Release 1)

- **User registration and profile:** sign up, log in, log out, password reset, and profile management.
- **AI Career Analysis:** extracts strengths, current skills, education, certifications, projects, and experience from the uploaded CV, compares them with skills requested in Saudi job postings, and identifies skill gaps.
- **CV Improvement Assistant:** reviews the CV in five ATS areas (structure, section organization, keyword usage, readability, and content formatting) and gives suggestions.
- **Certification and Opportunity Recommender:** recommends certifications and opportunities that match the user's skill gaps and career goal.

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
├── lib/                 # Flutter application source code
│   ├── screens/         # UI screens
│   ├── services/        # Firebase and Claude API services
│   └── models/          # Data models
├── assets/              # Images and bundled data files
├── android/             # Android platform files
└── pubspec.yaml         # Flutter dependencies
```

> Update this tree to match the actual folders in the repository.

---

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) [version]
- Android Studio with an Android emulator, or a physical Android device
- A Firebase project
- A Claude API key from the [Anthropic Console](https://console.anthropic.com/)

---

## Setup and Run

### 1. Clone the repository

```bash
git clone https://github.com/Shatha-1/2026-GP1-18.git
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

### 4. Run the app with the Claude API key

The API key is **not stored in the repository**. Pass it at run time:

```bash
flutter run --dart-define=CLAUDE_API_KEY=your_api_key_here
```

> Do not commit the API key or paste it into any file in the repository.

---

## Security Note

The Claude API key is passed through `--dart-define` so that it never appears in the source code or the repository. Because such values are still compiled into the app package, this setup is intended for development and testing. Moving Claude API calls to a server-side component (such as Firebase Cloud Functions) is planned before public deployment.

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
