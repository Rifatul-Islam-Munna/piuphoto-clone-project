import { useMemo, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Calendar,
  Camera,
  CheckCircle2,
  Eye,
  Loader2,
  MoreHorizontal,
  Pencil,
  Plus,
  Trash2,
  Upload,
  UserPlus,
  X,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import UserLayout from "./UserLayout";
import {
  DeleteRequestAxios,
  PatchRequestAxios,
  PostRequestAxios,
} from "../../../api-hooks/api-hooks";
import { useQueryWrapper } from "../../../api-hooks/react-query-wrapper";

type PhotographerOption = {
  _id: string;
  name: string;
  email?: string | null;
  phone?: string | null;
  userId?: string | null;
};

type EventInvitation = {
  _id: string;
  status: "pending" | "accepted";
  createdAt: string;
  respondedAt?: string | null;
  photographer: PhotographerOption | null;
};

type InviteSummary = {
  maxPhotographers: number;
  totalInvited: number;
  pendingInvites: number;
  acceptedInvites: number;
  remainingInvites: number;
};

type EventType = {
  _id: string;
  title: string;
  description?: string;
  image?: { url?: string };
  isPublished: boolean;
  isActive: boolean;
  createdAt: string;
  invitations: EventInvitation[];
  inviteSummary: InviteSummary;
};

type EventsResponse = {
  data: EventType[];
  page: number;
  limit: number;
  totalItems: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  subscription?: {
    maxPhotographers: number;
    planTitle?: string | null;
  };
};

type EventFormData = {
  title: string;
  description: string;
  image?: { url?: string };
};

type ImageUploadResponse = {
  message: string;
  url: string;
};

type UserListResponse = {
  data: PhotographerOption[];
};

const defaultFormData: EventFormData = {
  title: "",
  description: "",
};

export default function UserDashboard() {
  const queryClient = useQueryClient();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [formData, setFormData] = useState<EventFormData>(defaultFormData);
  const [editingEvent, setEditingEvent] = useState<EventType | null>(null);
  const [viewEvent, setViewEvent] = useState<EventType | null>(null);
  const [inviteEventId, setInviteEventId] = useState<string | null>(null);
  const [selectedPhotographerId, setSelectedPhotographerId] = useState<
    string | undefined
  >(undefined);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const { data: eventsData, isLoading } = useQueryWrapper<EventsResponse>(
    ["events"],
    "/event/my-events",
    { withToken: true, withCredentials: true },
  );

  const photographersQuery = useQueryWrapper<UserListResponse>(
    ["photographers-for-invite"],
    "/user/photographers-for-invite",
    {
      withToken: true,
      withCredentials: true,
      enabled: !!inviteEventId,
    },
  );

  const uploadImage = async (file: File): Promise<{ url: string }> => {
    const uploadFormData = new FormData();
    uploadFormData.append("file", file);
    const [response, error] = await PostRequestAxios<ImageUploadResponse>(
      "/image/upload",
      uploadFormData,
      {
        withToken: true,
        withCredentials: true,
        headers: { "Content-Type": "multipart/form-data" },
      },
    );

    if (error || !response) {
      throw new Error(error?.message || "Failed to upload image");
    }

    return { url: response.url };
  };

  const createEvent = async (data: EventFormData) => {
    const eventData = { title: data.title, description: data.description };

    if (data.image?.url) {
      Object.assign(eventData, { image: data.image });
    }

    const [response, error] = await PostRequestAxios<EventType>(
      "/event",
      eventData,
      { withToken: true, withCredentials: true },
    );

    if (error || !response) {
      throw new Error(error?.message || "Failed to create event");
    }

    return response;
  };

  const updateEvent = async ({
    id,
    data,
  }: {
    id: string;
    data: EventFormData;
  }) => {
    const [response, error] = await PatchRequestAxios<EventType>(
      `/event/update?id=${id}`,
      data,
      { withToken: true, withCredentials: true },
    );

    if (error || !response) {
      throw new Error(error?.message || "Failed to update event");
    }

    return response;
  };

  const deleteEvent = async (id: string) => {
    const [response, error] = await DeleteRequestAxios<EventType>(
      `/event/delete?id=${id}`,
      {
        withToken: true,
        withCredentials: true,
      },
    );

    if (error || !response) {
      throw new Error(error?.message || "Failed to delete event");
    }

    return response;
  };

  const toggleEventActive = async (id: string) => {
    const [response, error] = await PatchRequestAxios<EventType>(
      `/event/toggle-active?id=${id}`,
      {},
      {
        withToken: true,
        withCredentials: true,
      },
    );

    if (error || !response) {
      throw new Error(error?.message || "Failed to toggle event status");
    }

    return response;
  };

  const toggleEventPublished = async (id: string) => {
    const [response, error] = await PatchRequestAxios<EventType>(
      `/event/toggle-published?id=${id}`,
      {},
      {
        withToken: true,
        withCredentials: true,
      },
    );

    if (error || !response) {
      throw new Error(error?.message || "Failed to toggle event status");
    }

    return response;
  };

  const invitePhotographer = async ({
    eventId,
    photographerId,
  }: {
    eventId: string;
    photographerId: string;
  }) => {
    const [response, error] = await PostRequestAxios<{
      message: string;
      data: EventInvitation;
    }>("/event/invite-photographer", { eventId, photographerId }, {
      withToken: true,
      withCredentials: true,
    });

    if (error || !response) {
      throw new Error(error?.message || "Failed to invite photographer");
    }

    return response;
  };

  const createMutation = useMutation({
    mutationFn: async (data: EventFormData) => {
      let imageUrl = data.image?.url;

      if (imageFile) {
        const uploaded = await uploadImage(imageFile);
        imageUrl = uploaded.url;
      }

      return createEvent({
        ...data,
        image: imageUrl ? { url: imageUrl } : undefined,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event created successfully");
      setDialogOpen(false);
      setFormData(defaultFormData);
      setImageFile(null);
      setImagePreview(null);
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to create event");
    },
  });

  const updateMutation = useMutation({
    mutationFn: async ({
      id,
      data,
    }: {
      id: string;
      data: EventFormData;
    }) => {
      let imageUrl = data.image?.url;

      if (imageFile) {
        const uploaded = await uploadImage(imageFile);
        imageUrl = uploaded.url;
      }

      const nextImage = imageFile
        ? { url: imageUrl }
        : imagePreview
          ? data.image
          : { url: "" };

      return updateEvent({ id, data: { ...data, image: nextImage } });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event updated successfully");
      setDialogOpen(false);
      setFormData(defaultFormData);
      setEditingEvent(null);
      setImageFile(null);
      setImagePreview(null);
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to update event");
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteEvent,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event deleted successfully");
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to delete event");
    },
  });

  const toggleActiveMutation = useMutation({
    mutationFn: toggleEventActive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event status updated");
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to update event status");
    },
  });

  const togglePublishedMutation = useMutation({
    mutationFn: toggleEventPublished,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event publish status updated");
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to update event status");
    },
  });

  const inviteMutation = useMutation({
    mutationFn: invitePhotographer,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      setSelectedPhotographerId(undefined);
      toast.success("Photographer invited");
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to invite photographer");
    },
  });

  const handleSubmit = () => {
    if (editingEvent) {
      updateMutation.mutate({ id: editingEvent._id, data: formData });
      return;
    }

    createMutation.mutate(formData);
  };

  const handleDelete = (id: string) => {
    if (!confirm("Are you sure you want to delete this event?")) {
      return;
    }

    deleteMutation.mutate(id);
  };

  const handleDialogClose = (open: boolean) => {
    setDialogOpen(open);

    if (!open) {
      setEditingEvent(null);
      setFormData(defaultFormData);
      setImageFile(null);
      setImagePreview(null);
    }
  };

  const handleImageSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];

    if (file) {
      setImageFile(file);
      const reader = new FileReader();
      reader.onloadend = () => setImagePreview(reader.result as string);
      reader.readAsDataURL(file);
    }
  };

  const handleRemoveImage = () => {
    setImageFile(null);
    setImagePreview(null);
    setFormData((prev) => ({ ...prev, image: undefined }));

    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  };

  const handleOpenInviteDialog = (eventId: string) => {
    setInviteEventId(eventId);
    setSelectedPhotographerId(undefined);
  };

  const handleCloseInviteDialog = (open: boolean) => {
    if (!open) {
      setInviteEventId(null);
      setSelectedPhotographerId(undefined);
    }
  };

  const myEvents = eventsData?.data || [];
  const subscription = eventsData?.subscription;
  const activeEvents = myEvents.filter((event) => event.isActive).length;
  const totalEvents = myEvents.length;
  const pendingInvites = myEvents.reduce(
    (total, event) => total + (event.inviteSummary?.pendingInvites || 0),
    0,
  );
  const acceptedInvites = myEvents.reduce(
    (total, event) => total + (event.inviteSummary?.acceptedInvites || 0),
    0,
  );

  const selectedInviteEvent =
    myEvents.find((event) => event._id === inviteEventId) || null;

  const availablePhotographers = useMemo(() => {
    const invitedPhotographerIds = new Set(
      (selectedInviteEvent?.invitations || [])
        .map((invitation) => invitation.photographer?._id)
        .filter(Boolean),
    );

    return (photographersQuery.data?.data || []).filter(
      (photographer) => !invitedPhotographerIds.has(photographer._id),
    );
  }, [photographersQuery.data?.data, selectedInviteEvent]);

  return (
    <UserLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Dashboard</h1>
            <p className="text-muted-foreground">
              Manage events, photographer invites, plan limits.
            </p>
          </div>
          <Button onClick={() => setDialogOpen(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Create Event
          </Button>
        </div>

        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Total Events</CardTitle>
              <Calendar className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{totalEvents}</div>
              <p className="text-xs text-muted-foreground">
                {activeEvents} active now
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">
                Max Photographers
              </CardTitle>
              <Camera className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">
                {subscription?.maxPhotographers || 0}
              </div>
              <p className="text-xs text-muted-foreground">
                {subscription?.planTitle || "No active plan"}
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">
                Pending Invites
              </CardTitle>
              <UserPlus className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{pendingInvites}</div>
              <p className="text-xs text-muted-foreground">
                Waiting photographer accept
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">
                Accepted Invites
              </CardTitle>
              <CheckCircle2 className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{acceptedInvites}</div>
              <p className="text-xs text-muted-foreground">
                Active photographer slots used
              </p>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Photographer Invite Policy</CardTitle>
            <CardDescription>
              Each event can invite up to{" "}
              <span className="font-medium">
                {subscription?.maxPhotographers || 0}
              </span>{" "}
              photographer{(subscription?.maxPhotographers || 0) === 1 ? "" : "s"}.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="rounded-lg border bg-muted/40 p-4 text-sm text-muted-foreground">
              Pending invite stays pending until photographer accepts from
              invitation page. Accepted + pending both count toward plan limit.
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>My Events</CardTitle>
            <CardDescription>
              Manage events, invite photographers, track status.
            </CardDescription>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="flex h-32 items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : myEvents.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center">
                <Calendar className="mb-4 h-12 w-12 text-muted-foreground" />
                <h3 className="text-lg font-semibold">No events yet</h3>
                <p className="mb-4 text-muted-foreground">
                  Create first event to start inviting photographers.
                </p>
                <Button onClick={() => setDialogOpen(true)}>
                  <Plus className="mr-2 h-4 w-4" />
                  Create Event
                </Button>
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Title</TableHead>
                    <TableHead>Description</TableHead>
                    <TableHead>Photographers</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {myEvents.map((event) => (
                    <TableRow key={event._id}>
                      <TableCell className="font-medium">{event.title}</TableCell>
                      <TableCell className="max-w-xs truncate">
                        {event.description || "-"}
                      </TableCell>
                      <TableCell>
                        <div className="space-y-1">
                          <p className="text-sm font-medium">
                            {event.inviteSummary.acceptedInvites}/
                            {event.inviteSummary.maxPhotographers} accepted
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {event.inviteSummary.pendingInvites} pending,{" "}
                            {event.inviteSummary.remainingInvites} left
                          </p>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="flex gap-1">
                          <Badge
                            variant={event.isActive ? "default" : "secondary"}
                          >
                            {event.isActive ? "Active" : "Inactive"}
                          </Badge>
                          <Badge
                            variant={
                              event.isPublished ? "outline" : "destructive"
                            }
                          >
                            {event.isPublished ? "Published" : "Draft"}
                          </Badge>
                        </div>
                      </TableCell>
                      <TableCell>
                        {new Date(event.createdAt).toLocaleDateString()}
                      </TableCell>
                      <TableCell className="text-right">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-8 w-8 p-0"
                            >
                              <MoreHorizontal className="h-4 w-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuItem onClick={() => setViewEvent(event)}>
                              <Eye className="mr-2 h-4 w-4" />
                              View
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => handleOpenInviteDialog(event._id)}
                            >
                              <UserPlus className="mr-2 h-4 w-4" />
                              Invitations
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => {
                                setEditingEvent(event);
                                setFormData({
                                  title: event.title,
                                  description: event.description || "",
                                  image: event.image,
                                });
                                if (event.image?.url) {
                                  setImagePreview(event.image.url);
                                }
                                setDialogOpen(true);
                              }}
                            >
                              <Pencil className="mr-2 h-4 w-4" />
                              Edit
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() =>
                                toggleActiveMutation.mutate(event._id)
                              }
                            >
                              {event.isActive ? "Deactivate" : "Activate"}
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() =>
                                togglePublishedMutation.mutate(event._id)
                              }
                            >
                              {event.isPublished ? "Unpublish" : "Publish"}
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => handleDelete(event._id)}
                              className="text-red-600 focus:text-red-600"
                            >
                              <Trash2 className="mr-2 h-4 w-4" />
                              Delete
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Dialog open={dialogOpen} onOpenChange={handleDialogClose}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                {editingEvent ? "Edit Event" : "Create New Event"}
              </DialogTitle>
              <DialogDescription>
                {editingEvent
                  ? "Update event details."
                  : "Create event, then invite photographers."}
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="title">Event Title</Label>
                <Input
                  id="title"
                  value={formData.title}
                  onChange={(event) =>
                    setFormData({ ...formData, title: event.target.value })
                  }
                  placeholder="Enter event title"
                />
              </div>
              <div className="space-y-2">
                <Label>Event Image</Label>
                <div
                  className="cursor-pointer rounded-lg border-2 border-dashed p-4 text-center transition-colors hover:bg-muted/50"
                  onClick={() => fileInputRef.current?.click()}
                >
                  {imagePreview || formData.image?.url ? (
                    <div className="relative inline-block">
                      <img
                        src={imagePreview || formData.image?.url}
                        alt="Preview"
                        className="mx-auto max-h-40 rounded"
                      />
                      <Button
                        type="button"
                        variant="destructive"
                        size="sm"
                        className="absolute right-2 top-2 h-6 w-6 p-0"
                        onClick={(event) => {
                          event.stopPropagation();
                          handleRemoveImage();
                        }}
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ) : (
                    <div className="py-4">
                      <Upload className="mx-auto mb-2 h-8 w-8 text-muted-foreground" />
                      <p className="text-sm text-muted-foreground">
                        Click to upload image
                      </p>
                    </div>
                  )}
                </div>
                <input
                  type="file"
                  ref={fileInputRef}
                  className="hidden"
                  accept="image/*"
                  onChange={handleImageSelect}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="description">Description</Label>
                <Textarea
                  id="description"
                  value={formData.description}
                  onChange={(event) =>
                    setFormData({
                      ...formData,
                      description: event.target.value,
                    })
                  }
                  placeholder="Enter event description"
                  rows={3}
                />
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button
                onClick={handleSubmit}
                disabled={
                  !formData.title ||
                  createMutation.isPending ||
                  updateMutation.isPending
                }
              >
                {(createMutation.isPending || updateMutation.isPending) && (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                )}
                {editingEvent ? "Update Event" : "Create Event"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        <Dialog
          open={!!inviteEventId}
          onOpenChange={handleCloseInviteDialog}
        >
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>Manage Photographer Invitations</DialogTitle>
              <DialogDescription>
                {selectedInviteEvent?.title || "Event"} invite count follows
                plan limit.
              </DialogDescription>
            </DialogHeader>

            {selectedInviteEvent ? (
              <div className="space-y-6">
                <div className="grid gap-3 md:grid-cols-3">
                  <Card>
                    <CardContent className="pt-6">
                      <p className="text-xs uppercase text-muted-foreground">
                        Max
                      </p>
                      <p className="text-2xl font-bold">
                        {selectedInviteEvent.inviteSummary.maxPhotographers}
                      </p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardContent className="pt-6">
                      <p className="text-xs uppercase text-muted-foreground">
                        Pending
                      </p>
                      <p className="text-2xl font-bold">
                        {selectedInviteEvent.inviteSummary.pendingInvites}
                      </p>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardContent className="pt-6">
                      <p className="text-xs uppercase text-muted-foreground">
                        Remaining
                      </p>
                      <p className="text-2xl font-bold">
                        {selectedInviteEvent.inviteSummary.remainingInvites}
                      </p>
                    </CardContent>
                  </Card>
                </div>

                <div className="space-y-3 rounded-lg border p-4">
                  <div>
                    <h3 className="font-medium">Invite photographer</h3>
                    <p className="text-sm text-muted-foreground">
                      Pending stays pending until photographer accepts.
                    </p>
                  </div>

                  {selectedInviteEvent.inviteSummary.maxPhotographers <= 0 ? (
                    <p className="text-sm text-destructive">
                      Your current plan does not allow photographer invites.
                    </p>
                  ) : selectedInviteEvent.inviteSummary.remainingInvites <= 0 ? (
                    <p className="text-sm text-destructive">
                      No slots left for this event.
                    </p>
                  ) : availablePhotographers.length === 0 ? (
                    <p className="text-sm text-muted-foreground">
                      No available photographer left to invite.
                    </p>
                  ) : (
                    <div className="flex flex-col gap-3 sm:flex-row">
                      <Select
                        value={selectedPhotographerId}
                        onValueChange={setSelectedPhotographerId}
                      >
                        <SelectTrigger className="sm:flex-1">
                          <SelectValue placeholder="Select photographer" />
                        </SelectTrigger>
                        <SelectContent>
                          {availablePhotographers.map((photographer) => (
                            <SelectItem
                              key={photographer._id}
                              value={photographer._id}
                            >
                              {photographer.name}
                              {photographer.email
                                ? ` - ${photographer.email}`
                                : ""}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Button
                        onClick={() => {
                          if (!selectedPhotographerId || !selectedInviteEvent) {
                            return;
                          }

                          inviteMutation.mutate({
                            eventId: selectedInviteEvent._id,
                            photographerId: selectedPhotographerId,
                          });
                        }}
                        disabled={!selectedPhotographerId || inviteMutation.isPending}
                      >
                        {inviteMutation.isPending && (
                          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        )}
                        Send Invite
                      </Button>
                    </div>
                  )}
                </div>

                <div className="space-y-3">
                  <div>
                    <h3 className="font-medium">Current invitations</h3>
                    <p className="text-sm text-muted-foreground">
                      Per-event photographer status list.
                    </p>
                  </div>

                  {selectedInviteEvent.invitations.length === 0 ? (
                    <div className="rounded-lg border border-dashed p-6 text-sm text-muted-foreground">
                      No invitations yet.
                    </div>
                  ) : (
                    <div className="max-h-72 space-y-3 overflow-y-auto pr-1">
                      {selectedInviteEvent.invitations.map((invitation) => (
                        <div
                          key={invitation._id}
                          className="flex items-center justify-between rounded-lg border p-3"
                        >
                          <div>
                            <p className="font-medium">
                              {invitation.photographer?.name || "Unknown"}
                            </p>
                            <p className="text-sm text-muted-foreground">
                              {invitation.photographer?.email ||
                                invitation.photographer?.phone ||
                                invitation.photographer?.userId ||
                                "-"}
                            </p>
                          </div>
                          <div className="text-right">
                            <Badge
                              variant={
                                invitation.status === "accepted"
                                  ? "default"
                                  : "secondary"
                              }
                            >
                              {invitation.status}
                            </Badge>
                            <p className="mt-1 text-xs text-muted-foreground">
                              {new Date(
                                invitation.respondedAt || invitation.createdAt,
                              ).toLocaleDateString()}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            ) : null}
          </DialogContent>
        </Dialog>

        <Dialog
          open={!!viewEvent}
          onOpenChange={(open) => !open && setViewEvent(null)}
        >
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>{viewEvent?.title}</DialogTitle>
              <DialogDescription>Event preview</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              {viewEvent?.image?.url && (
                <div className="relative h-64 w-full overflow-hidden rounded-lg bg-muted">
                  <img
                    src={viewEvent.image.url}
                    alt={viewEvent.title}
                    className="h-full w-full object-cover"
                  />
                </div>
              )}
              {viewEvent?.description && (
                <div>
                  <h3 className="mb-2 font-semibold">Description</h3>
                  <p className="text-muted-foreground">
                    {viewEvent.description}
                  </p>
                </div>
              )}
              <div className="flex gap-2">
                <Badge variant={viewEvent?.isActive ? "default" : "secondary"}>
                  {viewEvent?.isActive ? "Active" : "Inactive"}
                </Badge>
                <Badge
                  variant={viewEvent?.isPublished ? "outline" : "destructive"}
                >
                  {viewEvent?.isPublished ? "Published" : "Draft"}
                </Badge>
              </div>

              <div>
                <h3 className="mb-2 font-semibold">Photographers</h3>
                {viewEvent?.invitations?.length ? (
                  <div className="space-y-2">
                    {viewEvent.invitations.map((invitation) => (
                      <div
                        key={invitation._id}
                        className="flex items-center justify-between rounded-lg border p-3"
                      >
                        <div>
                          <p className="font-medium">
                            {invitation.photographer?.name || "Unknown"}
                          </p>
                          <p className="text-sm text-muted-foreground">
                            {invitation.photographer?.email ||
                              invitation.photographer?.phone ||
                              "-"}
                          </p>
                        </div>
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
                    ))}
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground">
                    No photographer invited yet.
                  </p>
                )}
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setViewEvent(null)}>
                Close
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </UserLayout>
  );
}
