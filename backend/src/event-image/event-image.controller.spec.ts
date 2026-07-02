jest.mock('../face-search/face-vector.service', () => ({
  FaceVectorService: class FaceVectorService {},
}));
jest.mock('../face-search/qdrant-face.service', () => ({
  QdrantFaceService: class QdrantFaceService {},
}));

import { EventImageController } from './event-image.controller';
import { EventImageService } from './event-image.service';

describe('EventImageController', () => {
  let controller: EventImageController;

  beforeEach(() => {
    controller = new EventImageController({} as EventImageService);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
