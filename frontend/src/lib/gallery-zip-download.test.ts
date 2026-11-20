import { describe, expect, it, vi, afterEach } from "vitest";
import {
  archiveName,
  createGalleryZip,
  galleryFileName,
  nativeDownloadUrl,
  shouldUseNativeBrowserDownload,
} from "./gallery-zip-download";

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("cross-browser gallery downloads", () => {
  it("uses native HTTP downloads on Safari and all iPhones", () => {
    expect(shouldUseNativeBrowserDownload(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/ Safari/604.1",
    )).toBe(true);
    expect(shouldUseNativeBrowserDownload(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 CriOS/128 Mobile",
    )).toBe(true);
    expect(shouldUseNativeBrowserDownload(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1 Version/17.0 Safari/605.1",
    )).toBe(true);
    expect(shouldUseNativeBrowserDownload(
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0 Safari/537.36",
    )).toBe(false);
  });

  it("builds URLs to the authorized ZIP and original-photo attachments", () => {
    const url = new URL(nativeDownloadUrl("https://api.airpix.test/", {
      eventId: "507f1f77bcf86cd799439011",
      guestToken: "guest-secret",
      albumId: "507f1f77bcf86cd799439012",
    }));
    expect(url.pathname).toBe("/public-downloads/event-photos.zip");
    expect(url.searchParams.get("guestToken")).toBe("guest-secret");
    expect(url.searchParams.get("albumId")).toBe("507f1f77bcf86cd799439012");
    const single = new URL(nativeDownloadUrl("https://api.airpix.test", {
      eventId: "507f1f77bcf86cd799439011",
      ids: ["507f1f77bcf86cd799439013"],
      accessToken: "access-grant",
      single: true,
    }));
    expect(single.pathname).toBe("/public-downloads/event-photo");
    expect(single.searchParams.get("ids")).toBe("507f1f77bcf86cd799439013");
    expect(single.searchParams.get("accessToken")).toBe("access-grant");
  });

  it("sanitizes ZIP filenames and preserves original photo/video formats", () => {
    expect(archiveName('Wedding : Seattle / Oct 2026')).toBe('Wedding-Seattle-Oct-2026.zip');
    const id = "507f1f77bcf86cd799439011";
    expect(galleryFileName("https://r2.test/abc.heic", id, "photo", 0)).toBe(`photo-${id.slice(-12)}.heic`);
    expect(galleryFileName("https://r2.test/abc.mov", "bad", "video", 7)).toBe("photo-00008.mov");
  });

  it("prepares one archive rather than opening separate downloads per photo", async () => {
    const objectUrl = vi.fn(() => "blob:archive");
    Object.defineProperty(URL, "createObjectURL", { configurable: true, value: objectUrl });
    vi.stubGlobal("fetch", vi.fn(async () => new Response(
      new Uint8Array([1, 2, 3, 4]),
      { status: 200, headers: { "Content-Type": "image/jpeg" } },
    )));
    const progress = vi.fn();
    const result = await createGalleryZip([
      { url: "https://r2.test/a.jpg", name: "a.jpg" },
      { url: "https://r2.test/b.jpg", name: "b.jpg" },
    ], "Photos", { onProgress: progress });
    expect(result).toMatchObject({ kind: "ready", count: 2, fileName: "Photos.zip", objectUrl: "blob:archive" });
    expect(progress).toHaveBeenLastCalledWith(2, 2);
    expect(objectUrl).toHaveBeenCalledOnce();
    vi.unstubAllGlobals();
  });
});
