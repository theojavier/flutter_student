# my_flutter_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Face identity check

The exam and profile gaze-calibration flows ask for consent, run face matching
in the browser/WebView, and require a match before calibration or exam entry.
The first successful check stores one reference JPEG at
`face-references/{Firebase Auth UID}/reference.jpg`; later camera frames are
compared on-device and are not uploaded. The first selfie only establishes the
account's baseline—it does not prove the student's official identity.

Deploy with `firebase deploy --only storage,hosting` before enabling this flow.
The rules
allow a signed-in student to read their own reference and create it once, but
not replace or delete it; an administrator must handle authorized deletion.
The app's face-match threshold is an initial default and should be validated
with representative cameras, lighting, and students before using this as an
access-control decision. Matching runs in client code and is not tamper-proof;
use supervised enrollment and server-side checks for high-assurance identity
verification. Confirm the school's consent and biometric-data retention policy
before collecting student photos.
