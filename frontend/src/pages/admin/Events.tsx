import { useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Calendar, Eye, Loader2, MoreHorizontal, Plus, Trash2, Upload, X } from "lucide-react";
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
import AdminLayout from "./AdminLayout";
import { DeleteRequestAxios, PatchRequestAxios, PostRequestAxios } from "../../../api-hooks/api-hooks";
import { useQueryWrapper } from "../../../api-hooks/react-query-wrapper";

type EventType = {
  _id: string;
  title: string;
  description?: string;
  image?: { url?: string };
  isPublished: boolean;
  isActive: boolean;
  createdAt: string;
  userId?: {
    _id?: string;
    name?: string;
    email?: string;
  };
};

type EventsResponse = {
  data: EventType[];
  page: number;
  limit: number;
  totalItems: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
};

type UserOption = {
  _id: string;
  name: string;
  email: string;
};

type UsersResponse = {
  data: UserOption[];
};

type EventFormData = {
  title: string;
  description: string;
  userId: string;
  image?: { url?: string };
};

type ImageUploadResponse = {
  message: string;
  url: string;
};

const defaultFormData: EventFormData = {
  title: "",
  description: "",
  userId: "",
};

export default function Events() {
  const queryClient = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [viewEvent, setViewEvent] = useState<EventType | null>(null);
  const [formData, setFormData] = useState<EventFormData>(defaultFormData);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);

  const eventsQuery = useQueryWrapper<EventsResponse>(
    ["admin-events"],
    "/event/get-all?limit=100&isActive=all&isPublished=all",
    { withToken: true, withCredentials: true },
  );

  const usersQuery = useQueryWrapper<UsersResponse>(
    ["admin-users-for-events"],
    "/user/get-all-admin?limit=100&isActive=all",
    { withToken: true, withCredentials: true },
  );

  const refreshEvents = async () => {
    await queryClient.invalidateQueries({ queryKey: ["admin-events"] });
  };

  const uploadImage = async (file: File) => {
    const body = new FormData();
    body.append("file", file);

    const [response, error] = await PostRequestAxios<ImageUploadResponse>(
      "/image/upload-admin",
      body,
      {
        withToken: true,
        withCredentials: true,
        headers: { "Content-Type": "multipart/form-data" },
      },
    );

    if (error || !response) {
      throw new Error(error?.message || "Image upload failed");
    }

    return response.url;
  };

  const createEventMutation = useMutation({
    mutationFn: async (data: EventFormData) => {
      let image = data.image;

      if (imageFile) {
        const url = await uploadImage(imageFile);
        image = { url };
      }

      const [response, error] = await PostRequestAxios<EventType>(
        "/event",
        {
          title: data.title,
          description: data.description,
          userId: data.userId,
          ...(image ? { image } : {}),
        },
        { withToken: true, withCredentials: true },
      );

      if (error || !response) {
        throw new Error(error?.message || "Failed to create event");
      }

      return response;
    },
    onSuccess: async () => {
      toast.success("Event created");
      setDialogOpen(false);
      setFormData(defaultFormData);
      setImageFile(null);
      setImagePreview(null);
      await refreshEvents();
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to create event");
    },
  });

  const deleteEventMutation = useMutation({
    mutationFn: async (id: string) => {
      const [response, error] = await DeleteRequestAxios<EventType>(`/event/delete?id=${id}`, {
        withToken: true,
        withCredentials: true,
      });

      if (error || !response) {
        throw new Error(error?.message || "Failed to delete event");
      }

      return response;
    },
    onSuccess: async () => {
      toast.success("Event deleted");
      await refreshEvents();
    },
    onError: (error: Error) => {
      toast.error(error.message || "Failed to delete event");
    },
  });

  const toggleActiveMutation = useMutation({
    mutationFn: async (id: string) => {
      const [response, error] = await PatchRequestAxios<EventType>(`/event/toggle-active?id=${id}`, {}, {
        withToken: true,
        withCredentials: true,
      });

      if (error || !response) {
        throw new Error(error?.message || "Failed to toggle active");
      }

      return response;
    },
    onSuccess: refreshEvents,
  });

  const togglePublishedMutation = useMutation({
    mutationFn: async (id: string) => {
      const [response, error] = await PatchRequestAxios<EventType>(`/event/toggle-published?id=${id}`, {}, {
        withToken: true,
        withCredentials: true,
      });

      if (error || !response) {
        throw new Error(error?.message || "Failed to toggle published");
      }

      return response;
    },
    onSuccess: refreshEvents,
  });

  const handleImageSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setImageFile(file);
    const reader = new FileReader();
    reader.onloadend = () => setImagePreview(reader.result as string);
    reader.readAsDataURL(file);
  };

  const clearImage = () => {
    setImageFile(null);
    setImagePreview(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  const events = eventsQuery.data?.data || [];
  const users = usersQuery.data?.data || [];
  const loading = eventsQuery.isLoading || usersQuery.isLoading;

  return (
    <AdminLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Events</h1>
            <p className="text-muted-foreground">Admin can view all events and create for any user.</p>
          </div>
          <Button onClick={() => setDialogOpen(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Create Event
          </Button>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>All Events</CardTitle>
            <CardDescription>Every event from every user.</CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="flex h-32 items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Title</TableHead>
                    <TableHead>User</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {events.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={5} className="h-24 text-center">
                        No events found.
                      </TableCell>
                    </TableRow>
                  ) : (
                    events.map((event) => (
                      <TableRow key={event._id}>
                        <TableCell className="font-medium">{event.title}</TableCell>
                        <TableCell>{event.userId?.name || event.userId?.email || "-"}</TableCell>
                        <TableCell>
                          <div className="flex gap-1">
                            <Badge variant={event.isActive ? "default" : "secondary"}>
                              {event.isActive ? "Active" : "Inactive"}
                            </Badge>
                            <Badge variant={event.isPublished ? "outline" : "destructive"}>
                              {event.isPublished ? "Published" : "Draft"}
                            </Badge>
                          </div>
                        </TableCell>
                        <TableCell>{new Date(event.createdAt).toLocaleDateString()}</TableCell>
                        <TableCell className="text-right">
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button variant="ghost" size="sm" className="h-8 w-8 p-0">
                                <MoreHorizontal className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => setViewEvent(event)}>
                                <Eye className="mr-2 h-4 w-4" />
                                View
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => toggleActiveMutation.mutate(event._id)}>
                                {event.isActive ? "Deactivate" : "Activate"}
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => togglePublishedMutation.mutate(event._id)}>
                                {event.isPublished ? "Unpublish" : "Publish"}
                              </DropdownMenuItem>
                              <DropdownMenuItem
                                className="text-red-600 focus:text-red-600"
                                onClick={() => deleteEventMutation.mutate(event._id)}
                              >
                                <Trash2 className="mr-2 h-4 w-4" />
                                Delete
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Create Event</DialogTitle>
              <DialogDescription>Create event for any user.</DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="space-y-2">
                <Label>User</Label>
                <Select value={formData.userId} onValueChange={(value) => setFormData({ ...formData, userId: value })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select user" />
                  </SelectTrigger>
                  <SelectContent>
                    {users.map((user) => (
                      <SelectItem key={user._id} value={user._id}>
                        {user.name} - {user.email}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Event Title</Label>
                <Input
                  value={formData.title}
                  onChange={(event) => setFormData({ ...formData, title: event.target.value })}
                  placeholder="Event title"
                />
              </div>
              <div className="space-y-2">
                <Label>Image</Label>
                <div
                  className="cursor-pointer rounded-lg border-2 border-dashed p-4 text-center hover:bg-muted/50"
                  onClick={() => fileInputRef.current?.click()}
                >
                  {imagePreview ? (
                    <div className="relative inline-block">
                      <img src={imagePreview} alt="Preview" className="mx-auto max-h-40 rounded" />
                      <Button
                        type="button"
                        variant="destructive"
                        size="sm"
                        className="absolute right-2 top-2 h-6 w-6 p-0"
                        onClick={(event) => {
                          event.stopPropagation();
                          clearImage();
                        }}
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ) : (
                    <div className="py-4">
                      <Upload className="mx-auto mb-2 h-8 w-8 text-muted-foreground" />
                      <p className="text-sm text-muted-foreground">Click to upload image</p>
                    </div>
                  )}
                </div>
                <input ref={fileInputRef} type="file" className="hidden" accept="image/*" onChange={handleImageSelect} />
              </div>
              <div className="space-y-2">
                <Label>Description</Label>
                <Textarea
                  value={formData.description}
                  onChange={(event) => setFormData({ ...formData, description: event.target.value })}
                  placeholder="Description"
                />
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button
                onClick={() => createEventMutation.mutate(formData)}
                disabled={!formData.userId || !formData.title || createEventMutation.isPending}
              >
                {createEventMutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Create
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        <Dialog open={!!viewEvent} onOpenChange={(open) => !open && setViewEvent(null)}>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>{viewEvent?.title}</DialogTitle>
              <DialogDescription>{viewEvent?.userId?.name || viewEvent?.userId?.email}</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              {viewEvent?.image?.url && (
                <img src={viewEvent.image.url} alt={viewEvent.title} className="h-64 w-full rounded-lg object-cover" />
              )}
              <p className="text-sm text-muted-foreground">{viewEvent?.description || "No description"}</p>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    </AdminLayout>
  );
}
