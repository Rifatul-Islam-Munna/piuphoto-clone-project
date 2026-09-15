# Piufoto Clone - 3 Phase Implementation Plan

## Product Goal
Build one complete workflow: **Shoot -> Transfer -> Retouch -> Deliver**.

The product must cover the client requirements exactly: Photographer and Event Planner separation, real-time delivery, AI Enhance, Live Gallery, Branding, Face Recognition, Online Store, Analytics, Multi-Photographer Collaboration, retoucher workflow, desktop batch download, privacy controls, guest notifications and public API integration.

## Non-Negotiable Camera Rule
- Do not change the existing OTG camera connection behavior.
- Do not change the existing wireless camera connection/discovery behavior.
- Keep the current native channel, PTP/IP, Canon CCAPI, UPnP and network discovery code working as-is.
- New code may observe files received from those flows, queue them, show transfer state, upload them and sync status.
- Every phase must include OTG and wireless regression testing.

## Official Piufoto References Reviewed
- https://www.piufoto.com/
- https://www.piufoto.com/features
- https://www.piufoto.com/ai-magic
- https://www.piufoto.com/apiIntro
- https://www.piufoto.com/pricing
- Piufoto privacy/sharing rules and the retouch desktop workflow documentation were also reviewed.

## Current Project Audit
- Flutter capture/upload implementation is mainly in `mobileapp/lib/pages/upload/upload_page.dart`.
- Existing queue already persists uploads locally and retries failures.
- Existing backend already has events, invitations, albums, event images, FAL enhancement jobs and Qdrant face search.
- Existing public web gallery already supports albums, downloads and selfie-based face search.
- Existing foundations should be extended, not replaced.
# PHASE 1 - Photographer/Event Planner Separation + Real-Time Transfer + Multi-Photographer Collaboration

## Phase 1 Goal
Make shooting and delivery operational in real time while separating the Photographer product experience from the Event Planner product experience.

## 1. Separate Photographer and Event Planner
This separation is required first. It is not only a role badge or one dashboard with hidden buttons.

### Photographer Workspace
- Photographer-first mobile workflow.
- Connect camera using the existing OTG/wireless implementation.
- Join or select assigned events.
- Select assigned category/album before shooting.
- See live incoming files immediately after capture.
- See upload progress, failures, retries and delivered state.
- Select/publish photos while still shooting.
- No Event Planner setup/admin clutter in the normal shooting flow.

### Event Planner Workspace
- Separate web/dashboard experience.
- Create and configure events.
- Invite/manage photographers, assistants and retouchers.
- Create categories/albums and assign people to them.
- Configure shared presets/workflow for the project.
- Monitor photos arriving in real time.
- No camera connection controls in the normal planner workflow.

### Shared Account Behavior
- If a user can act as both, show a clear workspace switcher.
- Do not merge both experiences into one confusing dashboard.
## 2. Multi-Photographer Collaboration
This feature must be explicit and first-class.

- Multiple photographers can work inside the same event/project at the same time.
- Each photographer can upload from a different camera/device.
- Each photographer can upload into a different category/album.
- All categories feed into the same event workflow and shared preset rules.
- Event owner/planner can see who uploaded each file.
- Event owner/planner can reassign photographer/category if needed.
- Invitation code/link flow should make joining an event fast.
- No extra seat charge logic for multi-camera teams; model this as unlimited photographers per album/project where the subscription allows it.
- Do not serialize photographers through one upload session; concurrent uploads must be supported.
- Prevent duplicate uploads with a stable client capture ID/fingerprint and idempotent backend handling.

### Backend model changes
Create/refactor into feature modules:
- `event-members` - owner, planner, photographer, assistant, retoucher/reviewer membership.
- `photo-categories` - categories/albums and member assignment.
- `upload-sessions` - photographer/device/camera session tracking.
- `transfer-status` - durable per-photo transfer state.
- `workflow-presets` - shared project processing/publishing rules.

