import { Body, Controller, Headers, HttpException, Injectable, Param, Post, UnauthorizedException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { randomUUID, timingSafeEqual } from 'crypto';
import { Model, Types } from 'mongoose';
import { EventImage, EventImageDocument } from './entities/event-image.entity';
import { deliveryConfigVersion, digestKey, eligiblePhotoFilter, imagorEnabled, imagorUrls, loadDeliveryBranding } from './image-delivery';

const LEASE = 15 * 60_000;
@Injectable()
export class ImagorCacheService {
  constructor(@InjectModel(EventImage.name) private readonly photos: Model<EventImageDocument>) {}
  private get cleanup() { return this.photos.db.collection('imagor_cache_cleanup'); }
  private claimId(id: unknown, token: string) { return String(id) + '~' + token; }
  private split(id: string) {
    const [photoId, token, extra] = id.split('~');
    return !extra && Types.ObjectId.isValid(photoId) && /^[a-f0-9-]{36}$/.test(token || '')
      ? { _id: new Types.ObjectId(photoId), imagorLease: token } : null;
  }

  async getEventStatus(eventId: string) {
    if (!Types.ObjectId.isValid(eventId)) throw new HttpException('Invalid event id', 400);
    const id = new Types.ObjectId(eventId);
    const filter = { eventId: id, ...eligiblePhotoFilter() };
    const configVersion = deliveryConfigVersion();
    const [totalPhotos, eligiblePhotos, groups, ready, unsupported, failures] = await Promise.all([
      this.photos.countDocuments({ eventId: id, mediaType: { $ne: 'video' } }),
      this.photos.countDocuments(filter),
      this.photos.aggregate([
        { $match: filter },
        { $group: { _id: { $ifNull: ['$imagorStatus', 'unprocessed'] }, count: { $sum: 1 } } },
      ]).exec(),
      this.photos.countDocuments({ ...filter, imagorStatus: 'ready', imagorConfig: configVersion,
        imagorSignature: { $exists: true, $ne: '' }, imagorSmallUrl: { $nin: [null, ''] }, imagorViewUrl: { $nin: [null, ''] },
        $expr: { $eq: ['$imagorSource', '$imageUrl'] } }),
      this.photos.countDocuments({ ...filter, imagorStatus: 'unsupported', imagorConfig: configVersion }),
      this.photos.find({ ...filter, imagorStatus: 'failed' }).select('imagorLastError').limit(200).lean(),
    ]);
    const counts: Record<string, number> = {};
    for (const group of groups) counts[String(group._id || 'unprocessed')] = Number(group.count) || 0;
    const remaining = Math.max(0, eligiblePhotos - ready - unsupported);
    const reasonCounts = new Map<string, number>();
    for (const failure of failures) {
      const reason = String(failure.imagorLastError || 'Failure details were not recorded by the previous worker version').slice(0, 400);
      reasonCounts.set(reason, (reasonCounts.get(reason) || 0) + 1);
    }
    const failureReasons = [...reasonCounts.entries()]
      .map(([message, count]) => ({ message, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 5);
    return {
      enabled: imagorEnabled(), eventId, totalPhotos, eligiblePhotos, ready,
      pending: counts.pending || 0, processing: counts.processing || 0, failed: counts.failed || 0,
      unsupported, unprocessed: counts.unprocessed || 0, staleReady: Math.max(0, (counts.ready || 0) - ready),
      remaining, progressPercent: eligiblePhotos ? Math.round((ready / eligiblePhotos) * 100) : 100,
      galleryReady: remaining === 0, failureReasons,
    };
  }

  async recacheEvent(eventId: string) {
    if (!Types.ObjectId.isValid(eventId)) throw new HttpException('Invalid event id', 400);
    if (!imagorEnabled()) return { enabled: false, queued: 0, status: await this.getEventStatus(eventId) };
    const result = await this.photos.updateMany(
      { eventId: new Types.ObjectId(eventId), ...eligiblePhotoFilter() },
      { $set: { imagorStatus: 'pending' }, $unset: { imagorLease: 1, imagorNextAt: 1, imagorAttempts: 1, imagorLastError: 1 } },
    );
    return { enabled: true, queued: Number(result.matchedCount ?? result.modifiedCount ?? 0), status: await this.getEventStatus(eventId) };
  }

  async claim() {
    if (!imagorEnabled()) return null;
    const now = new Date();
    const token = randomUUID();
    const configVersion = deliveryConfigVersion();
    const row = await this.photos.findOneAndUpdate({
      ...eligiblePhotoFilter(),
      $or: [
        { imagorStatus: { $exists: false } },
        { imagorStatus: 'pending' },
        { imagorStatus: 'unsupported', imagorConfig: { $ne: configVersion } },
        { imagorStatus: { $in: ['failed', 'processing'] }, imagorNextAt: { $lte: now } },
        { imagorStatus: 'ready', $or: [{ $expr: { $ne: ['$imagorSource', '$imageUrl'] } }, { imagorConfig: { $ne: configVersion } }, { imagorSmallUrl: { $in: [null, ''] } }, { imagorViewUrl: { $in: [null, ''] } }] },
      ],
    }, {
      $set: { imagorStatus: 'processing', imagorLease: token, imagorNextAt: new Date(+now + LEASE) },
      $inc: { imagorAttempts: 1 },
      $unset: { imagorLastError: 1 },
    }, { new: true, sort: { createdAt: 1 } }).lean();
    if (!row) return null;
    const branding = await loadDeliveryBranding(this.photos, String(row.eventId));
    const urls = imagorUrls(row, branding);
    if (!urls) {
      await this.photos.updateOne({ _id: row._id, imagorLease: token }, {
        $set: { imagorStatus: 'unsupported', imagorConfig: configVersion, imagorLastError: 'Image source or watermark configuration is not supported by the current Imagor delivery rules' },
        $unset: { imagorLease: 1, imagorNextAt: 1 },
      });
      return null;
    }
    const updated = await this.photos.updateOne({ _id: row._id, imagorLease: token, eventId: row.eventId, imageUrl: row.imageUrl }, {
      $set: { imagorSource: row.imageUrl, imagorSignature: urls.small + '|' + urls.view, imagorConfig: configVersion },
      $addToSet: { imagorTransformUrls: { $each: Object.values(urls) } },
    });
    if (!updated.matchedCount) return null;
    return { imageId: this.claimId(row._id, token), collectionId: String(row.eventId), version: 1, urls: { small: urls.small, view: urls.view } };
  }

  async complete(id: string, body: any) {
    const filter = this.split(id);
    // A late callback for a reclaimed lease must not cause the worker to delete
    // deterministic cache keys still in use by the new lease.
    if (!filter) return { accepted: true, ready: false };
    const row = await this.photos.findOne(filter).lean();
    if (!row) return { accepted: true, ready: false };
    const branding = await loadDeliveryBranding(this.photos, String(row.eventId));
    const urls = imagorUrls(row, branding);
    if (row.imagorSource !== row.imageUrl || !urls || row.imagorConfig !== deliveryConfigVersion() || row.imagorSignature !== urls.small + '|' + urls.view) {
      await this.photos.updateOne(filter, { $set: { imagorStatus: 'pending' }, $unset: { imagorLease: 1, imagorLastError: 1 } });
      return { accepted: true, ready: false };
    }
    const valid = (kind: 'small' | 'view') => {
      try {
        const key = String(body?.keys?.[kind] || '');
        const url = new URL(body?.urls?.[kind] || '');
        const expectedRoot = (process.env.IMAGOR_RESULT_PUBLIC_URL || '').replace(/\/+$/, '');
        return !!key && (key === digestKey(urls[kind]) || key.endsWith('/' + digestKey(urls[kind]))) &&
          url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash &&
          decodeURIComponent(url.pathname).endsWith('/' + key) &&
          (!expectedRoot || url.href === expectedRoot + '/' + key);
      } catch { return false; }
    };
    if (body?.success !== true || !valid('small') || !valid('view')) {
      const delay = Math.min(3600_000, 5_000 * Math.pow(2, Math.min(10, row.imagorAttempts || 1)));
      const workerError = typeof body?.error === 'string' ? body.error.trim().slice(0, 500) : '';
      const errorMessage = workerError || (body?.success === true
        ? 'Result Storage verification failed: returned keys or public URLs did not match the signed transforms'
        : 'Imagor worker reported a failed transformation without an error message');
      await this.photos.updateOne(filter, {
        $set: { imagorStatus: 'failed', imagorNextAt: new Date(Date.now() + delay), imagorLastError: errorMessage },
        $unset: { imagorLease: 1 },
      });
      return { accepted: true, ready: false };
    }
    const result = await this.photos.updateOne({ ...filter, eventId: row.eventId, imageUrl: row.imageUrl }, {
      $set: { imagorStatus: 'ready', imagorSmallUrl: body.urls.small, imagorViewUrl: body.urls.view },
      $unset: { imagorLease: 1, imagorNextAt: 1, imagorAttempts: 1, imagorLastError: 1 },
      $addToSet: { imagorTransformUrls: { $each: Object.values(urls) } },
    });
    return { accepted: true, ready: !!result.modifiedCount };
  }

  async scheduleCleanup(row: any) {
    if (!row || !imagorEnabled()) return;
    if (await this.photos.exists({ imageUrl: row.imageUrl })) return;
    const branding = await loadDeliveryBranding(this.photos, String(row.eventId));
    const urls = [...new Set([...Object.values(imagorUrls(row, branding) || {}), ...(row.imagorTransformUrls || [])])];
    if (!urls.length) return;
    await this.cleanup.updateOne({ imageId: String(row._id), source: row.imageUrl }, {
      $setOnInsert: { imageId: String(row._id), collectionId: String(row.eventId), source: row.imageUrl,
        transformUrls: urls, nextAt: new Date(Date.now() + LEASE), attempts: 0 },
    }, { upsert: true });
  }

  async claimDelete() {
    if (!imagorEnabled()) return null;
    const token = randomUUID();
    const row = await this.cleanup.findOneAndUpdate({ nextAt: { $lte: new Date() } },
      { $set: { token, nextAt: new Date(Date.now() + LEASE) }, $inc: { attempts: 1 } },
      { sort: { nextAt: 1 }, returnDocument: 'after' });
    if (!row) return null;
    if (await this.photos.exists({ imageUrl: row.source })) {
      await this.cleanup.deleteOne({ _id: row._id, token });
      return null;
    }
    return { jobId: this.claimId(row._id, token), imageId: row.imageId, collectionId: row.collectionId,
      keys: [], urls: [], transformUrls: row.transformUrls };
  }

  async completeDelete(id: string, body: any) {
    const filter = this.split(id);
    if (!filter) return { accepted: false };
    const query = { _id: filter._id, token: filter.imagorLease };
    if (body?.success === true) await this.cleanup.deleteOne(query);
    else await this.cleanup.updateOne(query, { $set: { nextAt: new Date(Date.now() + 60_000) }, $unset: { token: 1 } });
    return { accepted: true };
  }
}

@Controller('internal/imagor-cache')
export class ImagorCacheController {
  constructor(private readonly cache: ImagorCacheService) {}
  private authorize(secret?: string) {
    const expected = Buffer.from((process.env.IMAGOR_SECRET || '').trim());
    const actual = Buffer.from(secret || '');
    if (!expected.length || expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
      throw new UnauthorizedException('Invalid Imagor worker secret');
    }
  }
  @Post('claim')
  async claim(@Headers('x-imagor-worker-secret') secret?: string) {
    this.authorize(secret); return { data: await this.cache.claim() };
  }
  @Post('complete/:id')
  async complete(@Param('id') id: string, @Body() body: any, @Headers('x-imagor-worker-secret') secret?: string) {
    this.authorize(secret); return { data: await this.cache.complete(id, body) };
  }
  @Post('delete/claim')
  async claimDelete(@Headers('x-imagor-worker-secret') secret?: string) {
    this.authorize(secret); return { data: await this.cache.claimDelete() };
  }
  @Post('delete/complete/:id')
  async completeDelete(@Param('id') id: string, @Body() body: any, @Headers('x-imagor-worker-secret') secret?: string) {
    this.authorize(secret); return { data: await this.cache.completeDelete(id, body) };
  }
}
