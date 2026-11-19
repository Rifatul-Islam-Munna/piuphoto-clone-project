# mobileapp

A new Flutter project.

## Guest QR website

Set `PUBLIC_APP_URL=https://airpix.app` in `mobileapp/.env` to the public
frontend website. `API_URL` stays pointed at the backend. Guest QR codes use
`https://airpix.app/#/event/<eventId>?v=1&face=1`, which opens in a phone browser
without installing AirPix and remains scannable inside AirPix.

Release the updated mobile app, then generate and share fresh guest QR codes.
Previously shared `airpix://` codes still work in the in-app scanner, but cannot
be repaired for external browsers by changing backend environment variables.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
