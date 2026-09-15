import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { Check, Loader2, Radio, Users } from "lucide-react";
import { PatchRequestAxios } from "@/api-hooks/api-hooks";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";

type Membership = {
  _id: string;
  role: string;
  status: string;
  eventId?: { _id?: string; title?: string } | null;
  invitedBy?: { name?: string; email?: string } | null;
};

type Response = { data: Membership[]; totalItems: number };

export default function PendingTeamInvitations() {
  const queryClient = useQueryClient();
  const memberships = useQueryWrapper<Response>(
    ["planner-memberships"],
    "/event-members/mine",
    { withToken: true, withCredentials: true },
  );

  const pending = (memberships.data?.data || []).filter(
    (member) => member.status === "pending",
  );
  const activeConsoleAssignments = (memberships.data?.data || []).filter(
    (member) =>
      member.status === "active" &&
      ["event_planner", "retoucher", "reviewer"].includes(member.role),
  );

  const acceptMutation = useMutation({
    mutationFn: async (id: string) => {
      const [response, error] = await PatchRequestAxios(
        `/event-members/accept?id=${id}`,
        {},
        { withToken: true, withCredentials: true },
      );
      if (error || !response) {
        throw new Error(error?.message || "Failed to accept team invitation");
      }
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["planner-memberships"] });
      queryClient.invalidateQueries({ queryKey: ["events"] });
      queryClient.invalidateQueries({ queryKey: ["workspace-access"] });
      toast.success("Team invitation accepted");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  if (
    memberships.isLoading ||
    (pending.length === 0 && activeConsoleAssignments.length === 0)
  ) {
    return null;
  }

  return (
    <section className="rounded-2xl border bg-background p-4">
      <div className="mb-3 flex items-center gap-2">
        <Users className="h-4 w-4" />
        <h2 className="font-semibold">Team invitations</h2>
        <Badge variant="secondary">{pending.length} pending</Badge>
      </div>
      <div className="space-y-2">
        {activeConsoleAssignments.map((member) => (
          <div
            key={`active-${member._id}`}
            className="flex flex-col gap-3 rounded-xl bg-muted/40 p-3 sm:flex-row sm:items-center"
          >
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">
                {member.eventId?.title || "Event team"}
              </p>
              <p className="text-xs text-muted-foreground">
                Active {member.role.replace(/_/g, " ")} assignment
              </p>
            </div>
            {member.eventId?._id ? (
              <Button size="sm" variant="outline" asChild>
                <Link to={`/planner/live/${member.eventId._id}`}>
                  <Radio className="mr-2 h-4 w-4" />
                  Live console
                </Link>
              </Button>
            ) : null}
          </div>
        ))}
        {pending.map((member) => (
          <div
            key={member._id}
            className="flex flex-col gap-3 rounded-xl bg-muted/40 p-3 sm:flex-row sm:items-center"
          >
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">
                {member.eventId?.title || "Event team"}
              </p>
              <p className="text-xs text-muted-foreground">
                {member.role.replace(/_/g, " ")} - invited by{" "}
                {member.invitedBy?.name ||
                  member.invitedBy?.email ||
                  "Event owner"}
              </p>
            </div>
            <Button
              size="sm"
              disabled={acceptMutation.isPending}
              onClick={() => acceptMutation.mutate(member._id)}
            >
              {acceptMutation.isPending ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Check className="mr-2 h-4 w-4" />
              )}
              Accept
            </Button>
          </div>
        ))}
      </div>
    </section>
  );
}
