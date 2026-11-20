import { BlobWriter, ZipWriter } from "@zip.js/zip.js";

export type GalleryDownloadFile = {
  url: string;
  name: string;
};

type SaveFileHandle = {
  createWritable: () => Promise<WritableStream<Uint8Array>>;
};

type SaveFilePickerWindow = Window & {
  showSaveFilePicker?: (options: {
    suggestedName: string;
    types: Array<{ description: string; accept: Record<string, string[]> }>;
  }) => Promise<SaveFileHandle>;
};

export type ZipResult =
  | { kind: "saved"; count: number }
  | { kind: "ready"; count: number; fileName: string; objectUrl: string };

const MAX_BROWSER_ZIP_BYTES = 96 * 1024 * 1024;
const allowedExtensions = new Set([
  ".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif", ".heic", ".heif",
  ".tif", ".tiff", ".dng", ".arw", ".cr2", ".cr3", ".nef", ".raf",
  ".rw2", ".orf", ".pef", ".mp4", ".mov", ".webm", ".m4v",
]);

export function archiveName(title: string): string {
  const cleaned = String(title || "event-photos")
    .replace(/\.zip$/i, "")
    .replace(/[<>:"/\\|?*\x00-\x1f]+/g, "-")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 110);
  return `${cleaned || "event-photos"}.zip`;
}

export function galleryFileName(
  url: string,
  id: string,
  mediaType: "photo" | "video" | undefined,
  index: number,
): string {
  let extension = mediaType === "video" ? ".mp4" : ".jpg";
  try {
    const suffix = new URL(url, window.location.origin).pathname
      .toLowerCase().match(/\.[a-z0-9]{2,5}$/)?.[0];
    if (suffix && allowedExtensions.has(suffix)) extension = suffix;
  } catch { /* Keep the sensible fallback extension. */ }
  const safeId = String(id || "").match(/^[a-f\d]{24}$/i)?.[0];
  return `photo-${safeId?.slice(-12) || String(index + 1).padStart(5, "0")}${extension}`;
}

export function shouldUseNativeBrowserDownload(userAgent: string): boolean {
  // All iPhone/iPad browsers use WebKit and need a real HTTP attachment.
  return /iPhone|iPad|iPod/i.test(userAgent)
    || (/Macintosh/i.test(userAgent) && typeof navigator !== "undefined" && navigator.maxTouchPoints > 1)
    || (/Safari/i.test(userAgent) && !/Chrome|Chromium|CriOS|FxiOS|Edg/i.test(userAgent));
}

export function hasDirectDiskSave(): boolean {
  return typeof (window as SaveFilePickerWindow).showSaveFilePicker === "function";
}

/** Must be invoked synchronously inside the original user click, before fetches. */
export async function reserveZipFile(fileName: string): Promise<WritableStream<Uint8Array> | null> {
  const picker = (window as SaveFilePickerWindow).showSaveFilePicker;
  if (!picker) return null;
  const file = await picker.call(window, {
    suggestedName: archiveName(fileName),
    types: [{ description: "ZIP archive", accept: { "application/zip": [".zip"] } }],
  });
  return file.createWritable();
}

function cappedStream(source: ReadableStream<Uint8Array>, tracker: { bytes: number }) {
  const reader = source.getReader();
  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      const { done, value } = await reader.read();
      if (done) {
        controller.close();
        return;
      }
      tracker.bytes += value.byteLength;
      if (tracker.bytes > MAX_BROWSER_ZIP_BYTES) {
        await reader.cancel().catch(() => undefined);
        controller.error(new Error("Archive exceeds the browser's safe memory limit. Use the native ZIP download instead."));
        return;
      }
      controller.enqueue(value);
    },
    cancel(reason) {
      return reader.cancel(reason);
    },
  });
}

/**
 * Downloads object bytes directly from Cloudflare/storage to the browser.
 * ZIP.js stores already-compressed image bytes without expensive recompression.
 * Browsers lacking disk streaming get an explicit "Save ZIP" link as a second
 * user gesture (rather than Safari-blocked synthetic clicks after async work).
 */
export async function createGalleryZip(
  files: GalleryDownloadFile[],
  name: string,
  options: {
    writable?: WritableStream<Uint8Array> | null;
    signal?: AbortSignal;
    onProgress?: (completed: number, total: number) => void;
  } = {},
): Promise<ZipResult> {
  if (!files.length) throw new Error("No photos available for download");
  const blobWriter = options.writable ? null : new BlobWriter("application/zip");
  const zipWriter = new ZipWriter(options.writable || blobWriter!, {
    zip64: true,
    level: 0,
  });
  const tracker = { bytes: 0 };
  const names = new Set<string>();
  let count = 0;

  try {
    for (const file of files) {
      if (options.signal?.aborted) throw new Error("Download cancelled");
      if (!file.url) throw new Error("Photo has no downloadable URL");
      let response: Response;
      try {
        response = await fetch(file.url, {
          signal: options.signal,
          mode: "cors",
          credentials: "omit",
          referrerPolicy: "no-referrer",
        });
      } catch (error) {
        if (options.signal?.aborted) throw new Error("Download cancelled");
        throw new Error("Cloud storage blocked direct browser access. Check the photo bucket CORS policy or use the native ZIP download.");
      }
      if (!response.ok || !response.body) {
        throw new Error(`Failed to fetch photo (HTTP ${response.status}). Use native ZIP download instead.`);
      }
      const base = file.name.replace(/[<>:"/\\|?*\x00-\x1f]/g, "-") || "photo";
      const dot = base.lastIndexOf(".");
      const stem = dot > 0 ? base.slice(0, dot) : base;
      const extension = dot > 0 ? base.slice(dot) : "";
      let unique = base;
      let suffix = 2;
      while (names.has(unique.toLowerCase())) unique = `${stem}-${suffix++}${extension}`;
      names.add(unique.toLowerCase());

      await zipWriter.add(
        unique,
        blobWriter ? cappedStream(response.body, tracker) : response.body,
        { level: 0 },
      );
      count += 1;
      options.onProgress?.(count, files.length);
    }
    await zipWriter.close();
    if (!blobWriter) return { kind: "saved", count };
    const blob = await blobWriter.getData();
    return { kind: "ready", count, fileName: archiveName(name), objectUrl: URL.createObjectURL(blob) };
  } catch (error) {
    if (options.writable) await options.writable.abort(error).catch(() => undefined);
    else await zipWriter.close().catch(() => undefined);
    throw error;
  }
}

export function nativeDownloadUrl(
  base: string,
  args: {
    eventId: string;
    albumId?: string;
    accessToken?: string;
    guestToken?: string;
    ids?: string[];
    single?: boolean;
  },
): string {
  const root = new URL(base || window.location.origin, window.location.origin);
  const url = new URL(
    args.single ? "/public-downloads/event-photo" : "/public-downloads/event-photos.zip",
    root.origin,
  );
  url.searchParams.set("eventId", args.eventId);
  if (args.albumId) url.searchParams.set("albumId", args.albumId);
  if (args.accessToken && !args.guestToken) url.searchParams.set("accessToken", args.accessToken);
  if (args.guestToken) url.searchParams.set("guestToken", args.guestToken);
  if (args.ids?.length) url.searchParams.set("ids", args.ids.join(","));
  return url.toString();
}

/** A real user click on an HTTP attachment is accepted by Safari's downloader. */
export function launchNativeDownload(url: string): void {
  const link = document.createElement("a");
  link.href = url;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  link.style.display = "none";
  document.body.appendChild(link);
  link.click();
  link.remove();
}
