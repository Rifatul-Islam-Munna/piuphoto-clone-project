import { ChangeEvent, useEffect, useMemo, useRef, useState } from "react";
import { Camera, Image as ImageIcon, Loader2, Search, Upload } from "lucide-react";
import { toast } from "sonner";
import UserLayout from "./UserLayout";
import { GetRequestAxios, PostRequestAxios } from "@/api-hooks/api-hooks";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

type FaceBox = {
  x: number;
  y: number;
  width: number;
  height: number;
  confidence?: number;
};

type MatchImage = {
  _id?: string;
  id?: string;
  imageUrl?: string;
  faceMatch?: { score?: number; faceCount?: number };
  eventId?: { title?: string } | string;
};

type MyPictureResponse = {
  data?: MatchImage[];
  totalItems?: number;
  faces?: FaceBox[];
  message?: string;
};

type EventOption = {
  _id?: string;
  id?: string;
  title?: string;
};

type EventsResponse = {
  data?: EventOption[];
};

const imageAccept = "image/jpeg,image/png,image/webp";

export default function UserMyPictures() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string>("");
  const [naturalSize, setNaturalSize] = useState({ width: 1, height: 1 });
  const [faces, setFaces] = useState<FaceBox[]>([]);
  const [matches, setMatches] = useState<MatchImage[]>([]);
  const [events, setEvents] = useState<EventOption[]>([]);
  const [selectedEventId, setSelectedEventId] = useState("");
  const [loading, setLoading] = useState(false);

  const hasImage = Boolean(file && previewUrl);
  const totalMatches = useMemo(() => matches.length, [matches]);

  useEffect(() => {
    let mounted = true;

    const loadEvents = async () => {
      const [response] = await GetRequestAxios<EventsResponse>(
        "/event/my-events?page=1&limit=100",
        { withToken: true },
      );
      if (!mounted) return;

      const nextEvents = response?.data || [];
      setEvents(nextEvents);
      const firstId = nextEvents[0]?._id || nextEvents[0]?.id || "";
      if (firstId) setSelectedEventId((current) => current || firstId);
    };

    loadEvents();

    return () => {
      mounted = false;
    };
  }, []);

  const pickFile = (event: ChangeEvent<HTMLInputElement>) => {
    const nextFile = event.target.files?.[0];
    event.target.value = "";
    if (!nextFile) return;

    if (!["image/jpeg", "image/png", "image/webp"].includes(nextFile.type)) {
      toast.error("Use JPG, PNG, or WEBP");
      return;
    }

    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setFile(nextFile);
    setPreviewUrl(URL.createObjectURL(nextFile));
    setFaces([]);
    setMatches([]);
  };

  const searchMyPictures = async () => {
    if (!file) {
      toast.error("Select or take a photo first");
      return;
    }
    if (!selectedEventId) {
      toast.error("Select an event first");
      return;
    }

    setLoading(true);
    const formData = new FormData();
    formData.append("image", file);

    const [response, error] = await PostRequestAxios<MyPictureResponse>(
      `/eventImage/my-picture?eventId=${selectedEventId}&limit=10000`,
      formData,
      {
        withToken: true,
        headers: { "Content-Type": "multipart/form-data" },
      },
    );

    setLoading(false);

    if (error) {
      setFaces([]);
      setMatches([]);
      toast.error(error.message || "Face search failed");
      return;
    }

    setFaces(response?.faces || []);
    setMatches(response?.data || []);
    if (response?.message) {
      toast.error(response.message);
    } else {
      toast.success(`${response?.totalItems || 0} matching images found`);
    }
  };

  const boxStyle = (face: FaceBox) => {
    const percentInput =
      face.x <= 1 && face.y <= 1 && face.width <= 1 && face.height <= 1;
    const left = percentInput ? face.x * 100 : (face.x / naturalSize.width) * 100;
    const top = percentInput ? face.y * 100 : (face.y / naturalSize.height) * 100;
    const width = percentInput
      ? face.width * 100
      : (face.width / naturalSize.width) * 100;
    const height = percentInput
      ? face.height * 100
      : (face.height / naturalSize.height) * 100;

    return {
      left: `${left}%`,
      top: `${top}%`,
      width: `${width}%`,
      height: `${height}%`,
    };
  };

  return (
    <UserLayout>
      <div className="space-y-6">
        <section className="flex flex-col gap-4 border-b pb-5 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <Badge variant="outline" className="mb-2">
              <Search className="mr-1 h-3.5 w-3.5" />
              Face Search
            </Badge>
            <h1 className="text-2xl font-bold">My Pictures</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Take or upload one face photo to find matching event images.
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Select value={selectedEventId} onValueChange={setSelectedEventId}>
              <SelectTrigger className="w-52">
                <SelectValue placeholder="Select event" />
              </SelectTrigger>
              <SelectContent>
                {events.filter((event) => event._id || event.id).map((event) => {
                  const id = event._id || event.id || "";
                  return (
                    <SelectItem key={id} value={id}>
                      {event.title || "Untitled event"}
                    </SelectItem>
                  );
                })}
              </SelectContent>
            </Select>
            <Button
              variant="outline"
              onClick={() => cameraInputRef.current?.click()}
              disabled={loading}
            >
              <Camera className="mr-2 h-4 w-4" />
              Take Photo
            </Button>
            <Button
              variant="outline"
              onClick={() => fileInputRef.current?.click()}
              disabled={loading}
            >
              <Upload className="mr-2 h-4 w-4" />
              Upload
            </Button>
            <Button onClick={searchMyPictures} disabled={!hasImage || !selectedEventId || loading}>
              {loading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Search className="mr-2 h-4 w-4" />
              )}
              Find Matches
            </Button>
          </div>
          <Input
            ref={fileInputRef}
            type="file"
            accept={imageAccept}
            className="hidden"
            onChange={pickFile}
          />
          <Input
            ref={cameraInputRef}
            type="file"
            accept={imageAccept}
            capture="user"
            className="hidden"
            onChange={pickFile}
          />
        </section>

        <section className="grid gap-5 lg:grid-cols-[minmax(280px,420px)_1fr]">
          <Card>
            <CardContent className="p-4">
              {previewUrl ? (
                <div className="relative overflow-hidden rounded-md bg-muted">
                  <img
                    src={previewUrl}
                    alt="Selected face"
                    className="w-full object-contain"
                    onLoad={(event) =>
                      setNaturalSize({
                        width: event.currentTarget.naturalWidth || 1,
                        height: event.currentTarget.naturalHeight || 1,
                      })
                    }
                  />
                  {faces.map((face, index) => (
                    <div
                      key={`${face.x}-${face.y}-${index}`}
                      className="absolute border-2 border-emerald-400 bg-emerald-400/10 shadow-[0_0_0_1px_rgba(0,0,0,0.35)]"
                      style={boxStyle(face)}
                    >
                      {face.confidence !== undefined && (
                        <span className="absolute -top-6 left-0 rounded bg-emerald-500 px-1.5 py-0.5 text-xs font-medium text-white">
                          {Math.round(face.confidence * 100)}%
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  className="flex aspect-[4/3] w-full flex-col items-center justify-center rounded-md border border-dashed text-muted-foreground"
                >
                  <ImageIcon className="mb-3 h-10 w-10" />
                  JPG, PNG, WEBP
                </button>
              )}
            </CardContent>
          </Card>

          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">Matches</h2>
              <Badge variant="secondary">{totalMatches} images</Badge>
            </div>
            {loading ? (
              <div className="flex min-h-72 items-center justify-center rounded-lg border">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : matches.length ? (
              <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                {matches.map((image, index) => (
                  <Card key={image._id || image.id || image.imageUrl || index} className="overflow-hidden">
                    <div className="aspect-[4/3] bg-muted">
                      <img
                        src={image.imageUrl}
                        alt={`Match ${index + 1}`}
                        className="h-full w-full object-cover"
                        loading="lazy"
                      />
                    </div>
                    <CardContent className="flex items-center justify-between gap-2 p-3">
                      <span className="truncate text-sm font-medium">
                        {typeof image.eventId === "object"
                          ? image.eventId?.title || "Event image"
                          : "Event image"}
                      </span>
                      {image.faceMatch?.score !== undefined && (
                        <Badge variant="outline">
                          {Math.round(image.faceMatch.score * 100)}%
                        </Badge>
                      )}
                    </CardContent>
                  </Card>
                ))}
              </div>
            ) : (
              <div className="flex min-h-72 items-center justify-center rounded-lg border border-dashed text-sm text-muted-foreground">
                Matching event images appear here.
              </div>
            )}
          </div>
        </section>
      </div>
    </UserLayout>
  );
}
