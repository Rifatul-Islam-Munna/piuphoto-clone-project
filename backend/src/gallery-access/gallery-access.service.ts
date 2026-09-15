import { ForbiddenException, HttpException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectModel } from '@nestjs/mongoose';
import { createHash, createHmac, timingSafeEqual } from 'crypto';
import { Model, Types } from 'mongoose';
import * as bcrypt from 'bcrypt';
import { Album, AlbumDocument } from '../album/entities/album.entity';
import { EventMemberService } from '../event-member/event-member.service';
import { Event, EventDocument } from '../event/entities/event.entity';
import {
  FacialPrivacyMode,
  GalleryAccessMode,
  GalleryLinkDto,
  GallerySettingsDto,
  GalleryUnlockDto,
} from './dto/gallery-access.dto';
import {
  GalleryAccessAudit,
  GalleryAccessAuditDocument,
} from './gallery-access-audit.entity';

type TokenScope = 'gallery' | 'personal';
type GalleryTokenPayload = {
  eventId: string;
  albumId?: string;
  version: string;
  scope: TokenScope;
  exp: number;
};

type EffectiveAccess = {
  event: Record<string, any>;
  album?: Record<string, any> | null;
  mode: GalleryAccessMode;
  passwordHash?: string;
  version: string;
};

@Injectable()
export class GalleryAccessService {
  constructor(
    @InjectModel(Event.name) private readonly eventModel: Model<EventDocument>,
    @InjectModel(Album.name) private readonly albumModel: Model<AlbumDocument>,
    @InjectModel(GalleryAccessAudit.name)
    private readonly auditModel: Model<GalleryAccessAuditDocument>,
    private readonly members: EventMemberService,
    private readonly config: ConfigService,
  ) {}

  private objectId(id: string) {
    if (!Types.ObjectId.isValid(id)) throw new HttpException('Invalid id', 400);
    return new Types.ObjectId(id);
  }

  private secret() {
    return (
      this.config.get<string>('GALLERY_ACCESS_SECRET') ||
      this.config.get<string>('ACCESS_TOKEN') ||
      'change-gallery-access-secret'
    );
  }

  private encode(payload: GalleryTokenPayload) {
    const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signature = createHmac('sha256', this.secret())
      .update(body)
      .digest('base64url');
    return `${body}.${signature}`;
  }

  private decode(token?: string): GalleryTokenPayload | null {
    if (!token) return null;
    const [body, signature] = token.split('.');
    if (!body || !signature) return null;
    const expected = createHmac('sha256', this.secret())
      .update(body)
      .digest('base64url');
    const a = Buffer.from(signature);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
    try {
      const payload = JSON.parse(
        Buffer.from(body, 'base64url').toString('utf8'),
      ) as GalleryTokenPayload;
      if (!payload.exp || payload.exp <= Date.now()) return null;
      return payload;
    } catch {
      return null;
    }
  }

  tokenHash(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }

  private async effective(
    eventId: string,
    albumId?: string,
  ): Promise<EffectiveAccess> {
    const event = await this.eventModel
      .findOne({
        _id: this.objectId(eventId),
        isActive: true,
        isPublished: true,
      })
      .select('+galleryPasswordHash')
      .lean();
    if (!event) throw new HttpException('Gallery not found', 404);

    let album: Record<string, any> | null = null;
    if (albumId) {
      album = await this.albumModel
        .findOne({
          _id: this.objectId(albumId),
          eventId: this.objectId(eventId),
        })
        .select('+galleryPasswordHash')
        .lean();
      if (!album) throw new HttpException('Album not found', 404);
    }

    const albumMode = album?.galleryVisibility as GalleryAccessMode | undefined;
    const mode =
      albumMode && albumMode !== GalleryAccessMode.INHERIT
        ? albumMode
        : (event.galleryVisibility as GalleryAccessMode | undefined) ||
          GalleryAccessMode.PUBLIC;
    const passwordHash =
      albumMode && albumMode !== GalleryAccessMode.INHERIT
        ? album?.galleryPasswordHash
        : event.galleryPasswordHash;
    const version = `${event.galleryAccessVersion || 1}:${album?.galleryAccessVersion || 1}`;
    return { event, album, mode, passwordHash, version };
  }

