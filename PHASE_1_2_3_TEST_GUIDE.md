# Phase 1-3 Simple Test Guide

Use this file to test the features added to the project.

## Provider setup

The old notification webhook variables are **not used**:
- `EMAIL_NOTIFICATION_WEBHOOK_URL`
- `WHATSAPP_NOTIFICATION_WEBHOOK_URL`
- `STORE_DELIVERY_WEBHOOK_URL`

AI review/search metadata now uses the same FAL credentials as the AI workflow. There is no `VISION_ANALYSIS_ENDPOINT_URL` dependency.

Keep one of these configured:
```env
FAL_KEY=your-fal-key
# FAL_API_KEY is also accepted for the existing setup.
```

Face recognition is separate from general FAL image analysis. Keep your existing `FACE_DETECTION_ENDPOINT_URL` because it creates the face embeddings used with Qdrant.

`STRIPE_WEBHOOK_SECRET` is optional. If it is blank, payment success/refunds are checked securely with `STRIPE_SECRET_KEY` and the Stripe API.

## Email and WhatsApp setup

Both providers are optional. If SMTP and WhatsApp credentials are blank, uploads, AI, galleries, personal face galleries, Stripe checkout, secure downloads and the rest of the app continue normally; only that external notification channel is skipped.

For email, add normal SMTP credentials to `backend/.env`:
```env
SMTP_HOST=smtp.your-provider.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=you@example.com
SMTP_PASS=your-smtp-password
SMTP_FROM=you@example.com
SMTP_FROM_NAME=Airpix
```

These values come from your email provider. Gmail/Google Workspace, Outlook, Mailgun, SES, Resend SMTP and similar providers can supply SMTP credentials.

For WhatsApp, use Meta WhatsApp Cloud API credentials:
```env
WHATSAPP_ACCESS_TOKEN=
WHATSAPP_PHONE_NUMBER_ID=
WHATSAPP_GRAPH_API_VERSION=v23.0
WHATSAPP_TEMPLATE_NAME=
WHATSAPP_TEMPLATE_LANGUAGE=en_US
```

Get the access token and phone-number ID from the Meta Developers / WhatsApp Cloud API setup for your business app. For proactive production messages, use an approved WhatsApp template.

Set the public frontend address used inside secure links:
```env
PUBLIC_APP_URL=https://your-domain.com
```

Restart the backend after editing `.env`.

## Phase 1 - Photographer + Event Planner + live transfer

### 1. Workspaces and team
1. Login as Event Planner and open `/planner/dashboard`.
2. Create an event and two categories/albums.
3. Invite two Photographers plus a Retoucher/Reviewer.
4. Assign the photographers to different categories.
5. Confirm there is no photographer-seat limit.
6. Login as a Photographer and confirm `/photographer/dashboard` is photographer-only.
7. If one account has both roles, test the workspace switcher.

### 2. Camera transfer
1. In the mobile app choose the event/category.
2. Connect the camera using your existing OTG method and take photos.
3. Repeat using your existing wireless method.
4. Confirm the live list shows filename, thumbnail/icon, camera/source, category, progress and status.
5. Test the `All`, `Uploaded`, and `Not uploaded` filters.
6. Turn internet off, capture more files, turn it back on and confirm retry resumes.
7. Confirm completed transfer history stays visible.
8. Retry the same failed capture and confirm it does not create a duplicate server photo.

### 3. Multi-photographer + web console
1. Upload at the same time from two photographer accounts.
2. Use different categories and different camera/device sources.
3. Open `/planner/live/<eventId>` while uploads are running.
4. Confirm the page updates without refresh and shows photographer, category, camera, progress, speed and failures.
5. Move selected photos to another category from `/planner/gallery` and confirm the change.

**Phase 1 passes when:** both photographers can upload concurrently, offline retry works, no duplicate appears, the planner sees live status, and OTG/wireless connection behavior is unchanged.

## Phase 2 - AI + live gallery + privacy + face delivery

### 1. AI Enhance / Review / Search
1. Open `/planner/gallery` and choose an event.
2. Select photos and test Colour, Skin, Facial, Body and Vehicle Privacy enhancement presets.
3. Confirm originals remain unchanged and enhanced versions can be compared.
4. Run AI Review and check quality score, blur/duplicate flags and reviewer override.
5. Search a visible number, a scene/object phrase and an outfit description.
6. Select `Face`, upload a selfie/face photo and confirm matching event photos are returned.
7. Confirm FAL jobs run using `FAL_KEY`/`FAL_API_KEY`; no separate vision-analysis URL is required.

