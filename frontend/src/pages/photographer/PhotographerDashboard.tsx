import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import {
  CalendarDays,
  Camera,
  CheckCircle2,
  Clock3,
  Loader2,
  ShieldCheck,
  Smartphone,
} from "lucide-react";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { PatchRequestAxios } from "@/api-hooks/api-hooks";
import { useWorkspaceAccess } from "@/hooks/use-workspace-access";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { toast } from "sonner";
import PhotographerLayout from "./PhotographerLayout";

type LegacyInvitation = {
  _id: string;
  status: "pending" | "accepted";
  event?: { _id?: string; title?: string; description?: string } | null;
  inviter?: { name?: string; email?: string } | null;
};

type InvitationResponse = {
  data: LegacyInvitation[];
  pendingItems: number;
  acceptedItems: number;
};

type Membership = {
  _id: string;
  role: string;
  status: string;
  canPublish?: boolean;
  eventId?: { _id?: string; title?: string; description?: string } | null;
  assignedAlbumIds?: Array<{ _id?: string; title?: string }>;
};

type MembershipResponse = { data: Membership[]; totalItems: number };

export default function PhotographerDashboard() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const workspaceAccess = useWorkspaceAccess();
  const invitations = useQueryWrapper<InvitationResponse>(
    ["photographer-invitations"],
    "/event/my-photographer-invitations",
    { withToken: true, withCredentials: true },
  );
  const memberships = useQueryWrapper<MembershipResponse>(
    ["photographer-memberships"],
    "/event-members/mine",
    { withToken: true, withCredentials: true },
  );

  const acceptMutation = useMutation({
    mutationFn: async (id: string) => {
      const [response, error] = await PatchRequestAxios(
        `/event/accept-invitation?id=${id}`,
        {},
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Failed to accept invitation");
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["photographer-invitations"] });
      queryClient.invalidateQueries({ queryKey: ["photographer-memberships"] });
      queryClient.invalidateQueries({ queryKey: ["workspace-access"] });
      toast.success("Event joined");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const acceptMemberMutation = useMutation({
    mutationFn: async (id: string) => {
      const [response, error] = await PatchRequestAxios(
        `/event-members/accept?id=${id}`,
        {},
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Failed to accept team invitation");
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["photographer-memberships"] });
      queryClient.invalidateQueries({ queryKey: ["workspace-access"] });
      toast.success("Team invitation accepted");
    },
    onError: (error: Error) => toast.error(error.message),
  });
  const pending = (invitations.data?.data || []).filter(
    (item) => item.status === "pending",
  );
  const legacyPendingEventIds = new Set(
    pending.map((invite) => invite.event?._id).filter(Boolean),
  );
  const pendingMemberships = (memberships.data?.data || []).filter((item) => {
    if (item.status !== "pending") return false;
    return !legacyPendingEventIds.has(item.eventId?._id);
  });
  const activeMemberships = (memberships.data?.data || []).filter(
    (item) =>
      item.status === "active" &&
      ["photographer", "assistant_photographer"].includes(item.role),
  );
  const loading = invitations.isLoading || memberships.isLoading;

  return (
    <PhotographerLayout>
      <div className="space-y-6">
        <section className="flex flex-col gap-4 rounded-2xl border bg-background p-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-medium text-muted-foreground">
              Photographer workspace
            </p>
            <h1 className="mt-1 text-2xl font-bold">
              Shoot. Transfer. Keep moving.
            </h1>
            <p className="mt-2 max-w-2xl text-sm text-muted-foreground">
              Events and assignments live here. Camera connection and the
              real-time transfer list stay in the mobile shooting app.
            </p>
          </div>
          <div className="flex items-center gap-3 rounded-xl bg-muted/50 px-4 py-3">
            <Smartphone className="h-5 w-5" />
            <div>
              <p className="text-sm font-semibold">Mobile shooting app</p>
              <p className="text-xs text-muted-foreground">
                Use OTG or wireless as before
              </p>
            </div>
          </div>
        </section>

        {workspaceAccess.data?.planner ? (
          <Card className="border-primary/25 bg-primary/5">
            <CardContent className="flex flex-col gap-4 p-5 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="font-semibold">Solo photographer mode is enabled</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  Create your own events without a planner invitation, then manage galleries, password protection, retouch, store, analytics and API from this photographer account.
                </p>
              </div>
              <div className="flex shrink-0 flex-wrap gap-2">
                <Button onClick={() => navigate("/planner/dashboard")}>
                  <CalendarDays className="mr-2 h-4 w-4" />
                  My solo events
                </Button>
                <Button variant="outline" onClick={() => navigate("/planner/gallery")}>
                  <ShieldCheck className="mr-2 h-4 w-4" />
                  Gallery tools
                </Button>
              </div>
            </CardContent>
          </Card>
        ) : null}

        <div className="grid gap-4 sm:grid-cols-3">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">Assigned events</CardTitle>
            </CardHeader>
            <CardContent className="text-3xl font-bold">
              {activeMemberships.length}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">Pending invites</CardTitle>
            </CardHeader>
            <CardContent className="text-3xl font-bold">
              {pending.length + pendingMemberships.length}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">Camera workflow</CardTitle>
            </CardHeader>
            <CardContent className="flex items-center gap-2 text-sm font-semibold">
              <CheckCircle2 className="h-5 w-5" /> Existing OTG / wireless
              preserved
            </CardContent>
          </Card>
        </div>

        {loading ? (
          <div className="flex min-h-48 items-center justify-center rounded-2xl border bg-background">
            <Loader2 className="h-7 w-7 animate-spin" />
          </div>
        ) : (
          <div className="grid gap-5 xl:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>My shooting assignments</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {activeMemberships.length === 0 ? (
                  <p className="rounded-xl border border-dashed p-5 text-sm text-muted-foreground">
                    No active event assignment yet.
                  </p>
                ) : (
                  activeMemberships.map((member) => (
                    <div key={member._id} className="rounded-xl border p-4">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="font-semibold">
                            {member.eventId?.title || "Event"}
                          </p>
                          <p className="mt-1 text-sm text-muted-foreground">
                            {member.eventId?.description ||
                              "Ready for live capture"}
                          </p>
                        </div>
                        <Badge variant="secondary">
                          {member.role.replace(/_/g, " ")}
                        </Badge>
                      </div>
                      <div className="mt-3 flex flex-wrap gap-2">
                        {(member.assignedAlbumIds || []).length > 0 ? (
                          member.assignedAlbumIds!.map((album) => (
                            <Badge
                              key={album._id || album.title}
                              variant="outline"
                            >
                              {album.title || "Category"}
                            </Badge>
                          ))
                        ) : (
                          <Badge variant="outline">
                            All assigned categories
                          </Badge>
                        )}
                      </div>
                    </div>
                  ))
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Invitations</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {pending.length === 0 && pendingMemberships.length === 0 ? (
                  <p className="rounded-xl border border-dashed p-5 text-sm text-muted-foreground">
                    No invitation waiting for you.
                  </p>
                ) : null}
                {pending.map((invite) => (
                  <div
                    key={invite._id}
                    className="flex items-center justify-between gap-4 rounded-xl border p-4"
                  >
                    <div className="min-w-0">
                      <p className="truncate font-semibold">
                        {invite.event?.title || "Event invitation"}
                      </p>
                      <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
                        <Clock3 className="h-3.5 w-3.5" />
                        From{" "}
                        {invite.inviter?.name ||
                          invite.inviter?.email ||
                          "Event Planner"}
                      </p>
                    </div>
                    <Button
                      size="sm"
                      disabled={acceptMutation.isPending}
                      onClick={() => acceptMutation.mutate(invite._id)}
                    >
                      {acceptMutation.isPending ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        "Join"
                      )}
                    </Button>
                  </div>
                ))}
                {pendingMemberships.map((member) => (
                  <div
                    key={member._id}
                    className="flex items-center justify-between gap-4 rounded-xl border p-4"
                  >
                    <div className="min-w-0">
                      <p className="truncate font-semibold">
                        {member.eventId?.title || "Team invitation"}
                      </p>
                      <p className="mt-1 text-xs text-muted-foreground">
                        Role: {member.role.replace(/_/g, " ")}
                      </p>
                    </div>
                    <Button
                      size="sm"
                      disabled={acceptMemberMutation.isPending}
                      onClick={() => acceptMemberMutation.mutate(member._id)}
                    >
                      {acceptMemberMutation.isPending ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        "Join"
                      )}
                    </Button>
                  </div>
                ))}
              </CardContent>
            </Card>
          </div>
        )}
      </div>
    </PhotographerLayout>
  );
}
