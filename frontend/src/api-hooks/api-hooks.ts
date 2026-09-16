import axios, { AxiosError, AxiosRequestConfig } from "axios";

type ApiError = { message: string; statusCode: number };

type RequestOptions = {
  withToken?: boolean;
  withCredentials?: boolean;
  redirectOnUnauthorized?: boolean;
  headers?: Record<string, string>;
};

const runtimeProcess = globalThis as typeof globalThis & {
  process?: { env?: Record<string, string | undefined> };
};

const baseUrl =
  import.meta.env.VITE_BASE_URL ?? runtimeProcess.process?.env?.BASE_URL ?? "";

const getToken = () => {
  if (typeof window === "undefined") {
    return null;
  }

  const localToken = window.localStorage.getItem("access_token");
  if (localToken) {
    return localToken;
  }

  const cookieToken = document.cookie
    .split("; ")
    .find((cookie) => cookie.startsWith("access_token="))
    ?.split("=")[1];

  return cookieToken ?? null;
};

const redirectToLogin = () => {
  if (typeof window === "undefined") return;

  const currentRoute = window.location.hash.replace(/^#/, "") || "/";
  const next =
    currentRoute.startsWith("/") && !currentRoute.startsWith("/login")
      ? `?next=${encodeURIComponent(currentRoute)}`
      : "";
  window.location.href = `${window.location.origin}${window.location.pathname}#/login${next}`;
};

function parseAxiosError(error: AxiosError): ApiError {
  const res = error.response?.data as
    { message?: string | { message?: string | string[] } } | undefined;
  const statusCode = error.response?.status ?? 500;

  let message = "Something went wrong";

  const rawMessage = res?.message;
  if (typeof rawMessage === "string") {
    message = rawMessage;
  } else if (rawMessage && Array.isArray(rawMessage.message)) {
    message = rawMessage.message[0] || message;
  } else if (rawMessage && typeof rawMessage.message === "string") {
    message = rawMessage.message;
  }

  return { message, statusCode };
}

const buildAxiosConfig = ({
  withToken = false,
  withCredentials = true,
  headers = {},
}: RequestOptions = {}): AxiosRequestConfig => {
  const token = withToken ? getToken() : null;

  return {
    withCredentials,
    headers: {
      ...headers,
      ...(token ? { access_token: token } : {}),
    },
  };
};

async function handleAxiosRequest<T>(
  request: Promise<{ data: T }>,
  options?: RequestOptions,
): Promise<[T | null, ApiError | null]> {
  try {
    const { data } = await request;
    return [data, null];
  } catch (error) {
    if (axios.isAxiosError(error)) {
      const status = error.response?.status;

      // A 403 means the user is authenticated but cannot perform this action.
      // Sending it to login creates a redirect loop and loses the requested page.
      if (options?.redirectOnUnauthorized !== false && status === 401) {
        redirectToLogin();
      }

      return [null, parseAxiosError(error)];
    }

    return [null, { message: "Unknown error", statusCode: 500 }];
  }
}

export const PostRequestAxios = async <T>(
  url: string,
  payload: unknown,
  options?: RequestOptions,
): Promise<[T | null, ApiError | null]> =>
  handleAxiosRequest<T>(
    axios.post<T>(`${baseUrl}${url}`, payload, buildAxiosConfig(options)),
    options,
  );

export const PatchRequestAxios = async <T>(
  url: string,
  payload: unknown,
  options?: RequestOptions,
): Promise<[T | null, ApiError | null]> =>
  handleAxiosRequest<T>(
    axios.patch<T>(`${baseUrl}${url}`, payload, buildAxiosConfig(options)),
    options,
  );

export const GetRequestAxios = async <T>(
  url: string,
  options?: RequestOptions,
): Promise<[T | null, ApiError | null]> =>
  handleAxiosRequest<T>(
    axios.get<T>(`${baseUrl}${url}`, buildAxiosConfig(options)),
    options,
  );

export const GetRequestNormal = async <T>(
  url: string,
  _revalidate = 0,
  _revalidateTags = "stumaps",
  options?: RequestOptions,
): Promise<T> => {
  const [data, error] = await GetRequestAxios<T>(url, options);

  if (error) {
    throw new Error(error.message);
  }

  if (!data) {
    throw new Error("No data found");
  }

  return data;
};

export const DeleteRequestAxios = async <T>(
  url: string,
  options?: RequestOptions,
): Promise<[T | null, ApiError | null]> =>
  handleAxiosRequest<T>(
    axios.delete<T>(`${baseUrl}${url}`, buildAxiosConfig(options)),
    options,
  );
