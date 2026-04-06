# Firebase Real Project Setup

This app already contains the Firebase integration scaffolding for the A-cut async flow:

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `firebase_storage`
- `cloud_functions`
- `lib/services/acut_firebase_service.dart`
- `lib/services/firebase_auth_service.dart`
- `lib/models/acut_job.dart`
- `lib/models/acut_result.dart`
- `lib/models/acut_result_item.dart`
- `lib/feature/a_cut/a_cut_controller.dart`
- `lib/firebase_bootstrap.dart`
- `lib/firebase_options.dart` placeholder stub

What is still required before runtime testing on a real Firebase project:

## 1. Create or Connect the Real Firebase Project

You still need the actual Firebase project used by the backend pipeline.

Minimum services:

- Firebase Authentication
- Cloud Firestore
- Cloud Storage
- Cloud Functions

## 2. Add Real Firebase App Config Files

Do not keep the placeholder-only state for runtime testing.

Add the real files:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

If you use FlutterFire-generated options, also run:

```bash
flutterfire configure
```

This will generate `lib/firebase_options.dart`.

Current app code first tries `DefaultFirebaseOptions.currentPlatform`, then falls
back to native platform files when the generated file is still the placeholder.
That means the failure mode is explicit today, and later real project insertion
works as soon as you add the native files and/or replace the placeholder with the
real `flutterfire configure` output.

## 3. Android Build Wiring

The Gradle plugin is already wired in the app codebase.

Once the real Firebase project files are added, Android should be able to read:

- `android/app/google-services.json`

## 4. Backend Contract Expected by the Flutter App

The app expects the backend Firebase project to expose:

- Firestore collection: `jobs`
- Storage prefix: `acut_jobs/{jobId}/inputs/...`
- Callable Function: `enqueueAcutAnalysis`
- Callable Function: `cancelAcutAnalysis`
- Result files:
  - `app_results.json`
  - `top_k_summary.json`
  - optional `review_sheet.csv`

## 5. Auth / Rules Assumption

The current app flow assumes:

- Firebase Anonymous Auth is enabled in Firebase Authentication
- the app signs in anonymously before upload, enqueue, watch, and result fetch
- images upload to Firebase Storage first
- a callable Function enqueues the job
- Firestore status transitions are one of:
  - `queued`
  - `running`
  - `cancelling`
  - `cancelled`
  - `done`
  - `error`
- final app rendering comes from compact backend exports

## 6. Security Note

The app now uses Firebase Anonymous Auth for the A-cut path.
Before production rollout, decide whether to keep anonymous auth or upgrade to a
stronger sign-in method such as Google / Apple / email.

The backend rules assume:

- `jobs/{jobId}.userId == request.auth.uid`
- input uploads carry Storage metadata:
  - `ownerUid == request.auth.uid`
  - `jobId == {jobId}`

## 7. Expected Failure Mode Before Config Is Added

If you launch the app before adding the real Firebase project files, Firebase
initialization is expected to fail cleanly. The A-cut screen should show a
clear message telling you to add:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart` from `flutterfire configure` when that flow is used
