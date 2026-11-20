/**
 * Save individual full-resolution photos straight into a user-chosen folder.
 * Available only in browsers with the File System Access API (e.g. Chromium).
 * Safari/iOS guests use explicit one-photo-at-a-time HTTP attachments instead.
 */
export type GalleryFolderFile = {
  url: string;
  name: string;
  fallbackUrl?: string;
};

export type GalleryFolderHandle = {
  getFileHandle: (
    name: string,
    options: { create: true },
  ) => Promise<{
    createWritable: () => Promise<WritableStream<Uint8Array>>;
  }>;
};

type DirectoryPickerWindow = Window & {
  showDirectoryPicker?: (options?: {
    mode?: "readwrite";
  }) => Promise<GalleryFolderHandle>;
};

export function canSaveGalleryFolder(): boolean {
  return typeof window !== "undefined" &&
    window.isSecureContext !== false &&
    typeof (window as DirectoryPickerWindow).showDirectoryPicker === "function";
}

/** Call immediately in an actual click handler before any fetch or await. */
export function chooseGalleryFolder(): Promise<GalleryFolderHandle> {
  const picker = (window as DirectoryPickerWindow).showDirectoryPicker;
  if (!picker || !canSaveGalleryFolder()) {
    throw new Error("Your browser cannot save a folder directly. Use individual downloads or ZIP.");
  }
  return picker.call(window, { mode: "readwrite" });
}

export function safeGalleryFolderName(name: string): string {
  const safe = String(name || "photo")
    .replace(/[<>:"/\\|?*]+/g, "-")
    .split("")
    .map((character) => character.charCodeAt(0) < 32 ? "-" : character)
    .join("")
    .replace(/^[.-]+/, "")
    .replace(/[. ]+$/, "")
    .trim()
    .slice(0, 180);
  return safe || "photo";
}

async function fetchImageForFolder(
  file: GalleryFolderFile,
  signal: AbortSignal,
): Promise<Response> {
  const fetchSource = (url: string) => fetch(url, {
    signal,
    credentials: "omit",
    mode: "cors",
    referrerPolicy: "no-referrer",
  });
  try {
    const primary = await fetchSource(file.url);
    if (primary.ok && primary.body) return primary;
    if (!file.fallbackUrl) throw new Error(`Image download failed (HTTP ${primary.status})`);
  } catch (error) {
    if (signal.aborted || !file.fallbackUrl) throw error;
  }
  const fallback = await fetchSource(file.fallbackUrl!);
  if (!fallback.ok || !fallback.body) {
    throw new Error(`Image download failed (HTTP ${fallback.status}).`);
  }
  return fallback;
}

/**
 * One photo at a time; never buffers an entire ZIP or gallery in RAM.
 * Download URLs must already be authorized by the gallery and server.
 */
export async function saveGalleryToFolder(
  directory: GalleryFolderHandle,
  files: GalleryFolderFile[],
  options: {
    signal?: AbortSignal;
    onProgress?: (done: number, total: number) => void;
  } = {},
): Promise<number> {
  if (!files.length) throw new Error("No downloadable photos selected.");
  const signal = options.signal ?? new AbortController().signal;
  const used = new Set<string>();
  let completed = 0;
  for (const file of files) {
    if (signal.aborted) {
      throw signal.reason || new DOMException("Download cancelled", "AbortError");
    }
    if (!file.url) throw new Error("One selected photo has no URL");
    const clean = safeGalleryFolderName(file.name);
    const lastDot = clean.lastIndexOf(".");
    const stem = lastDot > 0 ? clean.slice(0, lastDot) : clean;
    const extension = lastDot > 0 ? clean.slice(lastDot) : "";
    let name = clean;
    let suffix = 2;
    while (used.has(name.toLowerCase())) {
      name = `${stem}-${suffix++}${extension}`;
    }
    used.add(name.toLowerCase());
    const response = await fetchImageForFolder(file, signal);
    if (signal.aborted) {
      throw signal.reason || new DOMException("Download cancelled", "AbortError");
    }
    const handle = await directory.getFileHandle(name, { create: true });
    const output = await handle.createWritable();
    try {
      // Browser streams each image directly to disk; no arrayBuffer/blob().
      await response.body!.pipeTo(output, { signal });
    } catch (error) {
      await output.abort(error).catch(() => undefined);
      throw error;
    }
    completed += 1;
    options.onProgress?.(completed, files.length);
  }
  return completed;
}
