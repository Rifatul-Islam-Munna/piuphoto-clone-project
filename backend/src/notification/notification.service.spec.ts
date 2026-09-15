import { NotificationService } from './notification.service';

describe('NotificationService optional providers', () => {
  const config = { get: jest.fn().mockReturnValue(undefined) } as never;

  it('treats missing SMTP and WhatsApp credentials as disabled', () => {
    const service = new NotificationService(config);
    expect(service.emailConfigured()).toBe(false);
    expect(service.whatsappConfigured()).toBe(false);
  });

  it('skips guest notification cleanly when the provider is disabled', async () => {
    const service = new NotificationService(config);
    await expect(service.sendGuestMatch({
      eventTitle: 'Test Event',
      link: 'https://example.test/gallery',
      photoCount: 1,
      email: 'guest@example.com',
    }, 'email')).resolves.toBeUndefined();
  });
  it('does not fail store delivery when no provider is configured', async () => {
    const service = new NotificationService(config);
    await expect(
      service.sendStoreDelivery({
        eventTitle: 'Test Event',
        link: 'https://example.test/order',
        photoCount: 2,
        email: 'guest@example.com',
        whatsapp: '+15555550123',
      }),
    ).resolves.toBeUndefined();
  });
});
