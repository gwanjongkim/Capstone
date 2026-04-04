# Firebase Real Project Setup

This app already contains the Firebase integration scaffolding for the A-cut async flow:

- `firebase_core`
- `cloud_firestore`
- `firebase_storage`
- `cloud_functions`
- `lib/services/acut_firebase_service.dart`
- `lib/models/acut_job.dart`
- `lib/models/acut_result.dart`
- `lib/models/acut_result_item.dart`
- `lib/feature/a_cut/a_cut_controller.dart`

What is still required before runtime testing on a real Firebase project:

## 1. Native Firebase App Config

Add the real Firebase app configuration files provided by your Firebase project:

- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

Do not commit placeholder files.

## 2. FlutterFire CLI Output

If your team uses FlutterFire CLI, run:

```bash
cd /home/omen_pc1/pozy_app
flutterfire configure
```

This will generate `lib/firebase_options.dart`.

Current app code uses plain `Firebase.initializeApp()` and can work with the native platform files alone.
If you later switch to `DefaultFirebaseOptions.currentPlatform`, add the generated `firebase_options.dart` file and update initialization accordingly.

## 3. Android Build Wiring

Android Gradle is already prepared for Google Services:

- `android/settings.gradle.kts` includes `com.google.gms.google-services`
- `android/app/build.gradle.kts` applies `com.google.gms.google-services`

## 4. Backend Project Alignment

The app expects the backend Firebase project to expose:

- Firestore collection: `jobs`
- Storage prefix: `acut_jobs/{jobId}/inputs/...`
- Callable Function: `enqueueAcutAnalysis`
- Result files:
  - `app_results.json`
  - `top_k_summary.json`
  - `review_sheet.csv`

## 5. Runtime Assumptions

The current app flow assumes:

- images upload to Firebase Storage first
- a callable Function enqueues the job
- Firestore status transitions are one of:
  - `queued`
  - `running`
  - `done`
  - `error`
- final app rendering comes from compact backend exports

## 6. Security Note

No Firebase Auth flow is implemented yet for the A-cut job path.
Before production rollout, replace development rules with user-scoped rules or add anonymous/authenticated Firebase Auth.