### Required permissions
- Event Planner/Owner: manage event, team, categories, presets and publish rules.
- Photographer: upload/publish within assigned events/categories.
- Retoucher: access retouch queue/status actions.
- Reviewer: approve/hide/show before final delivery when review is enabled.
- Guest: only access gallery content allowed by gallery privacy rules.
## 3. Real-Time Connected Camera Screen
Match the client's provided live-transfer UI concept while keeping the connection internals untouched.

### Screen layout
- Event/category header.
- Connected camera/device indicator.
- Total photo count.
- Filters: `All`, `Uploaded`, `Not uploaded` plus failed/retry state where useful.
- Dense live list suitable for hundreds/thousands of captures.

### Every file row shows
- Thumbnail/preview when available.
- Original filename, including JPG/RAW names.
- Photographer/camera source.
- Category/album.
- Current transfer state.
- Upload progress.
- Retry/error action.
- Received/uploaded time.

### State pipeline
`Detected -> Camera transfer -> Stored locally -> Queued -> Uploading -> Processing -> Published/Delivered`

Failure states must be visible instead of silently disappearing.

### Transfer ledger
The existing retry queue is not enough because successful queue items are removed. Add a durable transfer ledger so the photographer and web console can still see completed files and their full status history.
## 4. Real-Time Photo Status in the Web Console
Retouchers and Event Planners must track every photo live without leaving the browser.

Show:
- Incoming count.
- Uploading count.
- Processing count.
- Waiting for retouch/review count.
- Published/delivered count.
- Failed count.
- Photographer/camera/category for every file.
- Latest transfer time and processing duration.
- Retry/reprocess action where the actor has permission.

Use websocket/SSE events instead of constant page refreshes.

Suggested events:
- `photo.detected`
- `photo.received`
- `photo.uploading`
- `photo.processing`
- `photo.retouching`
- `photo.reviewing`
- `photo.published`
- `photo.delivered`
- `photo.failed`

## 5. Real-Time Delivery Foundation
- New captured media should enter the server workflow immediately.
- The live event gallery should receive published media without manual refresh.
- QR/event link access must continue to work.
- Preserve original files while creating processed/enhanced variants separately.
## Phase 1 Acceptance Test
Phase 1 is complete only when all of this works together:
- Photographer login lands in Photographer workspace.
- Event Planner login lands in Event Planner workspace.
- Shared-role account can switch workspace.
- Existing OTG camera transfer still works unchanged.
- Existing wireless transfer still works unchanged.
- Photographer can select event/category and shoot continuously.
- JPG/RAW files appear in the live list with correct status.
- Two or more photographers can upload to the same event concurrently.
- Different photographers can feed different categories under one shared workflow.
- Planner/retoucher web console updates live.
- Offline/reconnect resumes queued files without duplicates.
- 1,000+ image session does not lose transfer history.

# PHASE 2 - AI Enhance + Face Recognition + Live Gallery + Branding + Privacy + Guest Delivery

## Phase 2 Goal
Turn the real-time transfer pipeline into an automated guest-facing delivery system with AI processing, personalized galleries, branding and strict visibility controls.

## 1. AI Enhance / AI Magic
Extend the existing FAL enhancement workflow instead of replacing it.

### AI Retouch controls
- Colour enhancement.
- Skin beautification.
- Facial beautification.
- Body beautification.
- Vehicle privacy protection.
- Manual single-photo enhancement.
- Automatic event preset enhancement.
- Batch enhancement for hundreds of photos.
- Before/after preview and original-file preservation.
- Queue, retry and per-photo processing status.
### AI Review / Culling
- Automatically flag/tag subpar photos.
- Detect blur, obvious duplicates and unusable shots.
- Auto-select/recommend the best photos from large batches.
- Reviewer can override AI decisions.
- Keep AI decision/reason/status visible in the web console.

### AI Search
- Face Recognition.
- Number Recognition for bib/race/jersey numbers.
- Semantic Search by scene, action, object and keyword.
- Outfit Recognition by clothing color/style/visual details.
- Search results must stay scoped to the correct event/gallery permissions.

## 2. Face Recognition - Personal Gallery
The current face-vector/Qdrant work becomes a complete guest workflow.

