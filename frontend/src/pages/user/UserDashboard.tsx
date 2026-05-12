import { useState, useRef } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Calendar, Loader2, MoreHorizontal, Pencil, Trash2, Eye, Upload, X } from "lucide-react";
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import UserLayout from "./UserLayout";
import { DeleteRequestAxios, PostRequestAxios, PatchRequestAxios } from "../../../api-hooks/api-hooks";
import { useQueryWrapper } from "../../../api-hooks/react-query-wrapper";

type EventType = {
  _id: string;
  title: string;
  description?: string;
  image?: { url?: string };
  isPublished: boolean;
  isActive: boolean;
  createdAt: string;
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

type EventFormData = {
  title: string;
  description: string;
  image?: { url?: string };
};

type ImageUploadResponse = {
  message: string;
  url: string;
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
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const { data: eventsData, isLoading } = useQueryWrapper<EventsResponse>(
    ["events"],
    "/event/my-events",
    { withToken: true, withCredentials: true }
  );

  const uploadImage = async (file: File): Promise<{ url: string }> => {
    const formData = new FormData();
    formData.append("file", file);
    const [response, error] = await PostRequestAxios<ImageUploadResponse>(
      "/image/upload",
      formData,
      { withToken: true, withCredentials: true, headers: { "Content-Type": "multipart/form-data" } }
    );
    if (error || !response) throw new Error(error?.message || "Failed to upload image");
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
      { withToken: true, withCredentials: true }
    );
    if (error || !response) throw new Error(error?.message || "Failed to create event");
    return response;
  };

  const updateEvent = async ({ id, data }: { id: string; data: EventFormData }) => {
    const [response, error] = await PatchRequestAxios<EventType>(
      `/event/update?id=${id}`,
      data,
      { withToken: true, withCredentials: true }
    );
    if (error || !response) throw new Error(error?.message || "Failed to update event");
    return response;
  };

  const deleteEvent = async (id: string) => {
    const [response, error] = await DeleteRequestAxios<EventType>(`/event/delete?id=${id}`, {
      withToken: true,
      withCredentials: true,
    });
    if (error || !response) throw new Error(error?.message || "Failed to delete event");
    return response;
  };

  const toggleEventActive = async (id: string) => {
    const [response, error] = await PatchRequestAxios<EventType>(`/event/toggle-active?id=${id}`, {}, {
      withToken: true,
      withCredentials: true,
    });
    if (error || !response) throw new Error(error?.message || "Failed to toggle event status");
    return response;
  };

  const toggleEventPublished = async (id: string) => {
    const [response, error] = await PatchRequestAxios<EventType>(`/event/toggle-published?id=${id}`, {}, {
      withToken: true,
      withCredentials: true,
    });
    if (error || !response) throw new Error(error?.message || "Failed to toggle event status");
    return response;
  };

  const createMutation = useMutation({
    mutationFn: async (data: EventFormData) => {
      let imageUrl = data.image?.url;
      if (imageFile) {
        const uploaded = await uploadImage(imageFile);
        imageUrl = uploaded.url;
      }
      return createEvent({ ...data, image: imageUrl ? { url: imageUrl } : undefined });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event created successfully");
      setDialogOpen(false);
      setFormData(defaultFormData);
      setImageFile(null);
      setImagePreview(null);
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to create event");
    },
  });

  const updateMutation = useMutation({
    mutationFn: async ({ id, data }: { id: string; data: EventFormData }) => {
      let imageUrl = data.image?.url;
      if (imageFile) {
        const uploaded = await uploadImage(imageFile);
        imageUrl = uploaded.url;
      }

      const nextImage =
        imageFile
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
    onError: (error: any) => {
      toast.error(error?.message || "Failed to update event");
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteEvent,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event deleted successfully");
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to delete event");
    },
  });

  const toggleActiveMutation = useMutation({
    mutationFn: toggleEventActive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event status updated");
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to update event status");
    },
  });

  const togglePublishedMutation = useMutation({
    mutationFn: toggleEventPublished,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["events"] });
      toast.success("Event publish status updated");
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to update event status");
    },
  });

  const handleSubmit = () => {
    if (editingEvent) {
      updateMutation.mutate({ id: editingEvent._id, data: formData });
    } else {
      createMutation.mutate(formData);
    }
  };

  const handleDelete = (id: string) => {
    if (!confirm("Are you sure you want to delete this event?")) return;
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

  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
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
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  const myEvents = eventsData?.data || [];
  const activeEvents = myEvents.filter(e => e.isActive).length;
  const totalEvents = myEvents.length;

  return (
    <UserLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Dashboard</h1>
            <p className="text-muted-foreground">Welcome back! Manage your events here.</p>
          </div>
          <Button onClick={() => setDialogOpen(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Create Event
          </Button>
        </div>

        <div className="grid gap-4 md:grid-cols-2">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Total Events</CardTitle>
              <Calendar className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{totalEvents}</div>
            </CardContent>
</Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>My Events</CardTitle>
            <CardDescription>Manage your events</CardDescription>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="flex h-32 items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : myEvents.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center">
                <Calendar className="h-12 w-12 text-muted-foreground mb-4" />
                <h3 className="text-lg font-semibold">No events yet</h3>
                <p className="text-muted-foreground mb-4">Create your first event to get started</p>
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
                    <TableHead>Status</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {myEvents.map((event) => (
                    <TableRow key={event._id}>
                      <TableCell className="font-medium">{event.title}</TableCell>
                      <TableCell className="max-w-xs truncate">{event.description || "-"}</TableCell>
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
                            <DropdownMenuItem
                              onClick={() => {
                                setEditingEvent(event);
                                setFormData({ title: event.title, description: event.description || "", image: event.image });
                                if (event.image?.url) setImagePreview(event.image.url);
                                setDialogOpen(true);
                              }}
                            >
                              <Pencil className="mr-2 h-4 w-4" />
                              Edit
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => toggleActiveMutation.mutate(event._id)}>
                              {event.isActive ? "Deactivate" : "Activate"}
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => togglePublishedMutation.mutate(event._id)}>
                              {event.isPublished ? "Unpublish" : "Publish"}
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={() => handleDelete(event._id)} className="text-red-600 focus:text-red-600">
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
              <DialogTitle>{editingEvent ? "Edit Event" : "Create New Event"}</DialogTitle>
              <DialogDescription>
                {editingEvent ? "Update the details for your event." : "Fill in the details for your new event."}
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="title">Event Title</Label>
                <Input
                  id="title"
                  value={formData.title}
                  onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                  placeholder="Enter event title"
                />
              </div>
              <div className="space-y-2">
                <Label>Event Image</Label>
                <div className="border-2 border-dashed rounded-lg p-4 text-center cursor-pointer hover:bg-muted/50 transition-colors" onClick={() => fileInputRef.current?.click()}>
                  {imagePreview || formData.image?.url ? (
                    <div className="relative inline-block">
                      <img src={imagePreview || formData.image?.url} alt="Preview" className="max-h-40 mx-auto rounded" />
                      <Button type="button" variant="destructive" size="sm" className="absolute top-2 right-2 h-6 w-6 p-0" onClick={(e) => { e.stopPropagation(); handleRemoveImage(); }}>
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ) : (
                    <div className="py-4">
                      <Upload className="mx-auto h-8 w-8 text-muted-foreground mb-2" />
                      <p className="text-sm text-muted-foreground">Click to upload image</p>
                    </div>
                  )}
                </div>
                <input type="file" ref={fileInputRef} className="hidden" accept="image/*" onChange={handleImageSelect} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="description">Description</Label>
                <Textarea
                  id="description"
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
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
                disabled={!formData.title || createMutation.isPending || updateMutation.isPending}
              >
                {(createMutation.isPending || updateMutation.isPending) && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {editingEvent ? "Update Event" : "Create Event"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        <Dialog open={!!viewEvent} onOpenChange={(open) => !open && setViewEvent(null)}>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>{viewEvent?.title}</DialogTitle>
              <DialogDescription>Event Preview</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              {viewEvent?.image?.url && (
                <div className="relative w-full h-64 bg-muted rounded-lg overflow-hidden">
                  <img src={viewEvent.image.url} alt={viewEvent.title} className="w-full h-full object-cover" />
                </div>
              )}
              <div className="flex items-center gap-4 p-4 bg-muted rounded-lg">
                <div className="w-12 h-12 bg-primary rounded-full flex items-center justify-center">
                  <span className="text-primary-foreground font-bold text-lg">P</span>
                </div>
                <div>
                  <p className="font-semibold">PiuPhoto</p>
                  <p className="text-sm text-muted-foreground">Your Event Platform</p>
                </div>
              </div>
              {viewEvent?.description && (
                <div>
                  <h3 className="font-semibold mb-2">Description</h3>
                  <p className="text-muted-foreground">{viewEvent.description}</p>
                </div>
              )}
              <div className="flex gap-2">
                <Badge variant={viewEvent?.isActive ? "default" : "secondary"}>
                  {viewEvent?.isActive ? "Active" : "Inactive"}
                </Badge>
                <Badge variant={viewEvent?.isPublished ? "outline" : "destructive"}>
                  {viewEvent?.isPublished ? "Published" : "Draft"}
                </Badge>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setViewEvent(null)}>Close</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </UserLayout>
  );
}