  private tokenMatches(
    payload: GalleryTokenPayload | null,
    access: EffectiveAccess,
    eventId: string,
    albumId?: string,
    scopes: TokenScope[] = ['gallery'],
  ) {
    if (!payload || payload.eventId !== eventId || !scopes.includes(payload.scope)) {
      return false;
    }
    const exactAlbum = (payload.albumId || '') === (albumId || '');
    const eventWideInheritedAlbum = Boolean(
      albumId &&
        !payload.albumId &&
        access.album?.galleryVisibility === GalleryAccessMode.INHERIT &&
        payload.version.split(':')[0] === access.version.split(':')[0],
    );
    return Boolean(
      (exactAlbum && payload.version === access.version) ||
        eventWideInheritedAlbum,
    );
  }

  async assertCanView(
    eventId: string,
    albumId?: string,
    accessToken?: string,
    allowFacial = false,
  ) {
    const access = await this.effective(eventId, albumId);
    if (access.mode === GalleryAccessMode.PUBLIC) return access;
    if (access.mode === GalleryAccessMode.FACIAL && allowFacial) return access;

    const payload = this.decode(accessToken);
    if (!this.tokenMatches(payload, access, eventId, albumId, ['gallery'])) {
      if (access.mode === GalleryAccessMode.FACIAL) {
        throw new ForbiddenException('FACE_SEARCH_REQUIRED');
      }
      throw new ForbiddenException('GALLERY_ACCESS_REQUIRED');
    }
    return access;
  }

  async assertFacialBlurPreview(eventId: string, albumId?: string) {
    const access = await this.effective(eventId, albumId);
    const mode = access.event.facialPrivacyMode || FacialPrivacyMode.HIDE_NON_MATCHES;
    if (access.mode !== GalleryAccessMode.FACIAL || mode !== FacialPrivacyMode.BLUR_NON_MATCHES) {
      throw new ForbiddenException('FACIAL_BLUR_PREVIEW_DISABLED');
    }
    return access;
  }

  async assertFaceSearchAllowed(
    eventId: string,
    albumId?: string,
    accessToken?: string,
  ) {
    const access = await this.effective(eventId, albumId);
    if (!access.event.faceSearchEnabled) {
      throw new ForbiddenException('Face search is disabled for this event');
    }
    if (
      [GalleryAccessMode.PRIVATE, GalleryAccessMode.PASSWORD].includes(
        access.mode,
      )
    ) {
      const payload = this.decode(accessToken);
      if (!this.tokenMatches(payload, access, eventId, albumId, ['gallery'])) {
        throw new ForbiddenException('GALLERY_ACCESS_REQUIRED');
      }
    }
    return access;
  }

  async publicInfo(eventId: string, albumId?: string, accessToken?: string) {
    const access = await this.effective(eventId, albumId);
    const payload = this.decode(accessToken);
    const unlocked =
      access.mode === GalleryAccessMode.PUBLIC ||
      this.tokenMatches(payload, access, eventId, albumId, ['gallery']);
    const event = access.event;
    return {
      eventId,
      albumId,
      title: access.album?.title || event.title,
      description: access.album?.description || event.description,
      image: event.image,
      visibility: access.mode,
      unlocked,
      requiresPassword: access.mode === GalleryAccessMode.PASSWORD && !unlocked,
      requiresPrivateLink:
        access.mode === GalleryAccessMode.PRIVATE && !unlocked,
      requiresFaceSearch: access.mode === GalleryAccessMode.FACIAL && !unlocked,
      facialPrivacyMode:
        event.facialPrivacyMode || FacialPrivacyMode.HIDE_NON_MATCHES,
      faceSearchEnabled: event.faceSearchEnabled === true,
      faceConsentRequired: event.faceConsentRequired !== false,
      guestNotificationsEnabled: event.guestNotificationsEnabled === true,
      branding: event.branding || {},
      gallerySlug: event.gallerySlug,
      customDomain: event.customDomain,
    };
  }

