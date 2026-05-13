import { Test, TestingModule } from '@nestjs/testing';
import { EventImageController } from './event-image.controller';
import { EventImageService } from './event-image.service';

describe('EventImageController', () => {
  let controller: EventImageController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [EventImageController],
      providers: [EventImageService],
    }).compile();

    controller = module.get<EventImageController>(EventImageController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
