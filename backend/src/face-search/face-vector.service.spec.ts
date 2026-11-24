import { HttpException } from '@nestjs/common';
import axios from 'axios';
import FormData from 'form-data';
import { FaceVectorService } from './face-vector.service';

describe('InsightFace endpoint contract', () => {
  const origin = 'https://faces.example.test';
  const image = Buffer.from('test image bytes');
  const makeService = (settings: Record<string, string> = { FACE_DETECTION_ENDPOINT_URL: origin }) =>
    new FaceVectorService({ get: (key: string) => settings[key] } as never);

  afterEach(() => jest.restoreAllMocks());

  it.each([origin, origin + '/', origin + '/v1/faces'])('uses the upload route and file field for %s', async endpoint => {
    const post = jest.spyOn(axios, 'post').mockResolvedValue({ data: { faces: [], embeddingDimension: 512 } });
    await expect(makeService({ FACE_DETECTION_ENDPOINT_URL: endpoint }).detectFromBuffer(image, 'photo.png', 'image/png')).resolves.toEqual([]);
    expect(post.mock.calls[0][0]).toBe(origin + '/v1/faces');
    const form = post.mock.calls[0][1] as FormData;
    expect(form.getBuffer().toString()).toContain('name="file"; filename="photo.png"');
    expect(form.getBuffer().toString()).toContain('Content-Type: image/png');
    expect(form.getBuffer().includes(image)).toBe(true);
    expect(form.getBuffer().toString()).not.toContain('name="image"');
  });

  it('preserves explicit compatible paths, custom field names and optional authentication', async () => {
    const post = jest.spyOn(axios, 'post').mockResolvedValue({ data: { faces: [] } });
    await makeService({
      FACE_DETECTION_ENDPOINT_URL: origin + '/custom/detect',
      FACE_DETECTION_UPLOAD_FIELD: 'image',
      FACE_DETECTION_API_KEY: 'test-face-key',
    }).detectFromBuffer(image);
    expect(post.mock.calls[0][0]).toBe(origin + '/custom/detect');
    expect((post.mock.calls[0][1] as FormData).getBuffer().toString()).toContain('name="image"');
    expect(post.mock.calls[0][2]).toEqual(expect.objectContaining({ headers: expect.objectContaining({ 'x-api-key': 'test-face-key' }) }));
  });

  it.each([
    [404, '/v1/faces'],
    [422, 'FACE_DETECTION_UPLOAD_FIELD'],
    [401, 'FACE_DETECTION_API_KEY'],
    [403, 'FACE_DETECTION_API_KEY'],
    [500, 'not reachable'],
  ])('explains the actual upstream %s failure', async (status, message) => {
    jest.spyOn(axios, 'post').mockRejectedValue({ isAxiosError: true, response: { status } });
    await expect(makeService().detectFromBuffer(image)).rejects.toThrow(String(message));
  });

  it.each([undefined, 'PASTE_MY_ENDPOINT_HERE', 'invalid-url', 'ftp://faces.example.test'])('rejects missing or invalid configuration before an HTTP request: %s', async endpoint => {
    const post = jest.spyOn(axios, 'post');
    await expect(makeService({ FACE_DETECTION_ENDPOINT_URL: endpoint as string }).detectFromBuffer(image)).rejects.toBeInstanceOf(HttpException);
    expect(post).not.toHaveBeenCalled();
  });

  it('rejects a health or unrelated JSON response instead of reporting zero faces', async () => {
    jest.spyOn(axios, 'post').mockResolvedValue({ data: { ok: true } });
    await expect(makeService().detectFromBuffer(image)).rejects.toThrow('expected a faces array');
  });

  it('retains 512-dimensional embedding extraction for face matching', async () => {
    const embedding = Array.from({ length: 512 }, (_, index) => index / 512);
    jest.spyOn(axios, 'post').mockResolvedValue({ data: { faces: [{ embedding }], embeddingDimension: 512 } });
    await expect(makeService().vectorsFromBuffer(image)).resolves.toEqual([embedding]);
  });
});
