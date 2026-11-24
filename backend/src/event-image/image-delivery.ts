import { createHash, createHmac, timingSafeEqual } from 'crypto';
import { Model, Types } from 'mongoose';
import type { EventImageDocument } from './entities/event-image.entity';

type Photo = Record<string, any>;
const raster = /\.(?:jpe?g|png|webp|avif|gif|tiff?|heic|heif)$/i;
const setting = (name: string) => (process.env[name] || '').trim();
const root = () => setting('IMAGOR_URL').replace(/\/+$/, '');
export const imagorEnabled = () =>
  !!(root() && setting('IMAGOR_SECRET')) && !/^(0|false|off)$/i.test(setting('IMAGOR_ENABLED'));
const publicRoot = () => setting('STORAGE_PUBLIC_URL').replace(/\/+$/, '');
const regexEscape = (value: string) => value.replace(/[.*+?^$\{\}()|[\]\\]/g, '\\$&');

// Legacy uploads may have a backend-signed original URL instead of a public
// R2 domain. Verify the existing MinioService token before signing its key.
function legacyStorageSigning() {
  try {
    const r2 = setting('STORAGE_S3_URL');
    const endpoint = new URL(r2 || setting('MINIO_URL'));
    const bucket = r2 ? setting('BUCKET') || setting('STORAGE_BUCKET_NAME') ||
      decodeURIComponent(endpoint.pathname.replace(/^\/+|\/+$/g, ''))
      : setting('MINIO_BUCKET_NAME') || 'piuphoto-public-bucket';
    const secret = setting('STORAGE_URL_SECRET') || setting(r2 ? 'STORAGE_SECRET_KEY' : 'MINIO_SECRET_KEY');
    return bucket && secret ? { bucket, secret } : undefined;
  } catch { return; }
}

export function eligiblePhotoFilter(): Record<string, any> {
  const base = publicRoot();
  const ext = '\\.(?:jpe?g|png|webp|avif|gif|tiff?|heic|heif)';
  const patterns = [
    base ? regexEscape(base) + '/[A-Za-z0-9_./%-]+' + ext : '',
    legacyStorageSigning() ? 'https?://[^/]+/image/file/[A-Za-z0-9_./%-]+' + ext + '\\?token=[a-f0-9]{64}' : '',
  ].filter(Boolean);
  return { mediaType: { $ne: 'video' }, imageUrl: patterns.length
    ? { $regex: '^(?:' + patterns.join('|') + ')$', $options: 'i' }
    : { $in: [] } };
}

export function sourceKey(imageUrl: string): string | undefined {
  try {
    const url = new URL(imageUrl);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.hash) return;
    let key: string | undefined;
    if (publicRoot() && !url.search) {
      const base = new URL(publicRoot() + '/');
      if (url.origin === base.origin && url.pathname.startsWith(base.pathname)) {
        key = url.pathname.slice(base.pathname.length).split('/').map(decodeURIComponent).join('/');
      }
    }
    if (!key && url.pathname.startsWith('/image/file/')) {
      const legacy = legacyStorageSigning();
      const token = url.searchParams.get('token') || '';
      const candidate = decodeURIComponent(url.pathname.slice('/image/file/'.length));
      if (legacy && /^[a-f0-9]{64}$/i.test(token) && [...url.searchParams.keys()].length === 1) {
        const expected = createHmac('sha256', legacy.secret).update(JSON.stringify([legacy.bucket, candidate])).digest();
        if (timingSafeEqual(Buffer.from(token, 'hex'), expected)) key = candidate;
      }
    }
    if (!key || !/^[A-Za-z0-9_./-]+$/.test(key) || !raster.test(key) ||
        key.split('/').some(part => !part || part === '.' || part === '..')) return;
    return key;
  } catch { return; }
}

