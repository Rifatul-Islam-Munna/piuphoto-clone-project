import { downloadAttachmentHeader } from './download-attachment-header';

describe('Safari and Chrome native download headers', () => {
  it('sends an ASCII filename first and the UTF-8 filename parameter second', () => {
    expect(downloadAttachmentHeader('Nikos 1.jpg'))
      .toBe('attachment; filename="Nikos 1.jpg"; filename*=UTF-8\'\'Nikos%201.jpg');
    const unicode = downloadAttachmentHeader('বাংলা photo.jpg');
    expect(unicode).toContain('filename="_____ photo.jpg"');
    expect(unicode).toContain("filename*=UTF-8''");
    expect(unicode).toContain('%');
  });
  it('prevents path traversal and control characters in download names', () => {
    const header = downloadAttachmentHeader('../bad\\photo\r\n";.png');
    expect(header).not.toContain('\r');
    expect(header).not.toContain('\n');
    expect(header).not.toContain('../');
    expect(header).toContain('attachment; filename="');
  });
});
