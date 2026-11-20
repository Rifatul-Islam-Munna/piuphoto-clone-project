/**
 * AirPix paid-photo email. Table/inline-CSS layout follows the branded
 * gallery email in pixieset-asad-vai-project/backend/src/mail/email-layout.ts:
 * ivory outer canvas, centered white 680px card, brand / eyebrow / headline,
 * message, large CTA, and low-contrast expiry footer.
 */
export type StoreDeliveryEmail = {
  eventTitle: string;
  link: string;
  photoCount: number;
  orderNo?: string;
  expiresAt?: Date | string;
};

export function escapeStoreEmailHtml(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function expiryDescription(value?: Date | string): string {
  if (!value) return 'For your security, this download link expires.';
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return 'For your security, this download link expires.';
  return `Your secure download link expires on ${date.toUTCString()}.`;
}

export function buildStoreDeliveryText(data: StoreDeliveryEmail): string {
  const count = Math.max(0, Math.floor(data.photoCount));
  const noun = count === 1 ? 'photo' : 'photos';
  return [
    'Your photos are ready',
    '',
    `Your ${count} purchased ${noun} from ${data.eventTitle} are available now.`,
    'Open the secure page below to download the original, full-resolution files.',
    '',
    data.link,
    '',
    data.orderNo ? `Order: ${data.orderNo}` : '',
    expiryDescription(data.expiresAt),
    '',
    'You can download the pictures now or return to this link from your email.',
    'AirPix',
  ].filter((line, index, lines) => line || index < 7 || !!line).join('\n');
}

export function buildStoreDeliveryHtml(data: StoreDeliveryEmail): string {
  const title = escapeStoreEmailHtml(data.eventTitle);
  const count = Math.max(0, Math.floor(data.photoCount));
  const noun = count === 1 ? 'photo' : 'photos';
  // Internal application code supplies the order link; do not accept javascript:.
  let link: string;
  try {
    const parsed = new URL(data.link);
    if (!['https:', 'http:'].includes(parsed.protocol)) throw new Error('Unsafe URL');
    link = escapeStoreEmailHtml(parsed.toString());
  } catch {
    throw new Error('A valid purchase delivery URL is required');
  }
  const preview = escapeStoreEmailHtml(`${count} original ${noun} from ${data.eventTitle} are ready to download.`);
  const message = escapeStoreEmailHtml(
    `Your ${count} purchased ${noun} from ${data.eventTitle} are ready. Download full-resolution originals directly from the secure gallery page.`,
  );
  const expiration = escapeStoreEmailHtml(expiryDescription(data.expiresAt));
  const orderNumber = data.orderNo
    ? `<tr><td align="center" style="padding:0 42px 8px;color:#777;font-size:12px;line-height:20px">Order ${escapeStoreEmailHtml(data.orderNo)}</td></tr>`
    : '';

  return `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Your photos are ready</title></head>
<body style="margin:0;padding:0;background-color:#f3f2ef;color:#202020;font-family:Arial,Helvetica,sans-serif">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent">${preview}</div>
  <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;background:#f3f2ef">
    <tr><td align="center" style="padding:36px 16px">
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="680" style="max-width:680px;width:100%;border-collapse:collapse;background:#ffffff">
        <tr><td align="center" style="padding:38px 28px 0">
          <div style="font-size:11px;line-height:18px;font-weight:700;letter-spacing:2.2px;text-transform:uppercase;color:#565656">AIRPIX</div>
        </td></tr>
        <tr><td align="center" style="padding:26px 28px 0">
          <div style="font-size:10px;line-height:16px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#96918b">Photos ready</div>
        </td></tr>
        <tr><td align="center" style="padding:16px 28px 0">
          <h1 style="margin:0;font-size:28px;line-height:38px;font-weight:500;letter-spacing:3px;text-transform:uppercase;color:#2f2f2f">Your photos are ready</h1>
        </td></tr>
        <tr><td align="center" style="padding:16px 42px 0">
          <p style="margin:0;font-size:13px;line-height:22px;color:#777">${title}</p>
        </td></tr>
        <tr><td align="center" style="padding:42px 42px 0">
          <p style="margin:0;max-width:520px;font-size:15px;line-height:27px;color:#585858;text-align:left">${message}</p>
        </td></tr>
        <tr><td align="center" style="padding:30px 36px 34px">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
            <td align="center" bgcolor="#ec6300" style="background:#ec6300">
              <a href="${link}" style="display:inline-block;padding:15px 34px;font-size:12px;line-height:16px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#ffffff;text-decoration:none">Download your photos</a>
            </td>
          </tr></table>
        </td></tr>
        ${orderNumber}
        <tr><td align="center" style="padding:0 42px 12px">
          <p style="margin:0;font-size:11px;line-height:19px;color:#7a7a7a">${expiration}</p>
        </td></tr>
        <tr><td align="center" style="padding:0 42px 42px">
          <p style="margin:0;font-size:11px;line-height:19px;color:#7a7a7a">Use the same link to download now or later. Please keep this link private.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}
