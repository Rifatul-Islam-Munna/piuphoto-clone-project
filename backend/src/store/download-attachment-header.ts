/**
 * RFC 6266 attachment disposition with an ASCII fallback for Safari,
 * and UTF-8 filename* for Chromium/Firefox. No javascript Blob URLs needed.
 */
export function downloadAttachmentHeader(input: string): string {
  const basename = String(input || 'photo')
    .split(/[\\/]/)
    .pop() || 'photo';
  const printable = Array.from(basename)
    .map((char) => {
      const code = char.codePointAt(0) || 0;
      return code < 32 || code === 127 || /["\\;:]/.test(char) ? '_' : char;
    })
    .join('')
    .trim()
    .slice(0, 160) || 'photo';
  const ascii = Array.from(printable)
    .map((char) => {
      const code = char.codePointAt(0) || 0;
      return code < 32 || code > 126 || char === '%' ? '_' : char;
    })
    .join('');
  const encoded = encodeURIComponent(printable)
    .replace(/[!'()*]/g, (char) => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encoded}`;
}
