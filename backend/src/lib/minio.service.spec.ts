import {
  CreateBucketCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadBucketCommand,
  PutBucketPolicyCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { mkdtemp, unlink, writeFile, rmdir } from 'fs/promises';
import { tmpdir } from 'os';
import { join } from 'path';
import { Readable } from 'stream';
import { MinioService } from './minio.service';

describe('R2 image storage', () => {
  const config = {
    STORAGE_S3_URL: 'https://account.eu.r2.cloudflarestorage.com/gallarista',
    STORAGE_ACCESS_KEY: 'r2-access',
    STORAGE_SECRET_KEY: 'r2-secret',
    MINIO_URL: 'http://localhost:9000',
    MINIO_ACCESS_KEY: 'minio-access',
    MINIO_SECRET_KEY: 'minio-secret',
  };
  let service: MinioService;
  let send: jest.SpyInstance;
  let directory: string;
  let path: string;
  const bytes = Buffer.from('test image content');

  async function initialize(overrides: Record<string, string> = {}) {
    service = new MinioService(new ConfigService({ ...config, ...overrides }));
    await service.onModuleInit();
  }

  async function upload() {
    return service.uploadFile({
      path,
      filename: 'photo with spaces.jpg',
      originalname: 'photo.jpg',
      mimetype: 'application/octet-stream',
    }, 'https://api.example.test');
  }

  beforeAll(async () => {
    directory = await mkdtemp(join(tmpdir(), 'r2-storage-'));
    path = join(directory, 'photo.jpg');
    await writeFile(path, bytes);
  });

  afterAll(async () => {
    await unlink(path);
    await rmdir(directory);
  });

  beforeEach(() => {
    send = jest.spyOn(S3Client.prototype, 'send').mockResolvedValue({} as never);
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
  });

  afterEach(() => {
    service?.onModuleDestroy();
    jest.restoreAllMocks();
  });

  it('uses the EU endpoint and URL bucket without applying unsupported public policies', async () => {
    await initialize();
    expect(send.mock.calls.map(([command]) => command.constructor)).toEqual([HeadBucketCommand]);
    expect(send.mock.calls[0][0].input.Bucket).toBe('gallarista');
    const client = (service as any).s3 as S3Client;
    expect(await client.config.region()).toBe('auto');
    expect(await client.config.endpoint()).toMatchObject({
      hostname: 'account.eu.r2.cloudflarestorage.com',
      path: '/',
    });
    expect(await client.config.credentials()).toMatchObject({ accessKeyId: 'r2-access' });
  });

  it('creates missing buckets, but does not treat permission failures as missing buckets', async () => {
    send.mockRejectedValueOnce({ name: 'NotFound', $metadata: { httpStatusCode: 404 } });
    await initialize();
    expect(send.mock.calls[1][0]).toBeInstanceOf(CreateBucketCommand);
    service.onModuleDestroy();
    send.mockClear();
    const denied = { name: 'Forbidden', $metadata: { httpStatusCode: 403 } };
    send.mockRejectedValueOnce(denied);
    await expect(initialize()).rejects.toBe(denied);
    expect(send).toHaveBeenCalledTimes(1);
  });

  it('accepts an endpoint-only URL with an explicit bucket', async () => {
    await initialize({
      STORAGE_S3_URL: 'https://account.r2.cloudflarestorage.com',
      STORAGE_BUCKET_NAME: 'photos',
    });
    expect(send.mock.calls[0][0].input.Bucket).toBe('photos');
  });

  it('prefers BUCKET over a stale bucket suffix and uses the direct public URL', async () => {
    await initialize({
      BUCKET: ' airpix ',
      STORAGE_BUCKET_NAME: 'gallarista',
      STORAGE_PUBLIC_URL: 'https://pub-455fef85d2d74e608a2dbc4c2e2a5fbe.r2.dev/',
    });
    expect(send.mock.calls[0][0].input.Bucket).toBe('airpix');
    const publicUrl = await upload();
    expect(publicUrl).toBe('https://pub-455fef85d2d74e608a2dbc4c2e2a5fbe.r2.dev/photo%20with%20spaces.jpg');
    const put = send.mock.calls.find(([command]) => command instanceof PutObjectCommand)[0];
    expect(put.input).toMatchObject({ Bucket: 'airpix', Key: 'photo with spaces.jpg', ContentType: 'image/jpeg' });
    send.mockResolvedValueOnce({ Body: Readable.from(bytes) });
    const stream = await service.openStoredUrl(publicUrl);
    const chunks = [];
    for await (const chunk of stream) chunks.push(chunk);
    expect(Buffer.concat(chunks)).toEqual(bytes);
    expect(send.mock.calls.at(-1)[0].input).toEqual({ Bucket: 'airpix', Key: 'photo with spaces.jpg' });
    await service.deleteService('photo with spaces.jpg');
    expect(send.mock.calls.at(-1)[0].input).toEqual({ Bucket: 'airpix', Key: 'photo with spaces.jpg' });
  });

  it('presigns to airpix and publishes the object at the public bucket URL', async () => {
    await initialize({ BUCKET: 'airpix', STORAGE_PUBLIC_URL: 'https://pub-455fef85d2d74e608a2dbc4c2e2a5fbe.r2.dev' });
    const ticket = await service.presignUpload({ fileName: 'camera.jpg', size: 1234 }, 'https://api.example.test');
    expect(new URL(ticket.uploadUrl).pathname).toBe('/airpix/' + ticket.key);
    expect(ticket.url).toBe('https://pub-455fef85d2d74e608a2dbc4c2e2a5fbe.r2.dev/' + ticket.key);
    expect(ticket.url).not.toContain('/airpix/');
  });

  it('uploads the full stream with its size/type and returns a stable, signed image URL', async () => {
    await initialize();
    send.mockImplementation(async (command) => {
      if (command instanceof PutObjectCommand) {
        const chunks = [];
        for await (const chunk of command.input.Body as Readable) chunks.push(chunk);
        expect(Buffer.concat(chunks)).toEqual(bytes);
      }
      return {};
    });
    const url = new URL(await upload());
    expect(url.origin).toBe('https://api.example.test');
    expect(url.pathname).toBe('/image/file/photo%20with%20spaces.jpg');
    expect(url.searchParams.get('token')).toMatch(/^[a-f0-9]{64}$/);
    expect(await upload()).toBe(url.href);
    const command = send.mock.calls.find(([command]) => command instanceof PutObjectCommand)[0];
    expect(command.input).toMatchObject({
      Bucket: 'gallarista',
      Key: 'photo with spaces.jpg',
      ContentType: 'image/jpeg',
      ContentLength: bytes.length,
    });
  });

  it('streams signed image reads and blocks missing, invalid, or reused tokens before accessing R2', async () => {
    await initialize();
    const url = new URL(await upload());
    const token = url.searchParams.get('token');
    send.mockClear();
    for (const [key, signature] of [
      ['photo with spaces.jpg', undefined],
      ['photo with spaces.jpg', '0'.repeat(64)],
      ['another.jpg', token],
    ]) {
      await expect(service.readFile(key, signature)).rejects.toMatchObject({ status: 404 });
    }
    expect(send).not.toHaveBeenCalled();
    send.mockResolvedValueOnce({
      Body: Readable.from(bytes), ContentType: 'image/jpeg', ContentLength: bytes.length,
    });
    const file = await service.readFile('photo with spaces.jpg', token);
    expect(send.mock.calls[0][0]).toBeInstanceOf(GetObjectCommand);
    expect(file.getHeaders()).toMatchObject({ type: 'image/jpeg', length: bytes.length });
    const chunks = [];
    for await (const chunk of file.getStream()) chunks.push(chunk);
    expect(Buffer.concat(chunks)).toEqual(bytes);
    send.mockRejectedValueOnce({ name: 'NoSuchKey' });
    await expect(service.readFile('photo with spaces.jpg', token)).rejects.toMatchObject({ status: 404 });
  });

  it('uses the public bucket domain directly when configured and deletes from the R2 bucket', async () => {
    await initialize({ STORAGE_PUBLIC_URL: 'https://images.example.test/' });
    expect(await upload()).toBe('https://images.example.test/photo%20with%20spaces.jpg');
    await expect(service.deleteService('photo with spaces.jpg')).resolves.toBe(true);
    const command = send.mock.calls.at(-1)[0];
    expect(command).toBeInstanceOf(DeleteObjectCommand);
    expect(command.input).toEqual({ Bucket: 'gallarista', Key: 'photo with spaces.jpg' });
  });

  it('prefers the configured API origin for proxy URLs', async () => {
    await initialize({ PUBLIC_API_URL: 'https://public-api.example.test/' });
    expect(new URL(await upload()).origin).toBe('https://public-api.example.test');
  });

  it('rejects private S3 endpoints as public image domains', async () => {
    await expect(initialize({ STORAGE_PUBLIC_URL: config.STORAGE_S3_URL })).rejects.toThrow('STORAGE_PUBLIC_URL');
    expect(send).not.toHaveBeenCalled();
  });

  it('keeps MinIO local uploads working when R2 is not configured', async () => {
    await initialize({ STORAGE_S3_URL: '', MINIO_BUCKET_NAME: 'local-photos' });
    expect(send.mock.calls[1][0]).toBeInstanceOf(PutBucketPolicyCommand);
    expect(await upload()).toBe('http://localhost:9000/local-photos/photo%20with%20spaces.jpg');
  });

  it('signs direct PUTs without sending file bytes through the backend', async () => {
    await initialize();
    send.mockClear();
    const ticket = await service.presignUpload({ fileName: 'camera.ARW', size: 1234 }, 'https://api.example.test');
    const signed = new URL(ticket.uploadUrl);
    expect(signed.origin).toBe('https://account.eu.r2.cloudflarestorage.com');
    expect(signed.pathname).toBe(`/gallarista/${ticket.key}`);
    expect(signed.searchParams.get('X-Amz-Expires')).toBe('900');
    expect(signed.searchParams.get('X-Amz-SignedHeaders').split(';')).toEqual(
      expect.arrayContaining(['content-length', 'content-type', 'host']),
    );
    expect(ticket.headers).toEqual({ 'Content-Type': 'image/x-sony-arw' });
    expect(ticket.key).toMatch(/^[a-f0-9-]+\.arw$/);
    expect(ticket.url).toContain('/image/file/');
    expect(send).not.toHaveBeenCalled();
    const second = await service.presignUpload({ fileName: 'camera.ARW', size: 1234 }, 'https://api.example.test');
    expect(second.key).not.toBe(ticket.key);
  });

  it.each([
    { fileName: 'photo.jpg', size: 0 },
    { fileName: 'photo.jpg', size: 256 * 1024 * 1024 + 1 },
    { fileName: 'photo.jpg', size: 1.5 },
    { fileName: '', size: 1 },
    { fileName: 'program.exe', size: 1 },
    { fileName: 'photo.jpg', size: 1, contentType: 'text/html' },
  ])('rejects invalid presign metadata: %j', async (file) => {
    await initialize();
    send.mockClear();
    await expect(service.presignUpload(file, 'https://api.example.test')).rejects.toMatchObject({ status: 400 });
    expect(send).not.toHaveBeenCalled();
  });
});
