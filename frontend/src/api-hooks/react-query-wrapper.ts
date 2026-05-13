import { QueryKey, useQuery, UseQueryOptions } from "@tanstack/react-query";
import { GetRequestNormal } from "./api-hooks";

type QueryWrapperOptions<T> = Omit<
  UseQueryOptions<T, Error, T>,
  "queryKey" | "queryFn"
> & {
  withToken?: boolean;
  withCredentials?: boolean;
};

export function useQueryWrapper<T>(
  key: QueryKey,
  url: string,
  options?: QueryWrapperOptions<T>,
  revalidate?: number,
  tag?:string
) {
  const { withToken = false, withCredentials = true, ...queryOptions } =
    options ?? {};

  return useQuery<T, Error>({
    queryKey: key,
    queryFn: () =>
      GetRequestNormal<T>(url, revalidate, tag, {
        withToken,
        withCredentials,
      }),
  
    ...queryOptions,
  });
}

