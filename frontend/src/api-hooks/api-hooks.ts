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
  import.meta.env.VITE_BASE_URL ??
  runtimeProcess.process?.env?.BASE_URL ??
  "";

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
  if (typeof window !== "undefined") {
    window.location.href = `${window.location.origin}${window.location.pathname}#/login`;
  }
};

function parseAxiosError(error: AxiosError): ApiError {
  const res = error.response?.data as
    | { message?: string | { message?: string | string[] } }
    | undefined;
  const statusCode = error.response?.status ?? 500;

  let message = "Something went wrong";

  if (res?.message) {
    if (Array.isArray(res.message?.message)) {
      message = res.message.message[0];
    } else if (typeof res.message === "string") {
      message = res.message;
    } else if (typeof res.message?.message === "string") {
      message = res.message.message;
    }
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

      if (options?.redirectOnUnauthorized !== false && (status === 401 || status === 403)) {
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
