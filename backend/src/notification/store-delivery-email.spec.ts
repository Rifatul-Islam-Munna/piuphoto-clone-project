import { buildStoreDeliveryHtml, buildStoreDeliveryText } from './store-delivery-email';
import { NotificationService } from './notification.service';

describe('purchased photo email matches the gallery email layout', () => {
  const data = {
    eventTitle: 'Nikos Wedding',
    link: 'https://airpix.example/#/store/order/order123?token=secret',
    photoCount: 23,
    orderNo: 'ORD-123',
    expiresAt: new Date('2026-11-24T10:00:00Z'),
  };

  it('renders a mobile-compatible 680px centered email, CTA and full expiry', () => {
    const html = buildStoreDeliveryHtml(data);
    expect(html).toContain('max-width:680px');
    expect(html).toContain('Photos ready');
    expect(html).toContain('Download your photos');
    expect(html).toContain('Nikos Wedding');
    expect(html).toContain('23 purchased photos');
    expect(html).toContain('ORD-123');
    expect(html).toContain('24 Nov 2026');
    expect(html).toContain('href="https://airpix.example/#/store/order/order123?token=secret"');
    expect(html).toContain('color:#ffffff');
    const plain = buildStoreDeliveryText(data);
    expect(plain).toContain(data.link);
    expect(plain).toContain('23 purchased photos');
    expect(plain).toContain('24 Nov 2026');
  });

  it('escapes unsafe event titles and prevents HTML injection', () => {
    const html = buildStoreDeliveryHtml({
      ...data,
      eventTitle: '<img src=x onerror=alert(1)> & "test"',
      link: 'https://airpix.example/#/store/order/id?token=a&next=1',
    });
    expect(html).not.toContain('<img src=x onerror');
    expect(html).toContain('&lt;img src=x onerror');
    expect(html).toContain('token=a&amp;next=1');
  });

  it('rejects unsafe URL schemes', () => {
    expect(() => buildStoreDeliveryHtml({ ...data, link: 'javascript:alert(1)' }))
      .toThrow('valid purchase delivery URL');
  });

  it('sends both HTML and plain-text link over configured SMTP', async () => {
    const config = {
      get: jest.fn((name: string) => ({
        SMTP_HOST: 'smtp.example.test',
        SMTP_PORT: '587',
        SMTP_USER: 'no-reply@example.test',
        SMTP_PASS: 'testpass',
        SMTP_FROM: 'no-reply@example.test',
      })[name]),
    };
    const mailer = { sendMail: jest.fn().mockResolvedValue({ messageId: 'test' }) };
    const service = new NotificationService(config as never);
    (service as any).mailer = mailer;
    await service.sendStoreDelivery({ email: 'guest@example.test', ...data });
    expect(mailer.sendMail).toHaveBeenCalledWith(
      expect.objectContaining({
        to: 'guest@example.test',
        subject: expect.stringContaining('Nikos Wedding'),
        html: expect.stringContaining('Download your photos'),
        text: expect.stringContaining('https://airpix.example/'),
      }),
    );
  });

  it('does not claim a successful delivery when SMTP rejects the message', async () => {
    const config = { get: jest.fn((name: string) =>
      name === 'SMTP_HOST' ? 'smtp.example.test' : name === 'SMTP_FROM' ? 'noreply@example.test' : '',
    ) };
    const service = new NotificationService(config as never);
    (service as any).mailer = { sendMail: jest.fn().mockRejectedValue(new Error('SMTP failed')) };
    await expect(service.sendStoreDelivery({ email: 'guest@example.test', ...data }))
      .rejects.toThrow('Configured delivery channel failed');
  });
});
