import { Test, TestingModule } from '@nestjs/testing';
import { WebsitesettingsService } from './websitesettings.service';

describe('WebsitesettingsService', () => {
  let service: WebsitesettingsService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [WebsitesettingsService],
    }).compile();

    service = module.get<WebsitesettingsService>(WebsitesettingsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
