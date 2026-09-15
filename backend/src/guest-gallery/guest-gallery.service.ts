import {
  HttpException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectModel } from '@nestjs/mongoose';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from 'crypto';
import { Model, Types } from 'mongoose';
import { EventMemberService } from '../event-member/event-member.service';
import {
  EventImage,
  EventImageDocument,
} from '../event-image/entities/event-image.entity';
import { FaceVectorService } from '../face-search/face-vector.service';
import { QdrantFaceService } from '../face-search/qdrant-face.service';
import { GalleryAccessService } from '../gallery-access/gallery-access.service';
import { NotificationService } from '../notification/notification.service';
import { Event, EventDocument } from '../event/entities/event.entity';
import {
  DeleteGuestDto,
  PersonalGalleryQueryDto,
  RegisterGuestDto,
  UpdateGuestPreferencesDto,
} from './dto/guest-gallery.dto';
import {
  GuestFaceRegistration,
  GuestFaceRegistrationDocument,
} from './entities/guest-face-registration.entity';
import {
  GuestNotification,
  GuestNotificationDocument,
  GuestNotificationStatus,
} from './entities/guest-notification.entity';

@Injectable()
export class GuestGalleryService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(GuestGalleryService.name);
  private worker?: ReturnType<typeof setInterval>;

  constructor(
    @InjectModel(GuestFaceRegistration.name)
    private readonly registrations: Model<GuestFaceRegistrationDocument>,
    @InjectModel(GuestNotification.name)
    private readonly notifications: Model<GuestNotificationDocument>,
    @InjectModel(EventImage.name)
    private readonly eventImages: Model<EventImageDocument>,
    @InjectModel(Event.name) private readonly events: Model<EventDocument>,
    private readonly faceVectors: FaceVectorService,
    private readonly qdrant: QdrantFaceService,
    private readonly galleryAccess: GalleryAccessService,
    private readonly members: EventMemberService,
    private readonly config: ConfigService,
    private readonly notifier: NotificationService,
  ) {}

  onModuleInit() {
    this.worker = setInterval(() => void this.flushNotifications(), 15000);
    this.worker.unref?.();
    void this.flushNotifications();
  }

  onModuleDestroy() {
    if (this.worker) clearInterval(this.worker);
  }

  private objectId(id: string) {
    if (!Types.ObjectId.isValid(id)) throw new HttpException('Invalid id', 400);
    return new Types.ObjectId(id);
  }

  private mobileLookupHash(value?: string) {
    const normalized = (value || '').replace(/\\D/g, '');
    return normalized
      ? createHash('sha256').update(normalized).digest('hex')
      : '';
  }

  private emailLookupHash(value?: string) {
    const normalized = (value || '').trim().toLowerCase();
    return normalized
      ? createHash('sha256').update(normalized).digest('hex')
      : '';
  }

  private cosine(a: number[], b: number[]) {
    if (!a.length || a.length !== b.length) return 0;
    let dot = 0;
    let aa = 0;
    let bb = 0;
    for (let i = 0; i < a.length; i += 1) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    return aa > 0 && bb > 0 ? dot / Math.sqrt(aa * bb) : 0;
  }

  private vectorsMatch(existing: number[][], incoming: number[][]) {
    const threshold =
      Number(this.config.get<string>('GLOBAL_FACE_MERGE_SCORE')) || 0.62;
    return incoming.some((next) =>
      existing.some((current) => this.cosine(current, next) >= threshold),
    );
  }

  private cryptoKey() {
    const secret =
      this.config.get<string>('GUEST_TOKEN_SECRET') ||
      this.config.get<string>('GALLERY_ACCESS_SECRET') ||
      this.config.get<string>('ACCESS_TOKEN') ||
      'change-guest-token-secret';
    return createHash('sha256').update(secret).digest();
  }

  private encryptToken(token: string) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.cryptoKey(), iv);
    const encrypted = Buffer.concat([
      cipher.update(token, 'utf8'),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();
    return Buffer.concat([iv, tag, encrypted]).toString('base64url');
  }

  private decryptToken(value: string) {
    const packed = Buffer.from(value, 'base64url');
    const iv = packed.subarray(0, 12);
    const tag = packed.subarray(12, 28);
    const encrypted = packed.subarray(28);
    const decipher = createDecipheriv('aes-256-gcm', this.cryptoKey(), iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([
      decipher.update(encrypted),
      decipher.final(),
    ]).toString('utf8');
  }

  private async registration(eventId: string, token: string) {
    this.objectId(eventId);
    return this.registrations
      .findOne({
        tokenHash: this.galleryAccess.tokenHash(token),
        $or: [
          { globalProfile: true },
          { eventId: this.objectId(eventId), expiresAt: { $gt: new Date() } },
        ],
      })
      .select('+faceVectors +tokenCipher +selfieFingerprints')
      .exec();
  }

  async register(files: Express.Multer.File[], dto: RegisterGuestDto) {
    if (!dto.consent) {
      throw new HttpException('Face-search consent is required', 400);
    }
    const selfies = (files || [])
      .filter((file) => Boolean(file?.buffer))
      .slice(0, 5);
    const globalProfile = dto.globalProfile === true;
    if (!selfies.length)
      throw new HttpException('Selfie image is required', 400);
    if (globalProfile && selfies.length < 2) {
      throw new HttpException(
        'Take at least 2 selfies for a global face profile',
        400,
      );
    }
    if (globalProfile && (!dto.email?.trim() || !dto.whatsapp?.trim())) {
      throw new HttpException(
        'Email and WhatsApp are required for global face delivery',
        400,
      );
    }

    const access = globalProfile
      ? null
      : await this.galleryAccess.assertFaceSearchAllowed(
          dto.eventId,
          dto.albumId,
          dto.accessToken,
        );
    if (globalProfile) {
      const info = await this.galleryAccess.publicInfo(
        dto.eventId,
        dto.albumId,
        dto.accessToken,
      );
      if (!info.faceSearchEnabled) {
        throw new HttpException('Face search is disabled for this event', 403);
      }
    }
    const vectors: number[][] = [];
    const fingerprints: string[] = [];
    let usableSelfies = 0;
    for (const file of selfies) {
      const result = await this.faceVectors.detectAndVectorFromBuffer(
        file.buffer,
        file.originalname || 'selfie.jpg',
        file.mimetype || 'image/jpeg',
      );
      if (!result.faces.length || !result.vectors.length) continue;
      usableSelfies += 1;
      vectors.push(...result.vectors);
      fingerprints.push(createHash('sha256').update(file.buffer).digest('hex'));
    }
    if (!vectors.length || (globalProfile && usableSelfies < 2)) {
      throw new HttpException(
        globalProfile
          ? 'At least 2 selfies must contain a clear usable face'
          : 'No usable face found in selfie',
        400,
      );
    }

    const email = dto.email?.trim().toLowerCase() || undefined;
    const whatsapp = dto.whatsapp?.trim() || undefined;
    const emailLookupHash = this.emailLookupHash(email) || undefined;
    const mobileLookupHash = this.mobileLookupHash(whatsapp) || undefined;
    const notifyEmail = dto.notifyEmail === true && Boolean(email);
    const notifyWhatsapp = dto.notifyWhatsapp === true && Boolean(whatsapp);
    let token = randomBytes(32).toString('base64url');
    let updatedGlobalProfile = false;
    let data: GuestFaceRegistrationDocument;

    if (globalProfile) {
      let existing = await this.registrations
        .findOne({ globalProfile: true, emailLookupHash, mobileLookupHash })
        .select('+faceVectors +tokenCipher +selfieFingerprints')
        .exec();
      if (existing && !this.vectorsMatch(existing.faceVectors || [], vectors)) {
        existing = null;
      }
      if (existing) {
        token = this.decryptToken(existing.tokenCipher);
        existing.faceVectors = [
          ...(existing.faceVectors || []),
          ...vectors,
        ].slice(-50);
        existing.selfieFingerprints = [
          ...new Set([...(existing.selfieFingerprints || []), ...fingerprints]),
        ].slice(-50);
        existing.email = email;
        existing.whatsapp = whatsapp;
        existing.emailLookupHash = emailLookupHash;
        existing.mobileLookupHash = mobileLookupHash;
        existing.notifyEmail = notifyEmail;
        existing.notifyWhatsapp = notifyWhatsapp;
        existing.lastSeenAt = new Date();
        existing.consentAt = new Date();
        existing.profileRevision = (existing.profileRevision || 1) + 1;
        data = await existing.save();
        updatedGlobalProfile = true;
      } else {
        data = await this.registrations.create({
          eventId: this.objectId(dto.eventId),
          albumId: dto.albumId ? this.objectId(dto.albumId) : undefined,
          tokenHash: this.galleryAccess.tokenHash(token),
          tokenCipher: this.encryptToken(token),
          faceVectors: vectors,
          email,
          whatsapp,
          emailLookupHash,
          mobileLookupHash,
          globalProfile: true,
          profileRevision: 1,
          notifyEmail,
          notifyWhatsapp,
          consentAt: new Date(),
          consentSource: 'global-face-qr',
          lastSeenAt: new Date(),
          selfieFingerprint: fingerprints[0],
          selfieFingerprints: fingerprints,
        });
      }
    } else {
      const retentionDays = Math.min(
        Math.max(Number(access!.event.faceRetentionDays) || 30, 1),
        365,
      );
      data = await this.registrations.create({
        eventId: this.objectId(dto.eventId),
        albumId: dto.albumId ? this.objectId(dto.albumId) : undefined,
        tokenHash: this.galleryAccess.tokenHash(token),
        tokenCipher: this.encryptToken(token),
        faceVectors: vectors,
        email,
        whatsapp,
        emailLookupHash,
        mobileLookupHash,
        globalProfile: false,
        notifyEmail,
        notifyWhatsapp,
        consentAt: new Date(),
        consentSource: 'public-gallery',
        expiresAt: new Date(Date.now() + retentionDays * 86400000),
        selfieFingerprint: fingerprints[0],
        selfieFingerprints: fingerprints,
      });
    }

    return {
      message: updatedGlobalProfile
        ? 'Global face profile updated'
        : 'Personal gallery created',
      guestToken: token,
      expiresAt: data.expiresAt || null,
      registrationId: String(data._id),
      globalProfile: data.globalProfile === true,
      updatedGlobalProfile,
      profileRevision: data.profileRevision || 1,
      storedFaceSamples: data.faceVectors?.length || vectors.length,
      notificationPreferences: {
        email: data.notifyEmail,
        whatsapp: data.notifyWhatsapp,
      },
    };
  }

  async personal(query: PersonalGalleryQueryDto) {
    const registration = await this.registration(
      query.eventId,
      query.guestToken,
    );
    if (!registration)
      throw new HttpException(
        'Personal gallery link is invalid or expired',
        401,
      );
    const event = await this.events
      .findOne({
        _id: this.objectId(query.eventId),
        isActive: true,
        isPublished: true,
        faceSearchEnabled: true,
      })
      .select(
        'title description image branding facialPrivacyMode faceRetentionDays',
      )
      .lean();
    if (!event) throw new HttpException('Personal gallery is unavailable', 404);

    const albumId =
      query.albumId ||
      (registration.albumId ? String(registration.albumId) : undefined);
    const results = (
      await Promise.all(
        registration.faceVectors.map((vector) =>
          this.qdrant.search(vector, query.eventId, 10000),
        ),
      )
    ).flat();
    const scores = new Map<string, number>();
    for (const result of results) {
      const ids = [
        ...(result.payload?.eventImageIds || []),
        result.payload?.eventImageId,
      ].filter((id): id is string => Boolean(id && Types.ObjectId.isValid(id)));
      for (const id of ids)
        scores.set(id, Math.max(scores.get(id) || 0, result.score));
    }

    const ids = [...scores.keys()].map((id) => this.objectId(id));
    const data = ids.length
      ? await this.eventImages
          .find({
            _id: { $in: ids },
            eventId: this.objectId(query.eventId),
            isPublished: { $ne: false },
            ...(albumId ? { albumId: this.objectId(albumId) } : {}),
          })
          .populate('albumId', 'title description')
          .populate('userTakenBy', 'name')
          .lean()
      : [];
    data.sort(
      (a, b) =>
        (scores.get(String(b._id)) || 0) - (scores.get(String(a._id)) || 0),
    );
    const accessTokenHours = registration.globalProfile
      ? 24 * 30
      : Math.max(
          1,
          Math.ceil(
            ((registration.expiresAt?.getTime() || Date.now()) - Date.now()) /
              3600000,
          ),
        );
    const accessToken = await this.galleryAccess.issuePersonalToken(
      query.eventId,
      albumId,
      accessTokenHours,
    );
    return {
      data,
      totalItems: data.length,
      accessToken,
      expiresAt: registration.expiresAt,
      notificationPreferences: {
        email: registration.email,
        whatsapp: registration.whatsapp,
        notifyEmail: registration.notifyEmail,
        notifyWhatsapp: registration.notifyWhatsapp,
      },
      event: {
        title: event.title,
        description: event.description,
        image: event.image,
        branding: event.branding || {},
        facialPrivacyMode: event.facialPrivacyMode,
      },
    };
  }

  async personalByMobile(eventId: string, mobile: string, albumId?: string) {
    const mobileLookupHash = this.mobileLookupHash(mobile);
    if (!mobileLookupHash)
      throw new HttpException('Mobile number is required', 400);
    const registration = await this.registrations
      .findOne({
        mobileLookupHash,
        $or: [
          { globalProfile: true },
          { eventId: this.objectId(eventId), expiresAt: { $gt: new Date() } },
        ],
      })
      .select('+tokenCipher')
      .sort({ createdAt: -1 })
      .exec();
    if (!registration) return { data: [], totalItems: 0 };
    const guestToken = this.decryptToken(registration.tokenCipher);
    const result = await this.personal({ eventId, albumId, guestToken });
    return {
      data: result.data,
      totalItems: result.totalItems,
      event: result.event,
    };
  }
  async updatePreferences(dto: UpdateGuestPreferencesDto) {
    const registration = await this.registration(dto.eventId, dto.guestToken);
    if (!registration)
      throw new HttpException('Personal gallery is invalid or expired', 401);
    if (dto.email !== undefined) {
      registration.email = dto.email.trim().toLowerCase() || undefined;
      registration.emailLookupHash =
        this.emailLookupHash(dto.email) || undefined;
    }
    if (dto.whatsapp !== undefined) {
      registration.whatsapp = dto.whatsapp.trim() || undefined;
      registration.mobileLookupHash =
        this.mobileLookupHash(dto.whatsapp) || undefined;
    }
    if (dto.notifyEmail !== undefined) {
      registration.notifyEmail = dto.notifyEmail && Boolean(registration.email);
    }
    if (dto.notifyWhatsapp !== undefined) {
      registration.notifyWhatsapp =
        dto.notifyWhatsapp && Boolean(registration.whatsapp);
    }
    await registration.save();
    return {
      message: 'Notification preferences updated',
      notificationPreferences: {
        email: registration.email,
        whatsapp: registration.whatsapp,
        notifyEmail: registration.notifyEmail,
        notifyWhatsapp: registration.notifyWhatsapp,
      },
    };
  }

  async deleteRegistration(dto: DeleteGuestDto) {
    const registration = await this.registration(dto.eventId, dto.guestToken);
    if (!registration) return { message: 'Personal gallery already removed' };
    await Promise.all([
      this.notifications.deleteMany({ registrationId: registration._id }),
      this.registrations.deleteOne({ _id: registration._id }),
    ]);
    return { message: 'Selfie profile and personal gallery access removed' };
  }

  async onPhotoIndexed(eventImage: EventImageDocument) {
    const event = await this.events
      .findById(eventImage.eventId)
      .select(
        'faceSearchEnabled guestNotificationsEnabled emailNotificationsEnabled whatsappNotificationsEnabled',
      )
      .lean();
    if (!event?.faceSearchEnabled || !event.guestNotificationsEnabled) return;

    const targetId = String(eventImage._id);
    const cursor = this.registrations
      .find({
        $or: [
          { globalProfile: true },
          { eventId: eventImage.eventId, expiresAt: { $gt: new Date() } },
        ],
      })
      .select('+faceVectors')
      .cursor();
    let batch: GuestFaceRegistrationDocument[] = [];
    for await (const registration of cursor) {
      batch.push(registration);
      if (batch.length < 10) continue;
      await Promise.allSettled(
        batch.map((item) =>
          this.matchNewPhoto(item, eventImage, event, targetId),
        ),
      );
      batch = [];
    }
    if (batch.length) {
      await Promise.allSettled(
        batch.map((item) =>
          this.matchNewPhoto(item, eventImage, event, targetId),
        ),
      );
    }
  }

  private async matchNewPhoto(
    registration: GuestFaceRegistrationDocument,
    eventImage: EventImageDocument,
    event: Record<string, any>,
    targetId: string,
  ) {
    let matched = false;
    for (const vector of registration.faceVectors) {
      const results = await this.qdrant.search(
        vector,
        String(eventImage.eventId),
        20,
      );
      matched = results.some((result) => {
        const ids = [
          ...(result.payload?.eventImageIds || []),
          result.payload?.eventImageId,
        ];
        return ids.includes(targetId);
      });
      if (matched) break;
    }
    if (!matched) return;
    registration.lastMatchedAt = new Date();
    await registration.save();
    await this.queueNotifications(registration, eventImage, event);
  }

  private async queueNotifications(
    registration: GuestFaceRegistrationDocument,
    eventImage: EventImageDocument,
    event: Record<string, any>,
  ) {
    const batchSeconds = Math.max(
      Number(this.config.get<string>('GUEST_NOTIFICATION_BATCH_SECONDS')) || 45,
      5,
    );
    const sendAfter = new Date(Date.now() + batchSeconds * 1000);
    const channels: Array<'email' | 'whatsapp'> = [];
    if (
      registration.notifyEmail &&
      event.emailNotificationsEnabled !== false &&
      this.notifier.emailConfigured()
    )
      channels.push('email');
    if (
      registration.notifyWhatsapp &&
      event.whatsappNotificationsEnabled === true &&
      this.notifier.whatsappConfigured()
    )
      channels.push('whatsapp');

    for (const channel of channels) {
      const delivered = await this.notifications.exists({
        eventId: eventImage.eventId,
        registrationId: registration._id,
        channel,
        photoIds: eventImage._id,
        status: {
          $in: [
            GuestNotificationStatus.PENDING,
            GuestNotificationStatus.SENDING,
            GuestNotificationStatus.SENT,
          ],
        },
      });
      if (delivered) continue;
      const existing = await this.notifications.findOne({
        eventId: eventImage.eventId,
        registrationId: registration._id,
        channel,
        status: GuestNotificationStatus.PENDING,
      });
      if (existing) {
        await this.notifications.updateOne(
          { _id: existing._id },
          { $addToSet: { photoIds: eventImage._id } },
        );
        continue;
      }
      await this.notifications.create({
        eventId: eventImage.eventId,
        registrationId: registration._id,
        channel,
        photoIds: [eventImage._id],
        status: GuestNotificationStatus.PENDING,
        sendAfter,
      });
    }
  }

  private async flushNotifications() {
    try {
      const pending = await this.notifications
        .find({
          status: GuestNotificationStatus.PENDING,
          sendAfter: { $lte: new Date() },
        })
        .sort({ sendAfter: 1 })
        .limit(30)
        .exec();
      for (const item of pending) await this.deliver(item);
    } catch (error) {
      this.logger.warn(`guest-notification-worker ${String(error)}`);
    }
  }

  private async deliver(item: GuestNotificationDocument) {
    if (item.channel === 'email' && !this.notifier.emailConfigured()) return;
    if (item.channel === 'whatsapp' && !this.notifier.whatsappConfigured())
      return;
    const claimed = await this.notifications.findOneAndUpdate(
      { _id: item._id, status: GuestNotificationStatus.PENDING },
      { $set: { status: GuestNotificationStatus.SENDING } },
      { new: true },
    );
    if (!claimed) return;
    try {
      const registration = await this.registrations
        .findById(claimed.registrationId)
        .select('+tokenCipher')
        .exec();
      const event = await this.events
        .findById(claimed.eventId)
        .select('title')
        .lean();
      if (!registration || !event)
        throw new Error('Guest or event no longer exists');
      const destination =
        claimed.channel === 'email'
          ? registration.email
          : registration.whatsapp;
      if (!destination) throw new Error('Notification destination is missing');
      const token = this.decryptToken(registration.tokenCipher);
      const appUrl = (
        this.config.get<string>('PUBLIC_APP_URL') ||
        this.config.get<string>('CORS_ORIGIN')?.split(',')[0] ||
        'http://localhost:5173'
      ).replace(/\/$/, '');
      const galleryUrl = `${appUrl}/#/event/${String(claimed.eventId)}?guest=${encodeURIComponent(token)}`;
      await this.notifier.sendGuestMatch(
        {
          email: registration.email,
          whatsapp: registration.whatsapp,
          eventTitle: event.title,
          link: galleryUrl,
          photoCount: claimed.photoIds.length,
        },
        claimed.channel,
      );
      await this.notifications.updateOne(
        { _id: claimed._id },
        {
          $set: { status: GuestNotificationStatus.SENT, sentAt: new Date() },
          $unset: { error: '' },
        },
      );
      registration.lastNotificationAt = new Date();
      await registration.save();
    } catch (error) {
      const attempts = claimed.attempts + 1;
      const finalFailure = attempts >= 5;
      await this.notifications.updateOne(
        { _id: claimed._id },
        {
          $set: {
            attempts,
            status: finalFailure
              ? GuestNotificationStatus.FAILED
              : GuestNotificationStatus.PENDING,
            sendAfter: new Date(
              Date.now() + Math.min(30, 2 ** attempts) * 60000,
            ),
            error: error instanceof Error ? error.message : String(error),
          },
        },
      );
    }
  }

  async plannerStatus(eventId: string, actorId?: string, actorRole?: string) {
    await this.members.assertCanManage(eventId, actorId, actorRole);
    const oid = this.objectId(eventId);
    const [registrations, notificationCounts, recent] = await Promise.all([
      this.registrations.countDocuments({
        eventId: oid,
        expiresAt: { $gt: new Date() },
      }),
      this.notifications.aggregate<{ _id: string; count: number }>([
        { $match: { eventId: oid } },
        { $group: { _id: '$status', count: { $sum: 1 } } },
      ]),
      this.notifications
        .find({ eventId: oid })
        .sort({ createdAt: -1 })
        .limit(20)
        .lean(),
    ]);
    return {
      registrations,
      notifications: Object.fromEntries(
        notificationCounts.map((row) => [row._id, row.count]),
      ),
      recent,
    };
  }
}