  async resolvePublicGallery(slug?: string, domain?: string) {
    const normalizedSlug = slug?.trim().toLowerCase();
    const normalizedDomain = domain?.trim().toLowerCase().split(':')[0];
    if (!normalizedSlug && !normalizedDomain) {
      throw new HttpException('Gallery slug or domain is required', 400);
    }
    const event = await this.eventModel
      .findOne({
        isActive: true,
        isPublished: true,
        ...(normalizedSlug ? { gallerySlug: normalizedSlug } : {}),
        ...(normalizedDomain
          ? {
              customDomain: {
                $regex: `^${normalizedDomain.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\$&')}$`,
                $options: 'i',
              },
            }
          : {}),
      })
      .select('_id gallerySlug customDomain')
      .lean();
    if (!event) throw new HttpException('Gallery not found', 404);
    return {
      eventId: String(event._id),
      gallerySlug: event.gallerySlug,
      customDomain: event.customDomain,
    };
  }

  async getSettings(eventId: string, actorId?: string, actorRole?: string) {
    await this.members.assertCanManage(eventId, actorId, actorRole);
    const event = await this.eventModel.findById(eventId).lean();
    if (!event) throw new HttpException('Event not found', 404);
    return { data: event };
  }

  async updateSettings(
    dto: GallerySettingsDto,
    actorId?: string,
    actorRole?: string,
  ) {
    await this.members.assertCanManage(dto.eventId, actorId, actorRole);
    if (dto.albumId) return this.updateAlbumSettings(dto, actorId);
    if (dto.visibility === GalleryAccessMode.INHERIT) {
      throw new HttpException('Event visibility cannot inherit', 400);
    }
    if (dto.publishPolicy === 'inherit') {
      throw new HttpException('Event publish policy cannot inherit', 400);
    }

    const set: Record<string, unknown> = {};
    const unset: Record<string, 1> = {};
    const copy = [
      'visibility',
      'facialPrivacyMode',
      'faceSearchEnabled',
      'faceConsentRequired',
      'faceRetentionDays',
      'guestNotificationsEnabled',
      'emailNotificationsEnabled',
      'whatsappNotificationsEnabled',
      'publishPolicy',
      'customDomain',
    ] as const;
    for (const key of copy) {
      const value = dto[key];
      if (value !== undefined) {
        set[key === 'visibility' ? 'galleryVisibility' : key] = value;
      }
    }
    if (dto.publishPolicy === 'auto_ai') set.autoEnhanceImages = true;
    if (dto.branding !== undefined) set.branding = dto.branding;

    if (dto.gallerySlug !== undefined) {
      const slug = dto.gallerySlug.trim().toLowerCase();
      if (slug && !/^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$/.test(slug)) {
        throw new HttpException(
          'Gallery slug must use letters, numbers and hyphens',
          400,
        );
      }
      if (slug) {
        const duplicate = await this.eventModel.exists({
          gallerySlug: slug,
          _id: { $ne: this.objectId(dto.eventId) },
        });
        if (duplicate)
          throw new HttpException('Gallery slug is already in use', 409);
        set.gallerySlug = slug;
      } else unset.gallerySlug = 1;
    }

    let bumpAccess = dto.visibility !== undefined;
    if (dto.password !== undefined) {
      bumpAccess = true;
      const password = dto.password.trim();
      if (password) set.galleryPasswordHash = await bcrypt.hash(password, 10);
      else unset.galleryPasswordHash = 1;
    }

    const update: Record<string, unknown> = { $set: set };
    if (Object.keys(unset).length) update.$unset = unset;
    if (bumpAccess) update.$inc = { galleryAccessVersion: 1 };
    const data = await this.eventModel
      .findByIdAndUpdate(dto.eventId, update, { new: true })
      .lean();
    await this.audit(dto.eventId, dto.albumId, 'settings.updated', actorId, {
      visibility: dto.visibility,
      faceSearchEnabled: dto.faceSearchEnabled,
    });
    return { message: 'Gallery settings updated', data };
  }