### 2. Live gallery + privacy + branding
1. Open `/planner/event/<eventId>/experience`.
2. Test Public, Private, Password and Facial privacy modes.
3. Verify the wrong gallery password fails and the correct password unlocks it.
4. Publish/hide photos from `/planner/gallery` and confirm the public gallery updates live.
5. Test `Hide non-matches` and `Blur non-matches`.
6. Change logo, cover, watermark, colors, footer/sponsor and white-label settings.
7. Test the gallery slug at `/#/g/<slug>`.
8. If using a custom domain, point DNS/reverse proxy to this frontend and verify the configured event resolves.
### 3. Personal face gallery + notifications
1. Enable face search and guest notifications for the event.
2. Open the public gallery and register a selfie with consent.
3. Add an email and/or WhatsApp number and enable that preference.
4. Upload a new event photo containing that guest.
5. Confirm the match appears automatically in the same personal gallery.
6. Wait for the notification batch window and confirm one grouped secure link is sent.
7. Disable one notification preference and verify that channel stops sending.
8. Delete the guest registration and confirm the personal-gallery token no longer works.

**Phase 2 passes when:** FAL AI features work, face matching is event-scoped, privacy is enforced server-side, the gallery updates live, and SMTP/WhatsApp send secure links when configured while remaining cleanly disabled when credentials are blank.

## Phase 3 - Retouch + desktop + store + analytics + API

### 1. Retouch workflow
1. Add Retoucher and Reviewer event members.
2. Open `/retouch`.
3. Filter by event, category, photographer, status and date.
4. Assign selected jobs to a retoucher.
5. Confirm new retouch/status events appear live without waiting for a manual refresh.
6. Start retouching and upload an edited version.
7. As Reviewer, compare original/current and Approve or Reject.
8. Test bulk approve/reject and optional bypass-review/auto-publish settings.

### 2. Desktop retoucher
From `desktop-retoucher`, copy `airpix-desktop.example.json` to `airpix-desktop.json` and add the retoucher JWT, event ID and folders.`r`n`r`nRun:
```bat
npm start
```

1. Assign a photo and confirm it auto-downloads.
2. Stop during a large download, restart, and confirm the `.part` file resumes.
3. Confirm `/retouch` shows the desktop device online and its last-seen time.
4. Export an edit as `<jobId>__edited.jpg`, `<jobId>__retouched.tif`, or `<jobId>__export.png`.
5. Confirm the edited version uploads automatically.
6. Export identical bytes again and confirm checksum tracking prevents a duplicate version.

### 3. Online store - webhook secret is optional
1. Open `/planner/store`, enable the store and choose sale photos/categories.
2. Open `/#/store/<eventId>`, select photos and pay with Stripe Checkout.
3. Confirm the success page verifies the Checkout Session directly with Stripe.
4. Leave `STRIPE_WEBHOOK_SECRET` empty and confirm the payment still completes.
5. Close the browser before redirect after another payment; within the reconciliation interval the backend should still mark it paid.
6. If SMTP/WhatsApp is configured, confirm the buyer receives the secure link on those channels. With both blank, confirm checkout and secure browser download still work without an error.
7. Open the order and download a purchased photo.
8. Change the secure URL `imageId` to an unpurchased photo; it must be rejected.
9. Refund the payment in Stripe and confirm the old secure download link becomes invalid after reconciliation.

### 4. Analytics
1. Generate gallery visits, views, downloads, shares, face searches, uploads, AI jobs, retouch work and a store order.
2. Open `/planner/analytics`.
3. Filter by event, date, category, photographer and channel.
4. Check gallery visits, unique viewers, downloads, transfer counts, photographer uploads, AI jobs, retouch turnaround, orders and revenue.

### 5. Public API
1. Open `/planner/api` and create an event-scoped API key.
2. Try it against another event; access must be rejected.
3. Test `/v1/setup/...` event/category/gallery endpoints.
4. Test URL upload with `POST /v1/upload` and multipart upload with `POST /v1/upload/file`.
5. Retry the same upload with the same idempotency key; no duplicate media should be created.
6. Poll `GET /v1/upload/status/<imageId>?eventId=<eventId>`.
7. Test AI enhance, review, metadata search and `POST /v1/ai/face-search` with a selfie.
8. Test `POST /v1/viewer/mobile-search` with an opted-in pre-registered WhatsApp/mobile number.
9. Test `POST /v1/ai/cartoon` on a photo.
10. Add an API webhook, trigger photo/retouch changes, and verify signed delivery/retries in `/planner/api`.
11. Open backend Swagger at `/api`.

## Final regression commands
```bat
cd backend
npm run build
npm test -- --runInBand
cd ..\frontend
npx tsc --noEmit -p tsconfig.app.json
npm run build
cd ..\desktop-retoucher
npm run check
npm test
cd ..\mobileapp
flutter analyze
flutter test
```

Final camera check: OTG and wireless discovery/connect/shoot must behave exactly as before; Phase 1-3 code must not require camera-protocol changes.