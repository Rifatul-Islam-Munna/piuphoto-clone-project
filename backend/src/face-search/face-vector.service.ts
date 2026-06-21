import '@tensorflow/tfjs-node';
import { HttpException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import * as faceapi from '@vladmandic/face-api';
import { Canvas, createCanvas, Image, ImageData, loadImage } from 'canvas';
import { existsSync } from 'fs';
import { join } from 'path';

faceapi.env.monkeyPatch({ Canvas, Image, ImageData } as any);

@Injectable()
export class FaceVectorService {
  private readonly logger = new Logger(FaceVectorService.name);
  private modelsReady?: Promise<void>;

  constructor(private readonly configService: ConfigService) {}

  private async ensureModels() {
    if (!this.modelsReady) {
      this.modelsReady = this.loadModels();
    }

    await this.modelsReady;
  }

  private async loadModels() {
    const modelPath =
      this.configService.get<string>('FACE_API_MODEL_PATH') ||
      join(process.cwd(), 'models', 'face-api');

    if (!existsSync(modelPath)) {
      throw new HttpException(`Face model path not found: ${modelPath}`, 500);
    }

    await Promise.all([
      faceapi.nets.tinyFaceDetector.loadFromDisk(modelPath),
      faceapi.nets.ssdMobilenetv1.loadFromDisk(modelPath),
      faceapi.nets.faceLandmark68Net.loadFromDisk(modelPath),
      faceapi.nets.faceRecognitionNet.loadFromDisk(modelPath),
    ]);

    this.logger.log(`face-models-loaded ${modelPath}`);
  }

  private minConfidence() {
    return Number(this.configService.get<string>('FACE_DETECT_MIN_CONFIDENCE')) || 0.5;
  }

  private detector() {
    return this.configService.get<string>('FACE_DETECTOR') || 'tiny';
  }

  private maxWidth() {
    return Number(this.configService.get<string>('FACE_IMAGE_MAX_WIDTH')) || 1280;
  }

  private async loadResizedImage(buffer: Buffer) {
    const image = await loadImage(buffer);
    const maxWidth = this.maxWidth();

    if (!maxWidth || image.width <= maxWidth) {
      return image;
    }

    const scale = maxWidth / image.width;
    const canvas = createCanvas(maxWidth, Math.round(image.height * scale));
    const context = canvas.getContext('2d');
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  async downloadImage(url: string) {
    const response = await axios.get<ArrayBuffer>(url, {
      responseType: 'arraybuffer',
      timeout: 60000,
    });

    return Buffer.from(response.data);
  }

  async vectorsFromBuffer(buffer: Buffer) {
    await this.ensureModels();
    const image = await this.loadResizedImage(buffer);
    const useTiny = this.detector() === 'tiny';
    const options = useTiny
      ? new faceapi.TinyFaceDetectorOptions({
          scoreThreshold: this.minConfidence(),
          inputSize: 416,
        })
      : new faceapi.SsdMobilenetv1Options({
          minConfidence: this.minConfidence(),
        });

    const detections = await faceapi
      .detectAllFaces(image as any, options)
      .withFaceLandmarks()
      .withFaceDescriptors();

    return detections.map((detection) => Array.from(detection.descriptor));
  }

  async vectorsFromUrl(url: string) {
    const buffer = await this.downloadImage(url);
    return this.vectorsFromBuffer(buffer);
  }
}
