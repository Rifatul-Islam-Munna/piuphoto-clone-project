import { HttpException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import FormData from 'form-data';

export type DetectedFace = {
  x: number;
  y: number;
  width: number;
  height: number;
  confidence?: number;
  vector?: number[];
};

type FaceApiResponse = {
  faces?: Array<
    DetectedFace & {
      box?: { x?: number; y?: number; width?: number; height?: number };
      boxPercent?: { x?: number; y?: number; width?: number; height?: number };
      embedding?: number[];
      descriptor?: number[];
    }
  >;
  embeddingDimension?: number;
};

@Injectable()
export class FaceVectorService {
  private readonly logger = new Logger(FaceVectorService.name);

  constructor(private readonly configService: ConfigService) {}

  private endpointUrl() {
    const direct = this.configService
      .get<string>('FACE_DETECTION_ENDPOINT_URL')
      ?.trim();

    if (!direct || direct === 'PASTE_MY_ENDPOINT_HERE') return undefined;
    return direct;
  }

  private apiKey() {
    return undefined;
  }

  private vectorSize() {
    return 512;
  }

  async downloadImage(url: string) {
    const response = await axios.get<ArrayBuffer>(url, {
      responseType: 'arraybuffer',
      timeout: 60000,
    });

    return Buffer.from(response.data);
  }

  async detectFromBuffer(
    buffer: Buffer,
    filename = 'image.jpg',
    mimeType = 'image/jpeg',
  ) {
    const endpointUrl = this.endpointUrl();
    if (!endpointUrl) {
      throw new HttpException(
        'Face detection endpoint is not configured. Set FACE_DETECTION_ENDPOINT_URL.',
        503,
      );
    }

    const formData = new FormData();
    formData.append('image', buffer, { filename, contentType: mimeType });

    try {
      const response = await axios.post<FaceApiResponse>(endpointUrl, formData, {
        headers: {
          ...formData.getHeaders(),
          ...(this.apiKey() ? { 'x-api-key': this.apiKey() } : {}),
        },
        timeout: 60000,
      });

      const faces = Array.isArray(response.data.faces) ? response.data.faces : [];
      this.logger.log(
        `face-endpoint-ok faces=${faces.length} embeddingDim=${response.data.embeddingDimension || 'unknown'}`,
      );
      return faces.map((face) => ({
        x: Number(face.x ?? face.box?.x ?? face.boxPercent?.x) || 0,
        y: Number(face.y ?? face.box?.y ?? face.boxPercent?.y) || 0,
        width: Number(face.width ?? face.box?.width ?? face.boxPercent?.width) || 0,
        height:
          Number(face.height ?? face.box?.height ?? face.boxPercent?.height) ||
          0,
        confidence:
          face.confidence === undefined ? undefined : Number(face.confidence),
        vector: face.vector || face.embedding || face.descriptor,
      }));
    } catch (error) {
      const status = axios.isAxiosError(error) ? error.response?.status : undefined;
      this.logger.warn(
        `face-endpoint-failed ${status ? `status=${status}` : ''}`,
      );
      throw new HttpException(
        'Face detection service is not reachable. Check FACE_DETECTION_ENDPOINT_URL.',
        503,
      );
    }
  }

  async vectorsFromBuffer(
    buffer: Buffer,
    filename = 'image.jpg',
    mimeType = 'image/jpeg',
  ) {
    const faces = await this.detectFromBuffer(buffer, filename, mimeType);
    const vectors = faces
      .map((face) => face.vector)
      .filter(
        (vector): vector is number[] =>
          Array.isArray(vector) && vector.length === this.vectorSize(),
      );

    if (faces.length && !vectors.length) {
      throw new HttpException(
        'Face endpoint must return vector, embedding, or descriptor for matching',
        500,
      );
    }

    return vectors;
  }

  async vectorsFromUrl(url: string) {
    const buffer = await this.downloadImage(url);
    return this.vectorsFromBuffer(buffer);
  }

  async detectAndVectorFromBuffer(
    buffer: Buffer,
    filename = 'image.jpg',
    mimeType = 'image/jpeg',
  ) {
    const faces = await this.detectFromBuffer(buffer, filename, mimeType);
    return {
      faces: faces.map(({ vector, ...face }) => face),
      vectors: faces
        .map((face) => face.vector)
        .filter(
          (vector): vector is number[] =>
            Array.isArray(vector) && vector.length === this.vectorSize(),
        ),
    };
  }
}
