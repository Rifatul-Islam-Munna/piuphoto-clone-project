# Piufoto Feature Completeness Audit

This file maps the requested Piufoto-style workflow to the implementation in this repository.

## Core workflow
- [x] Shoot -> Transfer -> Retouch -> Deliver workflow.
- [x] Separate Photographer and Event Planner workspaces.
- [x] Real-time photo/video upload pipeline.
- [x] Existing OTG and wireless camera connection code preserved.
- [x] Durable transfer ledger, retry and duplicate protection.
- [x] Real-time planner web console with SSE updates.
- [x] Multi-photographer event collaboration with category assignment.
- [x] No photographer-seat gating in event collaboration.
- [x] Mobile/web publish and unpublish controls while shooting.

## Phase 2 - AI and gallery
- [x] Colour Enhancement.
- [x] Skin Beautification.
- [x] Facial Beautification.
- [x] Body Beautification.
- [x] Vehicle Privacy Protection.
- [x] AI Review/culling with blur and duplicate detection.
- [x] Reviewer override and original/enhanced comparison.
- [x] Number, semantic and outfit search.
- [x] Selfie-based face recognition.
- [x] Planner selfie face search.
- [x] Guest selfie pre-registration with consent and retention.
- [x] Personal gallery automatically updates from new face matches.
- [x] Email/WhatsApp preferences with grouped, deduplicated notifications.
- [x] SMTP and WhatsApp providers are optional; missing credentials do not break the app.
- [x] Public, private, password-protected and facial privacy modes.
- [x] Hide non-matches and blur non-matches behavior.
- [x] Live gallery updates without manual refresh.
- [x] Photo and video entries in the live gallery.
- [x] Logo, cover, watermark, theme colors, footer and sponsor branding.
- [x] Gallery slug, custom domain and white-label settings.
- [x] Batch download and gallery link sharing.

## Phase 3 - production workflow
- [x] Photographer -> Retoucher -> Reviewer -> Audience workflow.
- [x] Retoucher assignment, notes, versions and review states.
- [x] Real-time retouch console status.
- [x] Desktop batch auto-download with restart-safe state.
- [x] Interrupted download resume, checksum and duplicate prevention.
- [x] Export-folder watch and automatic retouched-version upload.
- [x] Desktop concurrency and bandwidth controls.
- [x] Online store with per-event/category/photo sales controls.
- [x] Stripe checkout idempotency and secure purchased-only downloads.
- [x] Refund revocation and background Stripe API reconciliation.
- [x] `STRIPE_WEBHOOK_SECRET` is optional; unsigned webhook payloads never mark orders paid.
- [x] Store delivery uses SMTP/WhatsApp when configured and still works without them.
- [x] Analytics for visits, views, downloads, shares and popular media.
- [x] Transfer, photographer, AI, face, retouch and notification analytics.
- [x] Store order/revenue analytics.

## External API
- [x] Live Gallery Setup API.
- [x] Live Gallery Viewer API.
- [x] Photo Upload API by URL and multipart file.
- [x] Durable upload-status lookup and idempotency key support.
- [x] AI retouch/enhance API.
- [x] AI culling/review API.
- [x] Face, number, semantic and outfit search APIs.
- [x] Trusted event-scoped mobile-number personal-gallery lookup.
- [x] AI cartoon/creative generation endpoint using the existing FAL workflow.
- [x] API keys, event scopes, rate quotas and audit log.
- [x] HMAC-signed workflow webhooks with retries and dead-delivery handling.
- [x] Swagger/OpenAPI `/v1` documentation surface.

## Provider architecture
- General AI analysis uses `FAL_KEY` / `FAL_API_KEY`; no `VISION_ANALYSIS_ENDPOINT_URL` is required.
- `FACE_DETECTION_ENDPOINT_URL` remains separate because it produces face embeddings for Qdrant matching.
- SMTP is optional. Blank SMTP settings simply disable outbound email.
- WhatsApp Cloud API is optional. Blank WhatsApp settings simply disable outbound WhatsApp.
- Stripe webhook signing is optional for this deployment because paid/refunded state is independently verified with Stripe's API.

Use `PHASE_1_2_3_TEST_GUIDE.md` for the step-by-step manual test flow.
