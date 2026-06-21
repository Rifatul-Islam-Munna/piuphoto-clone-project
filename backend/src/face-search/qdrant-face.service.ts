import { HttpException, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios, { AxiosInstance } from 'axios';
import { randomUUID } from 'crypto';

type FacePayload = {
  eventId: string;
  eventImageId: string;
  imageUrl: string;
  faceIndex: number;
  isEnhanced: boolean;
  albumId?: string;
};

@Injectable()
export class QdrantFaceService implements OnModuleInit {
  private readonly logger = new Logger(QdrantFaceService.name);
  private readonly dimension = 128;
  private client: AxiosInstance;
  private collectionName: string;

  constructor(private readonly configService: ConfigService) {}

  async onModuleInit() {
    const url = this.configService.get<string>('QDRANT_URL');
    this.collectionName =
      this.configService.get<string>('QDRANT_FACE_COLLECTION') || 'event_faces';

    if (!url) {
      this.logger.warn('QDRANT_URL missing; face search disabled');
      return;
    }

    this.client = axios.create({
      baseURL: url.replace(/\/$/, ''),
      timeout: 30000,
      headers: this.configService.get<string>('QDRANT_API_KEY')
        ? { 'api-key': this.configService.get<string>('QDRANT_API_KEY') }
        : undefined,
    });

    try {
      await this.ensureCollection();
    } catch (error) {
      this.client = undefined;
      this.logger.error('qdrant-init-failed', error);
    }
  }

  private assertEnabled() {
    if (!this.client) {
      throw new HttpException('Qdrant is not configured', 503);
    }
  }

  private async ensureCollection() {
    this.assertEnabled();

    try {
      await this.client.get(`/collections/${this.collectionName}`);
      return;
    } catch (error) {
      if (!axios.isAxiosError(error) || error.response?.status !== 404) {
        throw error;
      }
    }

    await this.client.put(`/collections/${this.collectionName}`, {
      vectors: {
        size: this.dimension,
        distance: 'Cosine',
      },
    });

    await this.client.put(
      `/collections/${this.collectionName}/index`,
      {
        field_name: 'eventId',
        field_schema: 'keyword',
      },
      { validateStatus: (status) => status < 500 },
    );

    this.logger.log(`qdrant-face-collection-ready ${this.collectionName}`);
  }

  async upsertFaces(vectors: number[][], payload: Omit<FacePayload, 'faceIndex'>) {
    if (!vectors.length) return 0;
    this.assertEnabled();

    await this.client.put(`/collections/${this.collectionName}/points`, {
      points: vectors.map((vector, faceIndex) => ({
        id: randomUUID(),
        vector,
        payload: { ...payload, faceIndex },
      })),
    });

    return vectors.length;
  }

  async search(vector: number[], eventId?: string, limit = 100, scoreThreshold = 0.45) {
    this.assertEnabled();

    const response = await this.client.post<{
      result: Array<{ score: number; payload?: FacePayload }>;
    }>(`/collections/${this.collectionName}/points/search`, {
      vector,
      limit,
      score_threshold: scoreThreshold,
      with_payload: true,
      filter: eventId
        ? {
            must: [
              {
                key: 'eventId',
                match: { value: eventId },
              },
            ],
          }
        : undefined,
    });

    return response.data.result;
  }
}
