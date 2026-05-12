import {
  CreateBucketCommand,
  DeleteObjectCommand,
  PutBucketPolicyCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import {
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createReadStream } from 'fs';

@Injectable()
export class MinioService implements OnModuleInit {
  private logger = new Logger(MinioService.name);

  constructor(private configService: ConfigService) {}

  private s3: S3Client;

  async onModuleInit() {
    const minioUrl = this.configService.get<string>('MINIO_URL') as string;
    const accessKeyId = this.configService.get<string>('MINIO_ACCESS_KEY') as string;
    const secretAccessKey = this.configService.get<string>('MINIO_SECRET_KEY') as string;

    this.s3 = new S3Client({
      region: 'us-east-1',
      endpoint: minioUrl,
      credentials: {
        accessKeyId,
        secretAccessKey,
      },
      forcePathStyle: true,
    });

    const bucketName = this.configService.get<string>('MINIO_BUCKET_NAME') || 'piuphoto-public-bucket';
    await this.createBucketIfNotExists(bucketName);
    await this.makeBucketPublic(bucketName);
  }

  async createBucketIfNotExists(bucketName: string) {
    try {
      await this.s3.send(new CreateBucketCommand({ Bucket: bucketName }));
      console.log(`Bucket '${bucketName}' created or already exists.`);
    } catch (err: any) {
      if (err?.name === 'BucketAlreadyOwnedByYou' || err?.name === 'BucketAlreadyExists') {
        console.log(`Bucket '${bucketName}' already exists.`);
      } else {
        console.error('Error creating bucket:', err);
        throw err;
      }
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

  async uploadFile(filePath: any) {
    try {
      const fileContent = createReadStream(filePath.path);

      const bucketName = this.configService.get<string>('MINIO_BUCKET_NAME') || 'piuphoto-public-bucket';

      const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: filePath.filename,
        Body: fileContent,
        ContentType: filePath.mimetype,
      });

      const s = await this.s3.send(command);
      this.logger.debug(s);
      this.logger.debug(
        `${this.configService.get('MINIO_URL')}/${bucketName}/${filePath.filename}`,
      );

      return `${this.configService.get('MINIO_URL')}/${bucketName}/${filePath.filename}`;
    } catch (err) {
      console.error('Error uploading file:', err);
      throw new HttpException(
        'Failed to upload file',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  async deleteService(fileName: string) {
    if (!fileName || typeof fileName !== 'string') {
      throw new HttpException('Invalid file name', HttpStatus.BAD_REQUEST);
    }

    try {
      const bucketName = this.configService.get<string>('MINIO_BUCKET_NAME') || 'piuphoto-public-bucket';

      const command = new DeleteObjectCommand({
        Bucket: bucketName,
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