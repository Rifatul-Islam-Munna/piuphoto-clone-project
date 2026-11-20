import {
  CreateBucketCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadBucketCommand,
  PutBucketPolicyCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import {
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
  StreamableFile,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createReadStream } from 'fs';
import { stat } from 'fs/promises';
import { createHmac, randomUUID, timingSafeEqual } from 'crypto';
import { extname } from 'path';
import { Readable } from 'stream';
import { MAX_UPLOAD_SIZE, PresignUploadDto } from '../image/dto/presign-upload.dto';

@Injectable()
export class MinioService implements OnModuleInit, OnModuleDestroy {
  private logger = new Logger(MinioService.name);

  constructor(private configService: ConfigService) {}

  private s3: S3Client;
  private bucketName: string;
  private publicUrl: string;
  private urlSecret: string;

  async onModuleInit() {
    const storageUrl = this.configService.get<string>('STORAGE_S3_URL')?.trim();
    const isR2 = Boolean(storageUrl);
    const endpoint = new URL(
      storageUrl || this.configService.getOrThrow<string>('MINIO_URL'),
    );
    const bucketInUrl = decodeURIComponent(endpoint.pathname.replace(/^\/+|\/+$/g, ''));
    this.bucketName = isR2
      ? this.configService.get<string>('STORAGE_BUCKET_NAME')?.trim() || bucketInUrl
      : this.configService.get<string>('MINIO_BUCKET_NAME') || 'piuphoto-public-bucket';
    if (!this.bucketName || this.bucketName.includes('/')) {
      throw new Error('Set STORAGE_BUCKET_NAME or include one bucket in STORAGE_S3_URL.');
    }
    if (!['http:', 'https:'].includes(endpoint.protocol) || endpoint.username || endpoint.password || endpoint.search || endpoint.hash) {
      throw new Error('Storage endpoint must be an HTTP(S) URL without credentials, query, or fragment.');
    }

    const accessKeyId = this.configService.getOrThrow<string>(
      isR2 ? 'STORAGE_ACCESS_KEY' : 'MINIO_ACCESS_KEY',
    );
    const secretAccessKey = this.configService.getOrThrow<string>(
      isR2 ? 'STORAGE_SECRET_KEY' : 'MINIO_SECRET_KEY',
    );
    if (!accessKeyId.trim() || !secretAccessKey.trim()) {
      throw new Error('Storage access key and secret key must not be empty.');
    }
    this.urlSecret = this.configService.get<string>('STORAGE_URL_SECRET') || secretAccessKey;
    this.publicUrl = isR2
      ? this.configService.get<string>('STORAGE_PUBLIC_URL')?.trim().replace(/\/+$/, '')
      : `${endpoint.origin}/${this.bucketName}`;
    if (this.publicUrl) {
      const publicEndpoint = new URL(this.publicUrl);
      if (!['http:', 'https:'].includes(publicEndpoint.protocol) || publicEndpoint.username || publicEndpoint.password || publicEndpoint.search || publicEndpoint.hash || (isR2 && publicEndpoint.hostname.endsWith('.r2.cloudflarestorage.com'))) {
        throw new Error('STORAGE_PUBLIC_URL must be a public HTTP(S) bucket URL, not the R2 S3 API endpoint.');
      }
    }

    this.s3 = new S3Client({
      region: isR2 ? 'auto' : 'us-east-1',
      endpoint: endpoint.origin,
      credentials: {
        accessKeyId,
        secretAccessKey,
      },
      forcePathStyle: true,
      // Avoid optional streaming checksum headers unsupported by S3-compatible stores.
      requestChecksumCalculation: 'WHEN_REQUIRED',
      responseChecksumValidation: 'WHEN_REQUIRED',
    });

    await this.createBucketIfNotExists(this.bucketName);
    // R2 does not implement PutBucketPolicy. Public domains are configured in Cloudflare.
    if (!isR2) await this.makeBucketPublic(this.bucketName);
    this.logger.log(`${isR2 ? 'Cloudflare R2' : 'MinIO'} storage ready (${this.bucketName}).`);
  }

  onModuleDestroy() {
    this.s3?.destroy();
  }

  async createBucketIfNotExists(bucketName: string) {
    try {
      await this.s3.send(new HeadBucketCommand({ Bucket: bucketName }));
      return;
    } catch (error: any) {
      if (error?.$metadata?.httpStatusCode !== 404 && !['NoSuchBucket', 'NotFound'].includes(error?.name)) {
        throw error;
      }
    }

    try {
      await this.s3.send(new CreateBucketCommand({ Bucket: bucketName }));
      this.logger.log(`Bucket '${bucketName}' created.`);
    } catch (err: any) {
      if (err?.name === 'BucketAlreadyOwnedByYou' || err?.name === 'BucketAlreadyExists') {
        await this.s3.send(new HeadBucketCommand({ Bucket: bucketName }));
      } else {
        console.error('Error creating bucket:', err);
        throw err;
      }
    }
  }

  private fileToken(fileName: string): string {
    return createHmac('sha256', this.urlSecret)
      .update(JSON.stringify([this.bucketName, fileName]))
      .digest('hex');
  }

  private fileUrl(fileName: string, requestOrigin?: string): string {
    const key = fileName.split('/').map(encodeURIComponent).join('/');
    if (this.publicUrl) return `${this.publicUrl}/${key}`;

    const apiUrl = this.configService.get<string>('PUBLIC_API_URL')?.trim() || requestOrigin;
    if (!apiUrl) {
      throw new Error('PUBLIC_API_URL or an upload request origin is required without STORAGE_PUBLIC_URL.');
    }
    return `${apiUrl.replace(/\/+$/, '')}/image/file/${encodeURIComponent(fileName)}?token=${this.fileToken(fileName)}`;
  }

  /** Resolve public bucket URLs and our HMAC-signed private-file URLs only. */
  private storedObjectKey(fileUrl: string): string {
    let objectUrl: URL;
    try {
      objectUrl = new URL(fileUrl);
    } catch {
      throw new HttpException('Photo is not hosted in configured storage', HttpStatus.BAD_REQUEST);
    }
    if (!['http:', 'https:'].includes(objectUrl.protocol) ||
        objectUrl.username || objectUrl.password) {
      throw new HttpException('Photo is not hosted in configured storage', HttpStatus.BAD_REQUEST);
    }

    let key: string | undefined;
    if (this.publicUrl) {
      const baseUrl = new URL(this.publicUrl);
      const prefix = baseUrl.pathname.endsWith('/')
        ? baseUrl.pathname : baseUrl.pathname + '/';
      if (objectUrl.origin === baseUrl.origin &&
          objectUrl.pathname.startsWith(prefix)) {
        try {
          key = objectUrl.pathname.slice(prefix.length)
            .split('/').map(decodeURIComponent).join('/');
        } catch {
          throw new HttpException('Invalid storage object path', HttpStatus.BAD_REQUEST);
        }
      }
    }

    // R2 without a public bucket domain uses /image/file/:key?token=HMAC.
    // Verify the same bucket/key HMAC used by fileUrl(); never fetch the URL
    // itself or permit an arbitrary host to act as a storage proxy.
    if (!key && objectUrl.pathname.startsWith('/image/file/')) {
      let candidate: string;
      try {
        candidate = decodeURIComponent(objectUrl.pathname.slice('/image/file/'.length));
      } catch {
        throw new HttpException('Invalid storage object path', HttpStatus.BAD_REQUEST);
      }
      const supplied = objectUrl.searchParams.get('token') || '';
      if (/^[a-f0-9]{64}$/i.test(supplied)) {
        const expected = Buffer.from(this.fileToken(candidate), 'hex');
        const received = Buffer.from(supplied, 'hex');
        if (expected.length === received.length && timingSafeEqual(expected, received)) {
          key = candidate;
        }
      }
    }

    if (!key || key.split('/').some((part) => !part || part === '.' || part === '..')) {
      throw new HttpException('Photo is not hosted in configured storage', HttpStatus.BAD_REQUEST);
    }
    return key;
  }

  canStreamStoredUrl(fileUrl: string): boolean {
    try {
      this.storedObjectKey(fileUrl);
      return true;
    } catch {
      return false;
    }
  }

  /** Streams original photo bytes from the authorized R2 / MinIO bucket. */
  async openStoredUrl(fileUrl: string, signal?: AbortSignal): Promise<Readable> {
    const key = this.storedObjectKey(fileUrl);
    const response = await this.s3.send(
      new GetObjectCommand({ Bucket: this.bucketName, Key: key }),
      { abortSignal: signal },
    );
    if (!response.Body) {
      throw new HttpException('Storage photo is unavailable', HttpStatus.NOT_FOUND);
    }
    return response.Body as Readable;
  }

  async presignUpload(file: PresignUploadDto, requestOrigin?: string) {
    if (!file.fileName?.trim() || file.fileName.length > 255 || !Number.isInteger(file.size) || file.size <= 0 || file.size > MAX_UPLOAD_SIZE) {
      throw new HttpException('A file name and size between 1 byte and 256 MiB are required', HttpStatus.BAD_REQUEST);
    }
    const contentType = this.resolveContentType({
      originalname: file.fileName,
      mimetype: file.contentType?.trim() || 'application/octet-stream',
    });
    const allowed = new Set([
      'image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/avif',
      'image/heic', 'image/heif', 'image/tiff', 'image/x-adobe-dng',
      'image/x-sony-arw', 'image/x-canon-cr2', 'image/x-canon-cr3',
      'image/x-nikon-nef', 'image/x-nikon-nrw', 'image/x-fuji-raf',
      'image/x-panasonic-rw2', 'image/x-olympus-orf', 'image/x-pentax-pef',
      'application/pdf', 'video/mp4', 'video/webm', 'video/ogg',
      'video/quicktime', 'video/x-matroska',
    ]);
    if (!allowed.has(contentType)) {
      throw new HttpException('Unsupported image, camera RAW, PDF, or video file', HttpStatus.BAD_REQUEST);
    }
    const extension = extname(file.fileName).toLowerCase();
    const key = `${randomUUID()}${/^\.[a-z0-9]{1,10}$/.test(extension) ? extension : ''}`;
    const url = this.fileUrl(key, requestOrigin);
    const expiresIn = 900;
    const uploadUrl = await getSignedUrl(this.s3, new PutObjectCommand({
      Bucket: this.bucketName,
      Key: key,
      ContentType: contentType,
      ContentLength: file.size,
    }), {
      expiresIn,
      signableHeaders: new Set(['content-type', 'content-length']),
    });

    return { uploadUrl, method: 'PUT' as const, headers: { 'Content-Type': contentType }, key, url, expiresIn };
  }

  async readFile(fileName: string, token: string): Promise<StreamableFile> {
    const expected = Buffer.from(this.fileToken(fileName));
    const supplied = Buffer.from(typeof token === 'string' ? token : '');
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
      throw new HttpException('File not found', HttpStatus.NOT_FOUND);
    }

    try {
      const object = await this.s3.send(new GetObjectCommand({
        Bucket: this.bucketName,
        Key: fileName,
      }));
      return new StreamableFile(object.Body as Readable, {
        type: object.ContentType || 'application/octet-stream',
        length: object.ContentLength,
        disposition: 'inline',
      });
    } catch (error: any) {
      if (error?.name === 'NoSuchKey' || error?.$metadata?.httpStatusCode === 404) {
        throw new HttpException('File not found', HttpStatus.NOT_FOUND);
      }
      this.logger.error('Could not read storage file.');
      throw new HttpException('Failed to read file', HttpStatus.BAD_GATEWAY);
    }
  }

  async makeBucketPublic(bucketName: string) {
    const policy = {
      Version: '2012-10-17',
      Statement: [
        {
          Sid: 'PublicRead',
          Effect: 'Allow',
          Principal: '*',
          Action: ['s3:GetObject'],
          Resource: [`arn:aws:s3:::${bucketName}/*`],
        },
      ],
    };

    const command = new PutBucketPolicyCommand({
      Bucket: bucketName,
      Policy: JSON.stringify(policy),
    });

    try {
      await this.s3.send(command);
      console.log(`Bucket '${bucketName}' is now public.`);
    } catch (err) {
      console.error('Error setting bucket policy:', err);
      throw err;
    }
  }

  private resolveContentType(file: any): string {
    const supplied = file?.mimetype?.toString()?.toLowerCase();
    if (supplied && supplied !== 'application/octet-stream') return supplied;

    const extension = extname(file?.originalname || file?.filename || '').toLowerCase();
    const known: Record<string, string> = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.webp': 'image/webp',
      '.avif': 'image/avif',
      '.heic': 'image/heic',
      '.heif': 'image/heif',
      '.tif': 'image/tiff',
      '.tiff': 'image/tiff',
      '.dng': 'image/x-adobe-dng',
      '.arw': 'image/x-sony-arw',
      '.cr2': 'image/x-canon-cr2',
      '.cr3': 'image/x-canon-cr3',
      '.nef': 'image/x-nikon-nef',
      '.nrw': 'image/x-nikon-nrw',
      '.raf': 'image/x-fuji-raf',
      '.rw2': 'image/x-panasonic-rw2',
      '.orf': 'image/x-olympus-orf',
      '.pef': 'image/x-pentax-pef',
      '.pdf': 'application/pdf',
      '.mp4': 'video/mp4',
      '.m4v': 'video/mp4',
      '.webm': 'video/webm',
      '.ogg': 'video/ogg',
      '.mov': 'video/quicktime',
      '.mkv': 'video/x-matroska',
    };
    return known[extension] || supplied || 'application/octet-stream';
  }

  async uploadFile(filePath: any, requestOrigin?: string) {
    let fileContent: Readable;
    try {
      const url = this.fileUrl(filePath.filename, requestOrigin);
      const metadata = await stat(filePath.path);
      fileContent = createReadStream(filePath.path);

      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: filePath.filename,
        Body: fileContent,
        ContentType: this.resolveContentType(filePath),
        ContentLength: metadata.size,
      });

      await this.s3.send(command);
      return url;
    } catch (err) {
      console.error('Error uploading file:', err);
      throw new HttpException(
        'Failed to upload file',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    } finally {
      fileContent?.destroy();
    }
  }

  async deleteService(fileName: string) {
    if (!fileName || typeof fileName !== 'string') {
      throw new HttpException('Invalid file name', HttpStatus.BAD_REQUEST);
    }

    try {
      const command = new DeleteObjectCommand({
        Bucket: this.bucketName,
        Key: fileName,
      });

      await this.s3.send(command);
      this.logger.debug('file deleted', fileName);
      return true;
    } catch (err) {
      console.error('Error Delete file:', err);
      throw new HttpException(
        'Can not Delete File',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }
}
