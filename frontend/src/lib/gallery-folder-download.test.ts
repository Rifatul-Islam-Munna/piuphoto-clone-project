import { afterEach, describe, expect, it, vi } from "vitest";
import {
  canSaveGalleryFolder,
  chooseGalleryFolder,
  safeGalleryFolderName,
  saveGalleryToFolder,
  type GalleryFolderHandle,
} from "./gallery-folder-download";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  Object.defineProperty(window, "showDirectoryPicker", {
    configurable: true, value: undefined,
  });
});

function fakeDirectory() {
  const contents = new Map<string, number[]>();
  const directory: GalleryFolderHandle = {
    getFileHandle: vi.fn(async (name: string) => ({
      createWritable: async () => new WritableStream<Uint8Array>({
        write(chunk) {
          const existing = contents.get(name) || [];
          contents.set(name, [...existing, ...chunk]);
        },
      }),
    })),
  };
  return { directory, contents };
}

describe("individual photo folder export", () => {
  it("does not offer folder writing on browsers without the File System Access API", () => {
    expect(canSaveGalleryFolder()).toBe(false);
    expect(() => chooseGalleryFolder()).toThrow(/cannot save a folder/);
  });

  it("asks for read-write folder permission from the original user click", async () => {
    const { directory } = fakeDirectory();
    const picker = vi.fn(async () => directory);
    Object.defineProperty(window, "showDirectoryPicker", { configurable: true, value: picker });
    expect(canSaveGalleryFolder()).toBe(true);
    expect(await chooseGalleryFolder()).toBe(directory);
    expect(picker).toHaveBeenCalledWith({ mode: "readwrite" });
  });

  it("streams photos one by one and handles duplicate filenames", async () => {
    const { directory, contents } = fakeDirectory();
    const progress = vi.fn();
    const fetcher = vi.fn(async () =>
      new Response(new Uint8Array([1, 2, 3, 4]), { status: 200 }));
    vi.stubGlobal("fetch", fetcher);
    const count = await saveGalleryToFolder(directory, [
      { url: "https://cloud.test/one.jpg", name: "DSC0001.jpg" },
      { url: "https://cloud.test/two.jpg", name: "DSC0001.jpg" },
    ], { onProgress: progress });
    expect(count).toBe(2);
    expect([...contents.keys()]).toEqual(["DSC0001.jpg", "DSC0001-2.jpg"]);
    expect(contents.get("DSC0001-2.jpg")).toEqual([1, 2, 3, 4]);
    expect(progress).toHaveBeenLastCalledWith(2, 2);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it("tries the authorized backend original URL if Cloudflare browser CORS blocks access", async () => {
    const { directory, contents } = fakeDirectory();
    const fetcher = vi.fn(async (url: string) => {
      if (url.startsWith("https://r2.test/")) throw new TypeError("CORS");
      return new Response(new Uint8Array([7, 8]), { status: 200 });
    });
    vi.stubGlobal("fetch", fetcher);
    await saveGalleryToFolder(directory, [{
      url: "https://r2.test/camera.jpg",
      fallbackUrl: "https://api.test/public-downloads/event-photo?ids=authorized",
      name: "camera.jpg",
    }]);
    expect(contents.get("camera.jpg")).toEqual([7, 8]);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it("aborts without starting further files and does not consume whole archives", async () => {
    const { directory, contents } = fakeDirectory();
    const controller = new AbortController();
    const fetcher = vi.fn(async () => new Response(new Uint8Array([2]), { status: 200 }));
    vi.stubGlobal("fetch", fetcher);
    await expect(saveGalleryToFolder(directory, [
      { url: "https://r2.test/a", name: "a.jpg" },
      { url: "https://r2.test/b", name: "b.jpg" },
    ], {
      signal: controller.signal,
      onProgress: () => controller.abort(),
    })).rejects.toBeTruthy();
    expect([...contents.keys()]).toEqual(["a.jpg"]);
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it("sanitizes filenames to avoid accidental folders or unsafe names", () => {
    expect(safeGalleryFolderName("../private\\photo.jpg")).toBe("private-photo.jpg");
    expect(safeGalleryFolderName("a:b?.png")).toBe("a-b-.png");
  });
});
