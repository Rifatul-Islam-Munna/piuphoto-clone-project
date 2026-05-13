import { Test, TestingModule } from '@nestjs/testing';
import { EventImageService } from './event-image.service';

describe('EventImageService', () => {
  let service: EventImageService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [EventImageService],
    }).compile();

    service = module.get<EventImageService>(EventImageService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
