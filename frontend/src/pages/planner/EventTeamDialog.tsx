import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Copy,
  Link2,
  Loader2,
  RefreshCw,
  Search,
  Trash2,
  UserPlus,
} from "lucide-react";
import {
  DeleteRequestAxios,
  PatchRequestAxios,
  PostRequestAxios,
} from "@/api-hooks/api-hooks";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "sonner";

type Candidate = {
  _id: string;
  name: string;
  email?: string;
  phone?: string;
  role?: string;
};

type Album = { _id: string; title: string };
type Member = {
  _id: string;
  role: string;
  status: string;
  canPublish?: boolean;
  userId?: Candidate | string;
  assignedAlbumIds?: Album[];
};

type Props = {
  eventId: string | null;
  eventTitle?: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
};

const roles = [
  ["photographer", "Photographer"],
  ["assistant_photographer", "Assistant photographer"],
  ["event_planner", "Event planner"],
  ["retoucher", "Retoucher"],
  ["reviewer", "Reviewer"],
] as const;

export default function EventTeamDialog({
  eventId,
  eventTitle,
  open,
  onOpenChange,
}: Props) {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [selectedUserId, setSelectedUserId] = useState<string>();
  const [role, setRole] = useState("photographer");
  const [albumId, setAlbumId] = useState("all");
  const [joinCode, setJoinCode] = useState("");

  const members = useQueryWrapper<{ data: Member[] }>(
    ["event-team", eventId],
    `/event-members?eventId=${eventId || ""}`,
    {
      withToken: true,
      withCredentials: true,
      enabled: open && Boolean(eventId),
    },
  );
  const candidates = useQueryWrapper<{ data: Candidate[] }>(
    ["team-candidates"],
    `/user/team-candidates?eventId=${eventId || ""}`,
    { withToken: true, withCredentials: true, enabled: open },
  );
  const albums = useQueryWrapper<{ data: Album[] }>(
    ["event-team-albums", eventId],
    `/album/get-all?eventId=${eventId || ""}`,
    {
      withToken: true,
      withCredentials: true,
      enabled: open && Boolean(eventId),
    },
  );

  const currentMembers = members.data?.data || [];
  const memberUserIds = new Set(
    currentMembers
      .map((member) =>
        typeof member.userId === "object" ? member.userId?._id : member.userId,
      )
      .filter(Boolean),
  );
  const needle = search.trim().toLowerCase();
  const filteredCandidates = (candidates.data?.data || []).filter(
    (candidate) => {
      if (memberUserIds.has(candidate._id)) return false;
      if (!needle) return true;
      return [candidate.name, candidate.email, candidate.phone]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(needle));
    },
  );

  const joinLink = joinCode
    ? `${window.location.origin}${window.location.pathname}#/join/${joinCode}`
    : "";

  const joinCodeMutation = useMutation({
    mutationFn: async (rotate: boolean) => {
      if (!eventId) throw new Error("Event is missing");
      const request = rotate ? PatchRequestAxios : PostRequestAxios;
      const [response, error] = await request<{ code?: string }>(
        rotate
          ? `/event-members/join-code/rotate?eventId=${eventId}`
          : `/event-members/join-code?eventId=${eventId}`,
        {},
        { withToken: true, withCredentials: true },
      );
      if (error || !response?.code) {
        throw new Error(error?.message || "Could not create join link");
      }
      return response.code;
    },
    onSuccess: (code) => setJoinCode(code),
    onError: (error: Error) => toast.error(error.message),
  });

  const copyJoinLink = async () => {
    if (!joinLink) return;
    await navigator.clipboard.writeText(joinLink);
    toast.success("Photographer join link copied");
  };
  const addMutation = useMutation({
    mutationFn: async () => {
      if (!eventId || !selectedUserId) throw new Error("Select a team member");
      const [response, error] = await PostRequestAxios(
        "/event-members",
        {
          eventId,
          userId: selectedUserId,
          role,
          assignedAlbumIds: albumId === "all" ? [] : [albumId],
          canPublish: ["photographer", "assistant_photographer"].includes(role),
        },
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Could not invite team member");
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["event-team", eventId] });
      setSelectedUserId(undefined);
      toast.success("Team invitation created");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const removeMutation = useMutation({
    mutationFn: async (memberId: string) => {
      const [response, error] = await DeleteRequestAxios(
        `/event-members?id=${memberId}`,
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Could not remove member");
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["event-team", eventId] });
      toast.success("Team member removed");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const updateMutation = useMutation({
    mutationFn: async ({
      id,
      nextRole,
      assignedAlbumIds,
    }: {
      id: string;
      nextRole?: string;
      assignedAlbumIds?: string[];
    }) => {
      const payload: Record<string, unknown> = {};
      if (nextRole) {
        payload.role = nextRole;
        payload.canPublish = [
          "photographer",
          "assistant_photographer",
        ].includes(nextRole);
      }
      if (assignedAlbumIds) payload.assignedAlbumIds = assignedAlbumIds;
      const [response, error] = await PatchRequestAxios(
        `/event-members?id=${id}`,
        payload,
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Could not update team member");
      return response;
    },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["event-team", eventId] }),
    onError: (error: Error) => toast.error(error.message),
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <DialogTitle>Event team</DialogTitle>
          <DialogDescription>
            {eventTitle || "Event"}: photographers, planners and retouchers
            share one workflow. Photographer seats are not capped here.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5">
          <div className="rounded-xl border p-4">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <div className="flex items-center gap-2">
                  <Link2 className="h-4 w-4" />
                  <p className="font-semibold">Quick photographer join</p>
                </div>
                <p className="mt-1 text-sm text-muted-foreground">
                  Share one event link. Signed-in photographers join this event
                  immediately.
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button
                  type="button"
                  variant="outline"
                  disabled={joinCodeMutation.isPending}
                  onClick={() => joinCodeMutation.mutate(Boolean(joinCode))}
                >
                  {joinCodeMutation.isPending ? (
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  ) : joinCode ? (
                    <RefreshCw className="mr-2 h-4 w-4" />
                  ) : (
                    <Link2 className="mr-2 h-4 w-4" />
                  )}
                  {joinCode ? "Rotate link" : "Create join link"}
                </Button>
                {joinCode ? (
                  <Button type="button" onClick={copyJoinLink}>
                    <Copy className="mr-2 h-4 w-4" /> Copy link
                  </Button>
                ) : null}
              </div>
            </div>
            {joinCode ? (
              <div className="mt-3 grid gap-2 sm:grid-cols-[120px_1fr]">
                <Input readOnly value={joinCode} aria-label="Event join code" />
                <Input readOnly value={joinLink} aria-label="Event join link" />
              </div>
            ) : null}
          </div>
          <div className="rounded-xl border p-4">
            <div className="mb-3 flex items-center justify-between gap-3">
              <div>
                <p className="font-semibold">Invite team member</p>
                <p className="text-sm text-muted-foreground">
                  Assign a role and optional shooting category.
                </p>
              </div>
              <Badge variant="secondary">Unlimited photographers</Badge>
            </div>
            <div className="grid gap-3 md:grid-cols-2">
              <div className="relative md:col-span-2">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search name, email or phone"
                  className="pl-9"
                />
              </div>
              <Select value={selectedUserId} onValueChange={setSelectedUserId}>
                <SelectTrigger>
                  <SelectValue placeholder="Choose person" />
                </SelectTrigger>
                <SelectContent>
                  {filteredCandidates.map((candidate) => (
                    <SelectItem key={candidate._id} value={candidate._id}>
                      {candidate.name}
                      {candidate.email ? ` - ${candidate.email}` : ""}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select value={role} onValueChange={setRole}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {roles.map(([value, label]) => (
                    <SelectItem key={value} value={value}>
                      {label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select value={albumId} onValueChange={setAlbumId}>
                <SelectTrigger>
                  <SelectValue placeholder="Category" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All categories</SelectItem>
                  {(albums.data?.data || []).map((album) => (
                    <SelectItem key={album._id} value={album._id}>
                      {album.title}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button
                onClick={() => addMutation.mutate()}
                disabled={!selectedUserId || addMutation.isPending}
              >
                {addMutation.isPending ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <UserPlus className="mr-2 h-4 w-4" />
                )}
                Send invitation
              </Button>
            </div>
          </div>

          <div>
            <div className="mb-3 flex items-center justify-between">
              <div>
                <p className="font-semibold">Current team</p>
                <p className="text-sm text-muted-foreground">
                  Each photo keeps the member and category that produced it.
                </p>
              </div>
              <Badge variant="outline">{currentMembers.length} members</Badge>
            </div>
            {members.isLoading ? (
              <div className="flex h-28 items-center justify-center">
                <Loader2 className="h-5 w-5 animate-spin" />
              </div>
            ) : currentMembers.length === 0 ? (
              <div className="rounded-xl border border-dashed p-6 text-sm text-muted-foreground">
                No team members yet.
              </div>
            ) : (
              <div className="max-h-80 space-y-2 overflow-y-auto pr-1">
                {currentMembers.map((member) => {
                  const person =
                    typeof member.userId === "object"
                      ? member.userId
                      : undefined;
                  const isOwner = member.role === "owner";
                  return (
                    <div
                      key={member._id}
                      className="flex flex-col gap-3 rounded-xl border p-3 sm:flex-row sm:items-center"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">
                          {person?.name || person?.email || "Team member"}
                        </p>
                        <p className="truncate text-xs text-muted-foreground">
                          {person?.email || person?.phone || ""}
                        </p>
                      </div>
                      <div className="flex flex-wrap items-center gap-2">
                        {isOwner ? (
                          <Badge>Owner</Badge>
                        ) : (
                          <Select
                            value={member.role}
                            onValueChange={(nextRole) =>
                              updateMutation.mutate({
                                id: member._id,
                                nextRole,
                              })
                            }
                          >
                            <SelectTrigger className="h-8 w-48">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {roles.map(([value, label]) => (
                                <SelectItem key={value} value={value}>
                                  {label}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        )}
                        {["photographer", "assistant_photographer"].includes(
                          member.role,
                        ) ? (
                          <Select
                            value={
                              (member.assignedAlbumIds || []).length === 1
                                ? member.assignedAlbumIds![0]._id
                                : "all"
                            }
                            onValueChange={(nextAlbumId) =>
                              updateMutation.mutate({
                                id: member._id,
                                assignedAlbumIds:
                                  nextAlbumId === "all" ? [] : [nextAlbumId],
                              })
                            }
                          >
                            <SelectTrigger className="h-8 w-44">
                              <SelectValue placeholder="Category" />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="all">
                                All categories
                              </SelectItem>
                              {(albums.data?.data || []).map((album) => (
                                <SelectItem key={album._id} value={album._id}>
                                  {album.title}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        ) : null}
                        <Badge
                          variant={
                            member.status === "active" ? "default" : "secondary"
                          }
                        >
                          {member.status}
                        </Badge>
                        {(member.assignedAlbumIds || []).map((album) => (
                          <Badge key={album._id} variant="outline">
                            {album.title}
                          </Badge>
                        ))}
                        {!isOwner ? (
                          <Button
                            variant="ghost"
                            size="icon"
                            disabled={removeMutation.isPending}
                            onClick={() => removeMutation.mutate(member._id)}
                          >
                            <Trash2 className="h-4 w-4 text-destructive" />
                          </Button>
                        ) : null}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