function number(name: string, fallback: number, min: number, max: number) {
  const raw = setting(name);
  const value = raw ? Number(raw) : fallback;
  return Math.max(min, Math.min(max, Number.isFinite(value) ? Math.round(value) : fallback));
}
export function imagorUrls(photo: Photo) {
  if (!imagorEnabled() || photo.mediaType === 'video' || photo.purchaseRequired) return;
  const key = sourceKey(photo.imageUrl);
  if (!key) return;
  // Match the fixed AirPix route in the shared Imagor engine.
  const source = ['piuphoto', ...key.split('/')].map(encodeURIComponent).join('/');
  const signer = setting('IMAGOR_SIGNER_TYPE') || 'sha256';
  if (!['sha1', 'sha256', 'sha512'].includes(signer)) return;
  const truncate = number('IMAGOR_SIGNER_TRUNCATE', 40, 0, 128);
  const variant = (name: string, size: number, quality: number) => {
    const w = number('IMAGOR_' + name + '_WIDTH', size, 1, 3200);
    const h = number('IMAGOR_' + name + '_HEIGHT', size, 1, 3200);
    const q = number('IMAGOR_' + name + '_QUALITY', quality, 1, 95);
    const path = 'fit-in/' + w + 'x' + h + '/filters:format(avif):quality(' + q + '):strip_exif()/' + source;
    let signature = createHmac(signer, setting('IMAGOR_SECRET')).update(path).digest('base64')
      .replace(/\+/g, '-').replace(/\//g, '_');
    if (truncate) signature = signature.slice(0, truncate);
    return root() + '/' + signature + '/' + path;
  };
  return { thumbnail: variant('THUMB', 320, 45), small: variant('SMALL', 720, 60), view: variant('VIEW', 1800, 68) };
}

// Changes to the engine, signing key, source routing or transform settings
// invalidate cached rows without a database migration or an unbounded update.
export function deliveryConfigVersion() {
  const keys = ['IMAGOR_URL', 'IMAGOR_SECRET', 'IMAGOR_SIGNER_TYPE', 'IMAGOR_SIGNER_TRUNCATE',
    'IMAGOR_THUMB_WIDTH', 'IMAGOR_THUMB_HEIGHT', 'IMAGOR_THUMB_QUALITY', 'IMAGOR_SMALL_WIDTH',
    'IMAGOR_SMALL_HEIGHT', 'IMAGOR_SMALL_QUALITY', 'IMAGOR_VIEW_WIDTH', 'IMAGOR_VIEW_HEIGHT',
    'IMAGOR_VIEW_QUALITY', 'IMAGOR_RESULT_PUBLIC_URL', 'STORAGE_PUBLIC_URL', 'STORAGE_S3_URL', 'BUCKET', 'STORAGE_BUCKET_NAME', 'STORAGE_URL_SECRET', 'STORAGE_SECRET_KEY', 'MINIO_URL', 'MINIO_BUCKET_NAME', 'MINIO_SECRET_KEY'];
  return createHash('sha256').update(JSON.stringify(keys.map(setting))).digest('hex');
}

export function digestKey(url: string) {
  const path = new URL(url).pathname.replace(/^\/[^/]+\//, '');
  const hash = createHash('sha1').update(path).digest('hex');
  return hash.slice(0, 2) + '/' + hash.slice(2, 4) + '/' + hash.slice(4);
}
export function currentCache(photo: Photo, urls: NonNullable<ReturnType<typeof imagorUrls>>) {
  return photo.imagorStatus === 'ready' && photo.imagorSource === photo.imageUrl &&
    photo.imagorConfig === deliveryConfigVersion() && photo.imagorSignature === urls.small + '|' + urls.view &&
    !!photo.imagorSmallUrl && !!photo.imagorViewUrl;
}

export const pendingCacheFilter = (): Record<string, any> => ({
  $and: [{ $or: [{ imagorStatus: { $ne: 'unsupported' } }, { imagorConfig: { $ne: deliveryConfigVersion() } }] }, { $or: [
    { imagorStatus: { $ne: 'ready' } },
    { imagorConfig: { $ne: deliveryConfigVersion() } },
    { $expr: { $ne: ['$imagorSource', '$imageUrl'] } },
    { imagorSmallUrl: { $in: [null, ''] } },
    { imagorViewUrl: { $in: [null, ''] } },
  ] }],
});

export function withDelivery<T>(row: T, direct = false): T {
  if (!row) return row;
  const photo = ((row as any).toObject ? (row as any).toObject() : { ...row }) as Photo;
  const urls = imagorUrls(photo);
  // Preserve the original document/identity for unoptimized legacy records.
  // Only create a new API object when adding or removing delivery fields.
  if (!urls && !Object.keys(photo).some(key => key.startsWith('imagor'))) return row;
  if (urls) {
    const ready = currentCache(photo, urls);
    const cached = direct && ready;
    const mark = (url: string) => url + (url.includes('?') ? '&' : '?') + 'format=avif';
    // The original URL is deliberately not replaced: ZIP, AI and purchase code
    // still use it. The format marker also identifies extensionless AVIF on Flutter.
    photo.thumbnailUrl = cached ? mark(photo.imagorSmallUrl) : urls.thumbnail;
    photo.previewUrl = cached ? mark(photo.imagorSmallUrl) : urls.small;
    photo.viewUrl = cached ? mark(photo.imagorViewUrl) : urls.view;
    photo.processingStatus = ready ? 'ready' : photo.imagorStatus || 'pending';
  }
  for (const key of Object.keys(photo)) if (key.startsWith('imagor')) delete photo[key];
  return photo as T;
}

export async function deliveryRows<T>(model: Model<EventImageDocument>, rows: T[], albumId?: string): Promise<T[]> {
  if (!imagorEnabled()) return rows.map(row => withDelivery(row));
  const ids = [...new Set(rows.map(row => {
    const p = row as Photo;
    return String(p?.eventId?._id || p?.eventId || '');
  }).filter(id => Types.ObjectId.isValid(id)))];
  const pending = new Set<string>();
  if (ids.length) {
    // One query, not a per-photo lookup. A scoped album (or the whole event)
    // switches together, even when this response only contains one page.
    const result = await model.distinct('eventId', {
      ...eligiblePhotoFilter(), eventId: { $in: ids.map(id => new Types.ObjectId(id)) },
      ...(albumId && Types.ObjectId.isValid(albumId) ? { albumId: new Types.ObjectId(albumId) } : {}),
      ...pendingCacheFilter(),
    });
    for (const id of result) pending.add(String(id));
  }
  return rows.map(row => {
    const p = row as Photo;
    const id = String(p?.eventId?._id || p?.eventId || '');
    return withDelivery(row, !!id && !pending.has(id));
  });
}
