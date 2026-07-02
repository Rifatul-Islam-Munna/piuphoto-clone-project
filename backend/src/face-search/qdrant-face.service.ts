import { HttpException, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios, { AxiosInstance } from 'axios';
import { randomUUID } from 'crypto';

type FacePayload = {
  eventId: string;
  eventImageId?: string;
  eventImageIds?: string[];
  imageUrl: string;
  imageUrls?: string[];
  faceIndex: number;
  isEnhanced: boolean;
  albumId?: string;
};

@Injectable()
export class QdrantFaceService implements OnModuleInit {
  private readonly logger = new Logger(QdrantFaceService.name);
  private client: AxiosInstance;
  private collectionName: string;

  constructor(private readonly configService: ConfigService) {}

  async onModuleInit() {
    const url = this.configService.get<string>('QDRANT_URL');
    this.collectionName = 'piuphoto_event_faces_insightface';

    if (!url) {
      this.logger.warn('QDRANT_URL missing; face search disabled');
      return;
    }

    this.client = axios.create({
      baseURL: url.replace(/\/$/, ''),
      timeout: 30000,
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
      throw new HttpException(
        'Face search is not ready. Check QDRANT_URL.',
        503,
      );
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
        size: this.dimension(),
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

  private dimension() {
    return 512;
  }

  private scoreFromDistance(key: string, fallbackDistance: number) {
    const raw = this.configService.get<string>(key);
    const distance = raw === undefined || raw === '' ? fallbackDistance : Number(raw);
    if (!Number.isFinite(distance)) return 1 - fallbackDistance;

    return Math.max(0, Math.min(1, 1 - distance));
  }

  private groupScoreThreshold() {
    return this.scoreFromDistance('FACE_CLUSTER_DISTANCE', 0.55);
  }

  private matchScoreThreshold() {
    return this.scoreFromDistance('FACE_MATCH_DISTANCE', 0.95);
  }

  private searchLimit(limit?: number) {
    return Math.min(
      Math.max(
        Number(limit) ||
          Number(this.configService.get<string>('FACE_SEARCH_SCAN_LIMIT')) ||
          10000,
        1,
      ),
      10000,
    );
  }

  private async findSamePersonPoint(vector: number[], eventId: string) {
    const response = await this.search(
      vector,
      eventId,
      1,
      this.groupScoreThreshold(),
    );

    return response[0];
  }

  async upsertFaces(vectors: number[][], payload: Omit<FacePayload, 'faceIndex'>) {
    if (!vectors.length) return 0;
    this.assertEnabled();

    const points = [];

    for (const [faceIndex, vector] of vectors.entries()) {
      const samePerson = await this.findSamePersonPoint(vector, payload.eventId);
      const samePayload = samePerson?.payload;
      const id = samePerson?.id || randomUUID();
      const eventImageIds = new Set([
        ...(samePayload?.eventImageIds || []),
        samePayload?.eventImageId,
        payload.eventImageId,
      ].filter(Boolean));
      const imageUrls = new Set([
        ...(samePayload?.imageUrls || []),
        samePayload?.imageUrl,
        payload.imageUrl,
      ].filter(Boolean));

      points.push({
        id,
        vector,
        payload: {
          ...payload,
          faceIndex: samePayload?.faceIndex ?? faceIndex,
          eventImageIds: [...eventImageIds],
          imageUrls: [...imageUrls],
        },
      });
    }

    await this.client.put(`/collections/${this.collectionName}/points`, {
      points,
    });

    return vectors.length;
  }

  async search(
    vector: number[],
    eventId?: string,
    limit?: number,
    scoreThreshold?: number,
  ) {
    this.assertEnabled();

    const response = await this.client.post<{
      result: Array<{ id: string; score: number; payload?: FacePayload }>;
    }>(`/collections/${this.collectionName}/points/search`, {
      vector,
      limit: this.searchLimit(limit),
      score_threshold: scoreThreshold ?? this.matchScoreThreshold(),
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
