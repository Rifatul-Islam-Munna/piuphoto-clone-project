
# Shared Imagor delivery (PiuPhoto / AirPix)

The original upload remains in the existing `airpix` bucket. `imageUrl` stays
the immutable original download/source URL. The API returns `thumbnailUrl`,
`previewUrl`, `viewUrl` and `processingStatus` separately. The Flutter client
uses flutter_avif for signed AVIF and extensionless cached AVIF links, retaining
JPEG/PNG support and original URL fallback. Gallery downloads use original bytes
and ZIP archives, not resized variants; paid previews retain their existing
store authorization and watermark path.

## Deployment

1. Keep the existing Imagor app (Pixieset project `deploy/imagor`).
2. In Imagor's EasyPanel environment add only PIUPHOTO_BACKEND_INTERNAL_URL,
   the reachable PiuPhoto backend URL.
3. Keep the original S3_LOADER_*, AWS_LOADER_*, S3_RESULT_STORAGE_* and
   BACKEND_INTERNAL_URL settings. The existing R2 credentials and endpoint
   are shared; they must permit reading both source buckets. The engine
   automatically routes piuphoto paths to airpix while keeping Pixieset's
   default bucket. No additional S3 environment variables are required.
   A custom router file, if one is already configured, must include the
   piuphoto rule instead of relying on automatic generation.
4. Deploy updated Imagor. Keep PiuPhoto's existing IMAGOR_URL,
   IMAGOR_SECRET and signer settings. Both backends use the same
   IMAGOR_SECRET for worker authentication. The source prefix is fixed
   in code, and the worker supplies the existing result-storage URL.
   No additional worker secret or routing environment variable is needed.
5. Verify engine routing (a known AirPix source produces HTTP 200 image/avif);
   set IMAGOR_ENABLED=true and deploy PiuPhoto backend, frontend and mobile app.
   IMAGOR_ENABLED=false disables optimized delivery if needed.
6. Existing eligible stored photos are automatically picked up in bounded
   batches by the leased MongoDB queue. No re-upload or database reset.
   720px and 1800px AVIF copies are permanently warmed; 320px is on demand.
   Once all eligible photos for an album (or full event view) are verified,
   the API delivers the cached R2 variants. New uploads revert the relevant
   scope to Imagor until warming catches up. Videos, unsupported RAW formats,
   externally hosted images and store-protected previews retain prior behavior.

Queue endpoints (authenticated using x-imagor-worker-secret):
POST /internal/imagor-cache/claim
POST /internal/imagor-cache/complete/:leaseId
POST /internal/imagor-cache/delete/claim
POST /internal/imagor-cache/delete/complete/:leaseId

Result storage must retain permanent cache objects. Do not expire all result
objects blindly. Cleanup jobs handle deleted or replaced photos without
deleting their originals.
