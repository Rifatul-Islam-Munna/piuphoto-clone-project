import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Types } from 'mongoose';
import type { Response } from 'express';
import { pipeline } from 'node:stream/promises';
import { EventImageService } from '../event-image/event-image.service';
import { GuestGalleryService } from '../guest-gallery/guest-gallery.service';
import { MinioService } from '../lib/minio.service';
import { streamPhotoZip, type PhotoZipEntry } from './stream-photo-zip';

export type PublicZipQuery = {
  eventId: string;
  albumId?: string;
  accessToken?: string;
  guestToken?: string;
  ids?: string;
};

type GalleryDownloadRow = {
  _id?: unknown;
  id?: string;
  imageUrl?: string;
  mediaType?: string;
  isEnhanced?: boolean;
  purchaseRequired?: boolean;
};

const supportedExtensions = new Set([
  '.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif', '.heic', '.heif',
  '.tif', '.tiff', '.dng', '.arw', '.cr2', '.cr3', '.nef', '.raf',
  '.rw2', '.orf', '.pef', '.mp4', '.mov', '.webm', '.m4v',
]);

export function safePhotoEntryName(row: GalleryDownloadRow, index: number) {
  let extension = row.mediaType === 'video' ? '.mp4' : '.jpg';
  try {
    const pathname = new URL(row.imageUrl || '').pathname.toLowerCase();
    const candidate = pathname.match(/\.[a-z0-9]{2,5}$/)?.[0];
    if (candidate && supportedExtensions.has(candidate)) extension = candidate;
  } catch { /* Legacy rows without an absolute URL use a safe extension. */ }
  const photoId = String(row._id || row.id || '').match(/^[a-f\d]{24}$/i)?.[0];
  return `airpix-${photoId?.slice(-12) || String(index + 1).padStart(5, '0')}${row.isEnhanced ? '-enhanced' : ''}${extension}`;
}

/**
 * Native attachment download for iOS/Safari and browsers that cannot stream
 * a ZIP straight to disk. The backend does not buffer the photos or archive.
 * Direct browser-to-R2 ZIP downloads remain the preferred desktop path.
 */
@Injectable()
export class GalleryDownloadService {
  constructor(
    private readonly eventImages: EventImageService,
    private readonly guests: GuestGalleryService,
    private readonly storage: MinioService,
  ) {}

  async prepare(query: PublicZipQuery): Promise<PhotoZipEntry[]> {
    if (!Types.ObjectId.isValid(query.eventId)) {
      throw new BadRequestException('Invalid event id');
    }
    if (query.albumId && !Types.ObjectId.isValid(query.albumId)) {
      throw new BadRequestException('Invalid album id');
    }
    let requested: Set<string> | undefined;
    if (query.ids !== undefined && query.ids !== '') {
      if (query.ids.length > 7500) throw new BadRequestException('Too many selected images');
      const ids = query.ids.split(',').filter(Boolean);
      if (!ids.length || ids.length > 250 || ids.some((id) => !Types.ObjectId.isValid(id))) {
        throw new BadRequestException('Invalid selected image ids');
      }
      requested = new Set(ids);
    }

    const response = query.guestToken
      ? await this.guests.personal({
          eventId: query.eventId,
          albumId: query.albumId,
          guestToken: query.guestToken,
        })
      : await this.eventImages.findPublicByEvent(
          query.eventId,
          query.albumId,
          query.accessToken,
        );
    const available = (response.data || []) as GalleryDownloadRow[];
    const selected = requested
      ? available.filter((row) => requested.has(String(row._id || row.id)))
      : available;
    if (requested && selected.length !== requested.size) {
      throw new ForbiddenException('Some selected photos are no longer available');
    }
    if (selected.some((row) => row.purchaseRequired)) {
      throw new ForbiddenException('Purchase required before downloading original photos');
    }
    if (!selected.length) throw new NotFoundException('No downloadable photos in this gallery');
    if (selected.length > 10_000) {
      throw new BadRequestException('Gallery exceeds the maximum archive size');
    }
    if (selected.some((row) => !row.imageUrl || !this.storage.canStreamStoredUrl(row.imageUrl))) {
      throw new BadRequestException('A photo is stored on an unsupported legacy host');
    }

    return selected.map((row, index) => ({
      name: safePhotoEntryName(row, index),
      open: (signal: AbortSignal) => this.storage.openStoredUrl(row.imageUrl!, signal),
    }));
  }

  /** One real HTTP attachment for a single photo; avoids iOS popup blocking. */
  async downloadPhoto(query: PublicZipQuery, response: Response): Promise<void> {
    if (!query.ids || query.ids.includes(',')) {
      throw new BadRequestException('Select exactly one photo to download');
    }
    const entries = await this.prepare(query);
    if (entries.length !== 1) throw new NotFoundException('Photo unavailable');
    const controller = new AbortController();
    const onClose = () => {
      if (!response.writableFinished) controller.abort(new Error('Visitor disconnected'));
    };
    response.once('close', onClose);
    try {
      const photo = await entries[0].open(controller.signal);
      response.status(200);
      response.setHeader('Content-Type', 'application/octet-stream');
      response.setHeader('Content-Disposition', `attachment; filename="${entries[0].name}"`);
      response.setHeader('Cache-Control', 'private, no-store, max-age=0');
      response.setHeader('X-Content-Type-Options', 'nosniff');
      response.setHeader('Referrer-Policy', 'no-referrer');
      await pipeline(photo, response, { signal: controller.signal });
    } catch (error) {
      if (!response.headersSent) {
        throw error;
      }
      if (!response.destroyed) response.destroy(error instanceof Error ? error : undefined);
    } finally {
      response.off('close', onClose);
    }
  }

  async download(query: PublicZipQuery, response: Response): Promise<void> {
    // Authorize the whole file set before sending archive headers.
    const entries = await this.prepare(query);
    const filename = `airpix-event-${query.eventId.slice(-12)}.zip`;

    response.status(200);
    response.setHeader('Content-Type', 'application/zip');
    response.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    response.setHeader('Cache-Control', 'private, no-store, max-age=0');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Referrer-Policy', 'no-referrer');

    const controller = new AbortController();
    const onClose = () => {
      if (!response.writableFinished) controller.abort(new Error('Visitor disconnected'));
    };
    response.once('close', onClose);
    try {
      await streamPhotoZip(entries, response, controller.signal);
    } catch (error) {
      if (!response.destroyed) response.destroy(error instanceof Error ? error : undefined);
      // After an attachment begins, an HTTP JSON error is no longer possible.
    } finally {
      response.off('close', onClose);
    }
  }
}
