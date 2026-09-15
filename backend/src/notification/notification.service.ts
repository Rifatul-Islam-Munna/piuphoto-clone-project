import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import nodemailer, { Transporter } from 'nodemailer';

export type LinkNotification = {
  email?: string;
  whatsapp?: string;
  eventTitle: string;
  link: string;
  photoCount: number;
};

@Injectable()
export class NotificationService {
  private readonly logger = new Logger(NotificationService.name);
  private mailer?: Transporter;

  constructor(private readonly config: ConfigService) {}

  private env(name: string) {
    return this.config.get<string>(name)?.trim() || '';
  }

  private smtpTransport() {
    if (this.mailer) return this.mailer;
    const host = this.env('SMTP_HOST');
    if (!host) throw new Error('SMTP_HOST is not configured');
    const port = Number(this.env('SMTP_PORT')) || 587;
    const secure = this.env('SMTP_SECURE').toLowerCase() === 'true' || port === 465;
    const user = this.env('SMTP_USER');
    const pass = this.env('SMTP_PASS');
    this.mailer = nodemailer.createTransport({
      host,
      port,
      secure,
      ...(user && pass ? { auth: { user, pass } } : {}),
    });
    return this.mailer;
  }

  private fromAddress() {
    const address = this.env('SMTP_FROM') || this.env('SMTP_USER');
    if (!address) throw new Error('SMTP_FROM or SMTP_USER is not configured');
    const name = this.env('SMTP_FROM_NAME') || 'Airpix';
    return `"${name.replaceAll('"', '')}" <${address}>`;
  }

  emailConfigured() {
    return Boolean(this.env('SMTP_HOST') && (this.env('SMTP_FROM') || this.env('SMTP_USER')));
  }

  whatsappConfigured() {
    return Boolean(this.env('WHATSAPP_ACCESS_TOKEN') && this.env('WHATSAPP_PHONE_NUMBER_ID'));
  }

  async sendEmail(to: string, subject: string, text: string) {
    await this.smtpTransport().sendMail({
      from: this.fromAddress(),
      to,
      subject,
      text,
    });
  }

  private whatsappRecipient(value: string) {
    return value.replace(/^whatsapp:/i, '').replace(/\D/g, '');
  }
  async sendWhatsApp(to: string, eventTitle: string, link: string, message: string) {
    const token = this.env('WHATSAPP_ACCESS_TOKEN');
    const phoneNumberId = this.env('WHATSAPP_PHONE_NUMBER_ID');
    if (!token || !phoneNumberId) {
      throw new Error('WhatsApp Cloud API credentials are not configured');
    }
    const recipient = this.whatsappRecipient(to);
    if (!recipient) throw new Error('WhatsApp recipient is invalid');
    const version = this.env('WHATSAPP_GRAPH_API_VERSION') || 'v23.0';
    const templateName = this.env('WHATSAPP_TEMPLATE_NAME');
    const payload: Record<string, unknown> = {
      messaging_product: 'whatsapp',
      to: recipient,
    };
    if (templateName) {
      payload.type = 'template';
      payload.template = {
        name: templateName,
        language: { code: this.env('WHATSAPP_TEMPLATE_LANGUAGE') || 'en_US' },
        components: [{
          type: 'body',
          parameters: [
            { type: 'text', text: eventTitle },
            { type: 'text', text: link },
          ],
        }],
      };
    } else {
      payload.type = 'text';
      payload.text = { preview_url: true, body: message };
    }
    await axios.post(
      `https://graph.facebook.com/${version}/${phoneNumberId}/messages`,
      payload,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        timeout: 15000,
      },
    );
  }

  async sendGuestMatch(data: LinkNotification, channel: 'email' | 'whatsapp') {
    const noun = data.photoCount === 1 ? 'photo' : 'photos';
    const text = `${data.photoCount} new ${noun} from ${data.eventTitle} matched your personal gallery. Open: ${data.link}`;
    if (channel === 'email') {
      if (!this.emailConfigured() || !data.email) return;
      await this.sendEmail(
        data.email,
        `New photos from ${data.eventTitle}`,
        text,
      );
      return;
    }
    if (!this.whatsappConfigured() || !data.whatsapp) return;
    await this.sendWhatsApp(data.whatsapp, data.eventTitle, data.link, text);
  }
  async sendStoreDelivery(data: LinkNotification) {
    const noun = data.photoCount === 1 ? 'photo' : 'photos';
    const text = `Your ${data.photoCount} purchased ${noun} from ${data.eventTitle} are ready. Download: ${data.link}`;
    const attempts: Promise<unknown>[] = [];
    if (data.email && this.emailConfigured()) {
      attempts.push(
        this.sendEmail(
          data.email,
          `Your photos from ${data.eventTitle}`,
          text,
        ),
      );
    }
    if (data.whatsapp && this.whatsappConfigured()) {
      attempts.push(
        this.sendWhatsApp(data.whatsapp, data.eventTitle, data.link, text),
      );
    }
    if (!attempts.length) return;
    const results = await Promise.allSettled(attempts);
    if (!results.some((result) => result.status === 'fulfilled')) {
      const reason = results.find((result) => result.status === 'rejected');
      this.logger.warn(`delivery-failed ${String((reason as PromiseRejectedResult | undefined)?.reason)}`);
      throw new Error('All configured delivery channels failed');
    }
  }
}


