import { Module } from '@nestjs/common';
import { FaceVectorService } from './face-vector.service';
import { QdrantFaceService } from './qdrant-face.service';

@Module({
  providers: [FaceVectorService, QdrantFaceService],
  exports: [FaceVectorService, QdrantFaceService],
})
export class FaceSearchModule {}