### Guest flow
- Guest uploads a selfie or takes one from the device camera.
- AI creates a personal gallery containing only matched photos.
- The personal gallery automatically updates as new event photos are uploaded/indexed.
- Guest can revisit the same personal gallery using a secure guest token/link.
- Show match confidence internally; do not expose unsafe biometric details publicly.

### Pre-registration
- Guests can pre-register a selfie before the event starts.
- Store guest delivery preference: email and/or WhatsApp.
- When new matching photos appear, attach them to that guest's personal gallery automatically.
- Avoid duplicate notifications for the same guest/photo combination.
## 3. Automatic Guest Notifications
- Email guests when new photos of them are found using normal SMTP credentials.
- WhatsApp guests when new photos of them are found using Meta WhatsApp Cloud API credentials.
- Notification includes secure link to the guest's personal gallery.
- Support event-level notification enable/disable.
- Support per-guest opt-in/opt-out.
- Throttle rapid matches so a guest is not spammed after every shutter click.
- Group multiple new matches into one useful notification where possible.
- Track notification sent/delivered/failed state.

## 4. Live Gallery
The gallery must update while the event is still happening.

- New published photos appear automatically without refresh.
- Support photo and video entries in the same event architecture.
- Guests can view/download/share while photographers continue shooting.
- Allow event owner/planner/authorized photographer to select and publish from phone, tablet or web.
- Allow bulk publish/unpublish.
- Allow per-photo hide/show.
- Allow category/album-specific publishing rules.
- Show processing placeholders/status where useful instead of broken cards.
- QR code continues to open the live event experience.

## 5. Public / Private / Password / Facial Privacy
The Event Planner must explicitly decide who sees what.

### Public
- Anyone with the gallery URL/QR can view content marked public.

### Private / Password Protected
- Event Planner can require a password for the full gallery or selected albums.
- Password must be validated server-side, not only hidden in frontend code.
- Access session/token should expire and be revocable.

### Facial Privacy Protection
- Planner can keep face-containing photos private by default.
- A guest who has access can use face recognition to find their own matching photos.
- Support a mode where non-matching people/content are blurred or hidden so a guest effectively sees only their own photos.
## 6. Branding
Each event/live gallery needs configurable branding:
- Brand logo/card.
- Gallery cover/banner/loading visual.
- Brand colors and typography-safe theme controls.
- Photo watermark.
- Share-ready poster/carousel branding.
- Custom event/gallery URL slug.
- Custom domain support where configured.
- White-label/premium branding mode.
- Footer/sponsor branding controls.
- Branding preview before publishing.

## 7. Face Data Safety
- Require explicit event-level consent configuration before face search is enabled.
- Keep biometric/vector data private and inaccessible from normal gallery APIs.
- Add configurable retention/deletion policy for face vectors and guest selfies.
- Provide guest/selfie deletion request path.
- Log consent time/source and delivery preference.
- Never use one event's face vectors to search another event unless explicitly designed/authorized.

## Phase 2 Acceptance Test
- AI retouch works for single and batch photos while preserving originals.
- AI review flags blur/duplicates/subpar photos and reviewer can override it.
- Face, number, semantic and outfit search return event-scoped results.
- Guest selfie creates a personal gallery.
- New matching photos appear automatically in that personal gallery.
- Pre-registered guest receives email/WhatsApp only according to consent/preferences.
- Live gallery updates without refresh.
- Public gallery is truly public only when configured.
- Private/password gallery rejects unauthorized access server-side.
- Facial privacy mode prevents guests from browsing photos they should not see.
- Branding/watermark changes are visible on the published gallery.
# PHASE 3 - Human Retouch + Desktop Sync + Online Store + Analytics + API

## Phase 3 Goal
Complete the professional production/business workflow after capture: human retouching, reviewer approval, automated desktop synchronization, monetization, analytics and external integrations.

## 1. Human Retouch Workflow
Follow a clear professional pipeline:
`Photographer -> Retoucher -> Reviewer -> Audience`

Photo states:
`Incoming -> Downloaded -> Retouching -> Ready for Review -> Approved -> Published/Delivered`