  private async updateAlbumSettings(dto: GallerySettingsDto, actorId?: string) {
    const album = await this.albumModel
      .findOne({
        _id: this.objectId(dto.albumId!),
        eventId: this.objectId(dto.eventId),
      })
      .lean();
    if (!album) throw new HttpException('Album not found', 404);
    const set: Record<string, unknown> = {};
    const unset: Record<string, 1> = {};
    if (dto.visibility !== undefined) set.galleryVisibility = dto.visibility;
    if (dto.publishPolicy !== undefined) set.publishPolicy = dto.publishPolicy;
    if (dto.password !== undefined) {
      const password = dto.password.trim();
      if (password) set.galleryPasswordHash = await bcrypt.hash(password, 10);
      else unset.galleryPasswordHash = 1;
    }
    const update: Record<string, unknown> = {
      $set: set,
      $inc: { galleryAccessVersion: 1 },
    };
    if (Object.keys(unset).length) update.$unset = unset;
    const data = await this.albumModel
      .findByIdAndUpdate(dto.albumId, update, { new: true })
      .lean();
    await this.audit(
      dto.eventId,
      dto.albumId,
      'album.settings.updated',
      actorId,
      {
        visibility: dto.visibility,
      },
    );
    return { message: 'Album privacy updated', data };
  }

  async unlock(dto: GalleryUnlockDto) {
    const access = await this.effective(dto.eventId, dto.albumId);
    if (access.mode !== GalleryAccessMode.PASSWORD || !access.passwordHash) {
      throw new HttpException('This gallery does not require a password', 400);
    }
    if (!(await bcrypt.compare(dto.password, access.passwordHash))) {
      throw new ForbiddenException('Invalid gallery password');
    }
    const token = this.issueToken(
      dto.eventId,
      dto.albumId,
      access.version,
      'gallery',
      12,
    );
    await this.audit(
      dto.eventId,
      dto.albumId,
      'password.unlocked',
      undefined,
      {},
    );
    return { accessToken: token, expiresInHours: 12 };
  }

  async createPrivateLink(
    dto: GalleryLinkDto,
    actorId?: string,
    actorRole?: string,
  ) {
    await this.members.assertCanManage(dto.eventId, actorId, actorRole);
    const access = await this.effective(dto.eventId, dto.albumId);
    const hours = dto.ttlHours || 72;
    const accessToken = this.issueToken(
      dto.eventId,
      dto.albumId,
      access.version,
      'gallery',
      hours,
    );
    await this.audit(
      dto.eventId,
      dto.albumId,
      'private-link.created',
      actorId,
      {
        ttlHours: hours,
      },
    );
    return { accessToken, expiresInHours: hours };
  }

  async revoke(
    eventId: string,
    albumId: string | undefined,
    actorId?: string,
    actorRole?: string,
  ) {
    await this.members.assertCanManage(eventId, actorId, actorRole);
    if (albumId) {
      await this.albumModel.updateOne(
        { _id: this.objectId(albumId), eventId: this.objectId(eventId) },
        { $inc: { galleryAccessVersion: 1 } },
      );
    } else {
      await this.eventModel.updateOne(
        { _id: this.objectId(eventId) },
        { $inc: { galleryAccessVersion: 1 } },
      );
    }
    await this.audit(eventId, albumId, 'access.revoked', actorId, {});
    return { message: 'Existing gallery access links revoked' };
  }

  async issuePersonalToken(eventId: string, albumId?: string, hours = 24 * 30) {
    const access = await this.effective(eventId, albumId);
    return this.issueToken(eventId, albumId, access.version, 'personal', hours);
  }

  private issueToken(
    eventId: string,
    albumId: string | undefined,
    version: string,
    scope: TokenScope,
    hours: number,
  ) {
    return this.encode({
      eventId,
      albumId,
      version,
      scope,
      exp: Date.now() + hours * 60 * 60 * 1000,
    });
  }

  private async audit(
    eventId: string,
    albumId: string | undefined,
    action: string,
    actorId: string | undefined,
    metadata: Record<string, unknown>,
  ) {
    await this.auditModel.create({
      eventId: this.objectId(eventId),
      albumId: albumId ? this.objectId(albumId) : undefined,
      action,
      actorId,
      source: 'api',
      metadata,
    });
  }
}
