import { Logger } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { unlink } from 'fs/promises';
import { MinioService } from '../lib/minio.service';
import { ImageService } from './image.service';

jest.mock('fs/promises', () => ({ unlink: jest.fn() }));

describe('ImageService cloud upload completion', () => {
  const uploadedUrl = 'https://storage.example.test/photos/shot.jpg';
  const file = { path: '/temporary/shot.jpg', filename: 'shot.jpg' };
  const storage = { uploadFile: jest.fn(), deleteService: jest.fn() };
  const remove = jest.mocked(unlink);
  let service: ImageService;

  beforeEach(async () => {
    jest.clearAllMocks();
    storage.uploadFile.mockReset().mockResolvedValue(uploadedUrl);
    remove.mockReset().mockResolvedValue(undefined);
    const module = await Test.createTestingModule({
      providers: [ImageService, { provide: MinioService, useValue: storage }],
    }).compile();
    service = module.get(ImageService);
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
  });

  afterEach(() => jest.restoreAllMocks());

  it('returns the cloud URL and removes the temporary server file', async () => {
    await expect(service.uploadImage(file)).resolves.toMatchObject({
      url: uploadedUrl,
    });
    expect(storage.uploadFile).toHaveBeenCalledWith(file);
    expect(remove).toHaveBeenCalledWith(file.path);
  });

  it('does not turn a successful cloud upload into failure when cleanup fails', async () => {
    remove.mockRejectedValue(Object.assign(new Error('locked'), { code: 'EBUSY' }));
    await expect(service.uploadImage(file)).resolves.toMatchObject({
      url: uploadedUrl,
    });
    expect(Logger.prototype.warn).toHaveBeenCalled();
  });

  it('cleans the server temporary file but preserves the actual cloud error', async () => {
    const cloudError = new Error('storage unavailable');
    storage.uploadFile.mockRejectedValue(cloudError);
    remove.mockRejectedValue(Object.assign(new Error('locked'), { code: 'EBUSY' }));
    await expect(service.uploadImage(file)).rejects.toBe(cloudError);
    expect(remove).toHaveBeenCalledWith(file.path);
  });

  it('tolerates a temporary file that was already removed', async () => {
    remove.mockRejectedValue(Object.assign(new Error('missing'), { code: 'ENOENT' }));
    await expect(service.uploadImage(file)).resolves.toMatchObject({
      url: uploadedUrl,
    });
    expect(Logger.prototype.warn).not.toHaveBeenCalled();
  });

  it('rejects an absent single file and an empty batch without contacting storage', async () => {
    await expect(service.uploadImage(undefined)).rejects.toMatchObject({ status: 400 });
    await expect(service.uploadImages([])).rejects.toMatchObject({ status: 400 });
    expect(storage.uploadFile).not.toHaveBeenCalled();
    expect(remove).not.toHaveBeenCalled();
  });

  it('does not remove a still-uploading batch file when another file fails', async () => {
    const second = { path: '/temporary/second.jpg', filename: 'second.jpg' };
    let finishSecond!: (url: string) => void;
    const secondUpload = new Promise<string>((resolve) => { finishSecond = resolve; });
    const cloudError = new Error('first upload failed');
    storage.uploadFile
      .mockRejectedValueOnce(cloudError)
      .mockReturnValueOnce(secondUpload);

    await expect(service.uploadImages([file, second])).rejects.toBe(cloudError);
    expect(remove).toHaveBeenCalledWith(file.path);
    expect(remove).not.toHaveBeenCalledWith(second.path);

    finishSecond(uploadedUrl);
    await secondUpload;
    await Promise.resolve();
    expect(remove).toHaveBeenCalledWith(second.path);
  });

  it('preserves batch URL order and cleans each completed transfer', async () => {
    const second = { path: '/temporary/second.jpg', filename: 'second.jpg' };
    storage.uploadFile.mockResolvedValueOnce('first-url').mockResolvedValueOnce('second-url');
    await expect(service.uploadImages([file, second])).resolves.toMatchObject({
      urls: ['first-url', 'second-url'],
    });
    expect(remove).toHaveBeenCalledTimes(2);
  });
});