### Retoucher web console
- Live incoming queue from Phase 1.
- Filter by event, category, photographer, status and time.
- Assign/unassign photos or batches to retouchers.
- See original/enhanced/current version.
- Add internal notes.
- Mark retouch in progress/completed.
- Retry failed download/upload.

### Reviewer controls
- Approve or reject retouched files.
- Hide/show before audience delivery.
- Compare original versus retouched result.
- Bulk approve/publish.
- Optional workflow setting to bypass reviewer for trusted events.

## 2. Batch Auto-Download with Desktop App
Build the Piufoto Desktop equivalent for retouchers.

- Windows desktop client first; macOS architecture should remain possible.
- Retoucher signs in and chooses assigned event/category.
- Newly uploaded event photos are detected automatically.
- Batch-download photos without manually clicking each file.
### Desktop sync behavior
- Keep a local event folder in sync with cloud assignments.
- Resume interrupted downloads.
- Verify file integrity/checksum.
- Avoid duplicate files after restart.
- Support large photo sets without loading everything into RAM.
- Watch configured output/export folder for edited files.
- Upload the retouched replacement/version automatically or with a clear review action.
- Preserve original and version history.
- Show desktop sync status back in the web console.
- Support bandwidth/concurrency limits so large events do not overload the machine or server.

### Video workflow preparation
Piufoto also separates video editor batch download through its desktop workflow. Keep the sync architecture media-generic so a future video/Piu-Cut-style client can reuse transfer/session APIs without rewriting photo logic.

## 3. Online Store and Automatic Delivery
As soon as a purchase succeeds, the correct purchased files must be delivered automatically.

Store features:
- Enable/disable sales per event/gallery/category/photo.
- Digital photo products.
- Download packages/bundles.
- Optional print-product structure for later fulfillment integration.
- Watermarked/low-resolution preview before purchase.
- Cart and checkout.
- Guest/customer order history or secure order lookup.
- Coupon/discount hooks if needed later.

### Fulfillment
- Stripe API verification is the payment source of truth. A signed Stripe webhook is optional; direct session verification plus background reconciliation must work when no webhook secret is configured.
- Webhook processing must be idempotent.
- Successful order creates signed/expiring download access for only purchased files.
- Send delivery link by email; WhatsApp delivery can reuse Phase 2 notification service.
- Failed/refunded orders must not retain unauthorized download access.
## 4. Analytics
Provide real-time and historical analytics for the Event Planner/Owner.

Track:
- Gallery visits.
- Unique viewers where privacy-safe.
- Photo/video views.
- Downloads.
- Popular photos.
- Shares/share-link actions where measurable.
- Face-search usage.
- Guest notification opens/clicks where supported.
- Photos captured/uploaded/published/delivered.
- AI jobs and AI failures.
- Photographer upload volume/activity.
- Retoucher throughput/turnaround.
- Store orders, revenue and purchased photos.

Filters:
- Event.
- Category/album.
- Photographer.
- Date/time range.
- Delivery/search/store channel.

## 5. Public API Platform
Match the Piufoto API structure with four clear interface groups.

### Live Gallery Setup API
- Create/update event galleries from external systems.
- Configure categories, branding, privacy, publishing and workflow settings.
- Return gallery IDs/URLs/QR-ready identifiers.

### Live Gallery Viewer API
- Read gallery/album details.
- Read permitted photo/video data.
- Read visit/engagement analytics.
- Support personalized search such as face and participant/mobile-number lookup where enabled.
### Photo Upload API
- External website/app/mini-program can upload media directly into a specified event/gallery/category.
- Require idempotency key/capture ID so retries cannot duplicate photos.
- Return durable upload/processing/publish status identifiers.
- Allow webhook/event callback when processing/delivery status changes.

### AI Technology API
- AI retouching.
- AI culling/review.
- Blur/duplicate detection.
- Face/number/semantic/outfit search endpoints where licensed/enabled.
- Creative/cartoon generation can be a separate optional endpoint so it does not contaminate professional retouch workflow.

