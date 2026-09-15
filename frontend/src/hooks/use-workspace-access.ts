import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";

export type WorkspaceAccess = {
  planner: boolean;
  photographer: boolean;
  retoucher: boolean;
  reviewer: boolean;
  roles: string[];
};

export function useWorkspaceAccess() {
  const token = localStorage.getItem("access_token");
  const userRaw = localStorage.getItem("user");
  const user = userRaw ? JSON.parse(userRaw) : null;

  return useQueryWrapper<WorkspaceAccess>(
    ["workspace-access", user?._id || user?.id || user?.email],
    "/event-members/workspaces",
    {
      withToken: true,
      withCredentials: true,
      enabled: Boolean(token) && user?.role !== "admin",
      staleTime: 30_000,
    },
  );
}
