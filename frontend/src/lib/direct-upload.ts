import axios from "axios";
import { PostRequestAxios } from "@/api-hooks/api-hooks";

type UploadTicket = {
  uploadUrl: string;
  method: "PUT";
  headers: Record<string, string>;
  key: string;
  url: string;
};

type UploadedFile = { url: string; key: string; message: string };
type UploadError = { message: string; statusCode: number };

// Separate client keeps app cookies, tokens and API interceptors away from R2.
const storage = axios.create({ withCredentials: false });

export async function UploadFileAxios(
  file: File,
  admin = false,
): Promise<[UploadedFile | null, UploadError | null]> {
  const [ticket, error] = await PostRequestAxios<UploadTicket>(
    admin ? "/image/presign-admin" : "/image/presign",
    {
      fileName: file.name,
      contentType: file.type || "application/octet-stream",
      size: file.size,
    },
    { withToken: true, withCredentials: true },
  );
  if (error || !ticket?.uploadUrl || !ticket.url) {
    return [null, error || { message: "Could not prepare upload", statusCode: 500 }];
  }

  try {
    // Send raw bytes. Multipart encoding would change the signed body length.
    await storage.put(ticket.uploadUrl, file, { headers: ticket.headers });
    return [{ url: ticket.url, key: ticket.key, message: "File uploaded successfully" }, null];
  } catch (error) {
    return [null, {
      message: "Direct storage upload failed. Please retry.",
      statusCode: axios.isAxiosError(error) ? error.response?.status || 500 : 500,
    }];
  }
}