### API security/operations
- API keys/service accounts.
- Fine-grained scopes.
- Per-key/event access boundaries.
- Rate limits and quotas.
- Request validation DTOs.
- HMAC-signed webhooks.
- Webhook retry + dead-letter handling.
- Idempotency for write/payment/upload endpoints.
- Audit log.
- OpenAPI/Swagger documentation with examples.
- API versioning (`/v1/...`) before external release.

## Phase 3 Acceptance Test
- Retoucher sees incoming photos live and completes download -> edit -> upload -> review -> publish.
- Desktop auto-download survives app restart/network interruption.
- 100k-photo event can sync in batches without memory spikes.
- Reviewer can hide/show and approve photos before delivery.
- Paid order grants only purchased files and automatically sends delivery access.
- Refund/payment failure revokes or prevents delivery.
- Analytics totals match raw event/order/download records.
- API keys cannot access another tenant/event outside their scope.
- Upload API retry does not duplicate media.
- Webhook retry is safe and idempotent.
# Client Requirement -> Phase Mapping

This section is the checklist. A requirement must not be considered covered only because a similar feature exists.

- Separate Photographer and Event Planner -> **Phase 1**.
- Real-time photo/video transfer and delivery foundation -> **Phase 1**.
- Connected-camera live upload UI -> **Phase 1**.
- Multi-Photographer Collaboration -> **Phase 1**.
- Different photographers uploading to different categories under one preset workflow -> **Phase 1**.
- No extra photographer seats / unlimited team collaboration model -> **Phase 1**.
- Real-Time Photo Status in the Web Console -> **Phase 1**.
- Select and publish while shooting from mobile/web -> **Phase 1 + Phase 2 Live Gallery**.
- AI Enhance / AI Retouch / AI Review / AI Search -> **Phase 2**.
- Live Gallery -> **Phase 2**.
- Branding, watermark, custom URL/domain and white-label controls -> **Phase 2**.
- Face Recognition with selfie personal gallery -> **Phase 2**.
- Personal gallery automatically updates when new matches arrive -> **Phase 2**.
- Guest selfie pre-registration -> **Phase 2**.
- Automatic email/WhatsApp when new matching photos are found -> **Phase 2**.
- Public or private sharing -> **Phase 2**.
- Password-protected galleries -> **Phase 2**.
- Facial privacy / blur-or-hide so a guest sees only allowed personal matches -> **Phase 2**.
- Human retoucher + reviewer workflow -> **Phase 3**.
- Batch Auto-Download with desktop client -> **Phase 3**.
- Online Store with automatic purchased-file delivery -> **Phase 3**.
- Analytics -> **Phase 3**.
- Four-group external API platform: Setup, Viewer, Upload, AI -> **Phase 3**.
# Build Rules Across All Phases

## Flutter
- Do not rewrite camera transport/connectivity code unless a proven bug requires it.
- Keep capture/transfer UI separate from camera protocol implementation.
- Persist queue/ledger locally so temporary network loss never loses a capture.
- Use stable list keys and incremental updates for long live-transfer lists.
- Avoid decoding full-size RAW/JPG files on the UI thread just to render thumbnails.

## NestJS
- Organize new work as feature modules, not one growing `EventImageService` god service.
- Validate all request DTOs and enforce event-level guards/policies server-side.
- Use repository/service boundaries for membership, transfer, notification, store and analytics logic.
- Move long-running AI, notification, indexing and media jobs to durable background jobs/queues.
- Make upload/payment/webhook actions idempotent.
- Index event/category/status/time fields used by live dashboards.
- Do not expose biometric vectors or internal face-cluster data through public responses.

## Final Definition of Done
The product is complete when a team can create an event, invite multiple photographers, shoot through existing OTG/wireless connections, watch files arrive live, process/retouch them, control exactly who can see them, notify guests, sell selected media and automatically deliver purchases - while the whole workflow remains observable from the web console.

Each phase must be testable independently before starting the next phase. A phase is not finished because the UI exists; backend permissions, persistence, realtime behavior, failure recovery and acceptance tests must also pass.