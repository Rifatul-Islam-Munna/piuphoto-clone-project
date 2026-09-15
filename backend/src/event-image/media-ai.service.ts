import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectModel } from '@nestjs/mongoose';
import axios from 'axios';
import { Model, Types } from 'mongoose';
import sharp from 'sharp';
import { EventImage, EventImageDocument } from './entities/event-image.entity';

export type VisionAnalysis = {
  description?: string;
  tags?: string[];
  numbers?: string[];
  outfitTags?: string[];
  qualityScore?: number;
  blurScore?: number;
  reasons?: string[];
};

@Injectable()
export class MediaAiService {
  private readonly logger = new Logger(MediaAiService.name);
  private active = 0;
  private readonly queue: string[] = [];

  constructor(
    @InjectModel(EventImage.name)
    private readonly images: Model<EventImageDocument>,
    private readonly config: ConfigService,
  ) {}

  queueAnalysis(image: EventImageDocument | { _id: unknown }) {
    const id = String(image._id);
    if (!this.queue.includes(id)) this.queue.push(id);
    this.drain();
  }

  private concurrency() {
    return Math.max(
      Number(this.config.get<string>('MEDIA_AI_CONCURRENCY')) || 2,
      1,
    );
  }

  private drain() {
    while (this.active < this.concurrency() && this.queue.length) {
      const id = this.queue.shift();
      if (!id) return;
      this.active += 1;
      void this.analyzeById(id)
        .catch((error) =>
          this.logger.warn(`media-ai-failed id=${id} ${String(error)}`),
        )
        .finally(() => {
          this.active -= 1;
          this.drain();
        });
    }
  }

  private async imageBuffer(url: string) {
    const response = await axios.get<ArrayBuffer>(url, {
      responseType: 'arraybuffer',
      timeout: 60000,
      maxContentLength: 50 * 1024 * 1024,
    });
    return Buffer.from(response.data);
  }

  private async localMetrics(buffer: Buffer) {
    const gray = await sharp(buffer)
      .rotate()
      .greyscale()
      .resize(96, 96, { fit: 'fill' })
      .raw()
      .toBuffer({ resolveWithObject: true });
    const { width, height } = gray.info;
    const data = gray.data;
    let sum = 0;
    let sumSq = 0;
    let count = 0;
    for (let y = 1; y < height - 1; y += 1) {
      for (let x = 1; x < width - 1; x += 1) {
        const i = y * width + x;
        const lap =
          4 * data[i] -
          data[i - 1] -
          data[i + 1] -
          data[i - width] -
          data[i + width];
        sum += lap;
        sumSq += lap * lap;
        count += 1;
      }
    }
    const mean = count ? sum / count : 0;
    const variance = count ? Math.max(0, sumSq / count - mean * mean) : 0;
    const blurScore = Math.round(variance * 100) / 100;
    const qualityScore = Math.max(
      0,
      Math.min(100, Math.round(20 + Math.log10(variance + 1) * 22)),
    );

    const tiny = await sharp(buffer)
      .rotate()
      .greyscale()
      .resize(16, 16, { fit: 'fill' })
      .raw()
      .toBuffer();
    const avg = tiny.reduce((total, value) => total + value, 0) / tiny.length;
    let bits = '';
    for (const value of tiny) bits += value >= avg ? '1' : '0';
    let perceptualHash = '';
    for (let i = 0; i < bits.length; i += 4) {
      perceptualHash += parseInt(bits.slice(i, i + 4), 2).toString(16);
    }
    return { blurScore, qualityScore, perceptualHash };
  }

  private hamming(a?: string, b?: string) {
    if (!a || !b || a.length !== b.length) return Number.POSITIVE_INFINITY;
    let distance = 0;
    for (let i = 0; i < a.length; i += 1) {
      const xor = parseInt(a[i], 16) ^ parseInt(b[i], 16);
      distance += xor.toString(2).split('1').length - 1;
    }
    return distance;
  }

