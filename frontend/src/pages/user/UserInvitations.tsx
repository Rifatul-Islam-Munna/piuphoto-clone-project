import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Calendar,
  CheckCircle2,
  Clock3,
  Loader2,
  Mail,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import UserLayout from "./UserLayout";
import { PatchRequestAxios } from "@/api-hooks/api-hooks";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";

type PhotographerInvitation = {
  _id: string;
  status: "pending" | "accepted";
  createdAt: string;
  respondedAt?: string | null;
  event: {
    _id: string;
    title: string;
    description?: string | null;
    image?: { url?: string } | null;
  } | null;
  inviter: {
    _id: string;
    name: string;
    email?: string | null;
    phone?: string | null;
    userId?: string | null;
  } | null;
};

type PhotographerInvitationsResponse = {
  data: PhotographerInvitation[];
  totalItems: number;
  pendingItems: number;
  acceptedItems: number;
};

export default function UserInvitations() {
  const queryClient = useQueryClient();
  const userStr = localStorage.getItem("user");
  const user = userStr ? JSON.parse(userStr) : null;

  const { data, isLoading } = useQueryWrapper<PhotographerInvitationsResponse>(
    ["my-photographer-invitations"],
    "/event/my-photographer-invitations",
    {
      withToken: true,
      withCredentials: true,
      enabled: user?.role === "photographer",
    },
  );

  const acceptInvitation = async (id: string) => {
    const [response, error] = await PatchRequestAxios<{
      message: string;
      data: PhotographerInvitation;
    }>(`/event/accept-invitation?id=${id}`, {}, {
      withToken: true,
      withCredentials: true,
    });

    if (error || !response) {
      throw new Error(error?.message || "Failed to accept invitation");
    }

    return response;
  };

  const acceptMutation = useMutation({
    mutationFn: acceptInvitation,
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["my-photographer-invitations"],
      });
      toast.success("Invitation accepted");
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to accept invitation");
    },
  });

  if (user?.role !== "photographer") {
    return (
      <UserLayout>
        <Card className="max-w-2xl">
          <CardHeader>
            <CardTitle>Invitation Page</CardTitle>
            <CardDescription>
              Only photographer accounts can accept event invitations here.
            </CardDescription>
          </CardHeader>
        </Card>
      </UserLayout>
    );
  }

  const invitations = data?.data || [];

  return (
    <UserLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold">My Invitations</h1>
          <p className="text-muted-foreground">
            Accept pending event invitations here.
          </p>
        </div>

        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Total</CardTitle>
              <Calendar className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{data?.totalItems || 0}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Pending</CardTitle>
              <Clock3 className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{data?.pendingItems || 0}</div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Accepted</CardTitle>
              <CheckCircle2 className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{data?.acceptedItems || 0}</div>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Invitation List</CardTitle>
            <CardDescription>
              Pending stays pending until you press accept.
            </CardDescription>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="flex h-32 items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : invitations.length === 0 ? (
              <div className="rounded-lg border border-dashed p-8 text-center text-muted-foreground">
                No invitations yet.
              </div>
            ) : (
              <div className="space-y-4">
                {invitations.map((invitation) => (
                  <div
                    key={invitation._id}
                    className="rounded-xl border p-4"
                  >
                    <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                      <div className="space-y-3">
                        <div>
                          <div className="flex items-center gap-2">
                            <h3 className="font-semibold">
                              {invitation.event?.title || "Untitled event"}
                            </h3>
                            <Badge
                              variant={
                                invitation.status === "accepted"
                                  ? "default"
                                  : "secondary"
                              }
                            >
                              {invitation.status}
                            </Badge>
                          </div>
                          <p className="text-sm text-muted-foreground">
                            {invitation.event?.description || "No description"}
                          </p>
                        </div>

                        <div className="flex items-start gap-2 text-sm text-muted-foreground">
                          <Mail className="mt-0.5 h-4 w-4" />
                          <div>
                            <p>
                              Invited by {invitation.inviter?.name || "Unknown"}
                            </p>
                            <p>
                              {invitation.inviter?.email ||
                                invitation.inviter?.phone ||
                                invitation.inviter?.userId ||
                                "-"}
                            </p>
                          </div>
                        </div>

                        <p className="text-xs text-muted-foreground">
                          Sent{" "}
                          {new Date(invitation.createdAt).toLocaleDateString()}
                        </p>
                      </div>

                      <div className="flex items-center gap-2">
                        {invitation.status === "pending" ? (
                          <Button
                            onClick={() =>
                              acceptMutation.mutate(invitation._id)
                            }
                            disabled={acceptMutation.isPending}
                          >
                            {acceptMutation.isPending && (
                              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                            )}
                            Accept Invite
                          </Button>
                        ) : (
                          <Badge variant="outline">Accepted</Badge>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </UserLayout>
  );
}

