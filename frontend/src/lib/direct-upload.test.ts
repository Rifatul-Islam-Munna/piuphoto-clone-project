import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ post: vi.fn(), put: vi.fn(), create: vi.fn() }));
vi.mock("@/api-hooks/api-hooks", () => ({ PostRequestAxios: mocks.post }));
vi.mock("axios", () => ({
  default: {
    create: mocks.create.mockReturnValue({ put: mocks.put }),
    isAxiosError: (error: { isAxiosError?: boolean }) => error?.isAxiosError === true,
  },
}));

import { UploadFileAxios } from "./direct-upload";

const ticket = {
  uploadUrl: "https://r2.example.test/photos/unique.jpg?signature=example",
  url: "https://images.example.test/unique.jpg",
  key: "unique.jpg",
  method: "PUT",
  headers: { "Content-Type": "image/jpeg" },
};

describe("direct image uploads", () => {
  beforeEach(() => {
    mocks.post.mockReset().mockResolvedValue([ticket, null]);
    mocks.put.mockReset().mockResolvedValue({ status: 200 });
  });

  it("sends only metadata to the API and raw file bytes to a separate R2 client", async () => {
    const file = new File(["photo"], "camera.jpg", { type: "image/jpeg" });
    const [result, error] = await UploadFileAxios(file);
    expect(mocks.post).toHaveBeenCalledWith("/image/presign", {
      fileName: "camera.jpg", contentType: "image/jpeg", size: 5,
    }, { withToken: true, withCredentials: true });
    expect(mocks.create).toHaveBeenCalledWith({ withCredentials: false });
    expect(mocks.put).toHaveBeenCalledWith(ticket.uploadUrl, file, { headers: ticket.headers });
    expect(error).toBeNull();
    expect(result).toMatchObject({ url: ticket.url, key: ticket.key });
  });

  it("preserves admin authorization and handles missing browser MIME types", async () => {
    await UploadFileAxios(new File(["raw"], "camera.arw"), true);
    expect(mocks.post.mock.calls[0][0]).toBe("/image/presign-admin");
    expect(mocks.post.mock.calls[0][1].contentType).toBe("application/octet-stream");
  });

  it("does not upload when the signing request fails", async () => {
    mocks.post.mockResolvedValue([null, { message: "Unauthorized", statusCode: 401 }]);
    const [result, error] = await UploadFileAxios(new File(["x"], "photo.jpg"));
    expect(result).toBeNull();
    expect(error?.statusCode).toBe(401);
    expect(mocks.put).not.toHaveBeenCalled();
  });

  it("does not return an image URL after a failed PUT", async () => {
    mocks.put.mockRejectedValue({ isAxiosError: true, response: { status: 403 } });
    const [result, error] = await UploadFileAxios(new File(["x"], "photo.jpg"));
    expect(result).toBeNull();
    expect(error?.statusCode).toBe(403);
  });
});
