import { Test, TestingModule } from '@nestjs/testing';
import { WebsitesettingsController } from './websitesettings.controller';
import { WebsitesettingsService } from './websitesettings.service';

describe('WebsitesettingsController', () => {
  let controller: WebsitesettingsController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [WebsitesettingsController],
      providers: [WebsitesettingsService],
    }).compile();

    controller = module.get<WebsitesettingsController>(WebsitesettingsController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