  private parseVisionText(text?: string): VisionAnalysis {
    if (!text) return {};
    const cleaned = text.replace(/```json/gi, '').replace(/```/g, '').trim();
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) return { description: cleaned.slice(0, 1000) };
    try {
      const parsed = JSON.parse(cleaned.slice(start, end + 1)) as VisionAnalysis;
      return {
        description: parsed.description,
        tags: Array.isArray(parsed.tags) ? parsed.tags.map(String).slice(0, 30) : [],
        numbers: Array.isArray(parsed.numbers) ? parsed.numbers.map(String).slice(0, 30) : [],
        outfitTags: Array.isArray(parsed.outfitTags) ? parsed.outfitTags.map(String).slice(0, 30) : [],
        qualityScore: Number.isFinite(Number(parsed.qualityScore)) ? Number(parsed.qualityScore) : undefined,
        reasons: Array.isArray(parsed.reasons) ? parsed.reasons.map(String).slice(0, 20) : [],
      };
    } catch {
      return { description: cleaned.slice(0, 1000) };
    }
  }

  private async falVision(imageUrl: string): Promise<VisionAnalysis> {
    const falKey = this.config.get<string>('FAL_KEY') || this.config.get<string>('FAL_API_KEY');
    if (!falKey) return {};
    const prompt = [
      'Analyze this event photo and return ONLY valid JSON.',
      'Schema: {"description":string,"tags":string[],"numbers":string[],"outfitTags":string[],"qualityScore":number,"reasons":string[]}.',
      'Description should be a concise searchable caption. Tags should cover scene, action, objects and event context.',
      'Numbers should contain clearly visible bib, jersey, race or participant numbers only.',
      'outfitTags should describe visible clothing colors and styles without identifying a person.',
      'qualityScore must be 0-100. reasons should only contain obvious visual quality problems.',
      'Do not identify people and do not infer sensitive attributes.',
    ].join(' ');
    const response = await axios.post<{ text?: string }>(
      'https://fal.run/fal-ai/bagel/understand',
      { image_url: imageUrl, prompt },
      { headers: { Authorization: `Key ${falKey}`, 'Content-Type': 'application/json' }, timeout: 120000 },
    );
    return this.parseVisionText(response.data?.text);
  }

  private async visionAnalysis(imageUrl: string): Promise<VisionAnalysis> {
    try {
      return await this.falVision(imageUrl);
    } catch (error) {
      this.logger.warn(`fal-vision-analysis ${String(error)}`);
      return {};
    }
  }

  async analyzeById(id: string) {
    if (!Types.ObjectId.isValid(id)) return null;
    const image = await this.images.findById(id).exec();
    if (!image) return null;
    if (image.mediaType === 'video') return image;
    const buffer = await this.imageBuffer(image.imageUrl);
    const local = await this.localMetrics(buffer);
    const external = await this.visionAnalysis(image.imageUrl);

    const recent = await this.images
      .find({
        _id: { $ne: image._id },
        eventId: image.eventId,
        perceptualHash: { $exists: true, $ne: '' },
      })
      .select('_id perceptualHash')
      .sort({ createdAt: -1 })
      .limit(500)
      .lean();
    const duplicate = recent
      .map((candidate) => ({
        id: candidate._id,
        distance: this.hamming(local.perceptualHash, candidate.perceptualHash),
      }))
      .sort((a, b) => a.distance - b.distance)[0];

    const reasons = [...new Set(external.reasons || [])];
    const blurThreshold =
      Number(this.config.get<string>('AI_BLUR_VARIANCE_THRESHOLD')) || 120;
    if ((external.blurScore ?? local.blurScore) < blurThreshold) {
      reasons.push('Possible blur');
    }
    if (duplicate && duplicate.distance <= 10) reasons.push('Likely duplicate');
    const qualityScore = Math.max(
      0,
      Math.min(100, Math.round(external.qualityScore ?? local.qualityScore)),
    );
    if (qualityScore < 45) reasons.push('Low quality score');
    const aiReviewStatus = reasons.length ? 'flagged' : 'approved';

    return this.images.findByIdAndUpdate(
      image._id,
      {
        $set: {
          aiReviewStatus,
          aiRecommended: aiReviewStatus === 'approved' && qualityScore >= 70,
          aiQualityScore: qualityScore,
          aiBlurScore: external.blurScore ?? local.blurScore,
          aiReviewReasons: [...new Set(reasons)],
          aiDescription: external.description || image.aiDescription,
          aiTags: [...new Set(external.tags || [])],
          recognizedNumbers: [...new Set((external.numbers || []).map(String))],
          outfitTags: [...new Set(external.outfitTags || [])],
          perceptualHash: local.perceptualHash,
          duplicateOfId:
            duplicate && duplicate.distance <= 10 ? duplicate.id : undefined,
        },
      },
      { new: true },
    );
  }

  async analyzeMany(ids: string[]) {
    const valid = ids.filter(Types.ObjectId.isValid);
    const results = await Promise.allSettled(
      valid.map((id) => this.analyzeById(id)),
    );
    return {
      total: valid.length,
      completed: results.filter((result) => result.status === 'fulfilled')
        .length,
      failed: results.filter((result) => result.status === 'rejected').length,
    };
  }

  async search(eventId: string, query: string, type = 'all', limit = 200) {
    if (!Types.ObjectId.isValid(eventId)) return [];
    const needle = query.trim();
    if (!needle) return [];
    const safe = needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(safe, 'i');
    const clauses: Record<string, unknown>[] = [];
    if (type === 'all' || type === 'semantic') {
      clauses.push({ aiDescription: regex }, { aiTags: regex });
    }
    if (type === 'all' || type === 'number')
      clauses.push({ recognizedNumbers: regex });
    if (type === 'all' || type === 'outfit')
      clauses.push({ outfitTags: regex });
    if (type === 'face') return [];
    return this.images
      .find({
        eventId: new Types.ObjectId(eventId),
        $or: clauses.length ? clauses : [{ aiDescription: regex }],
      })
      .populate('albumId', 'title')
      .populate('userTakenBy', 'name')
      .sort({ createdAt: -1 })
      .limit(Math.min(Math.max(Number(limit) || 200, 1), 1000))
      .lean();
  }
}
