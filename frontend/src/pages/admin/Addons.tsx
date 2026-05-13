import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Loader2, Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
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
import AdminLayout from "./AdminLayout";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { useCommonMutationApi } from "@/api-hooks/use-api-mutation";

type Addon = {
  _id: string;
  title: string;
  description?: string;
  credit: number;
  price: number;
  currency: string;
  order: number;
  isActive: boolean;
};

type AddonsResponse = {
  data: Addon[];
};

type AddonFormData = {
  title: string;
  description: string;
  credit: number;
  price: number;
  currency: string;
  order: number;
  isActive: boolean;
};

const defaultFormData: AddonFormData = {
  title: "",
  description: "",
  credit: 0,
  price: 0,
  currency: "USD",
  order: 0,
  isActive: true,
};

const currencyOptions = ["USD", "BDT", "EUR", "GBP"];

export default function Addons() {
  const queryClient = useQueryClient();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingAddon, setEditingAddon] = useState<Addon | null>(null);
  const [formData, setFormData] = useState<AddonFormData>(defaultFormData);

  const addonsQuery = useQueryWrapper<AddonsResponse>(
    ["addons"],
    "/addon/get-all?limit=100&isActive=all",
    { withToken: true, withCredentials: true },
  );

  const refreshAddons = async () => {
    await queryClient.invalidateQueries({ queryKey: ["addons"] });
  };

  const createAddonMutation = useCommonMutationApi<
    { message: string; data: Addon },
    AddonFormData
  >({
    url: "/addon",
    method: "POST",
    successMessage: "Addon created",
    withToken: true,
    withCredentials: true,
    onSuccess: async () => {
      setDialogOpen(false);
      setEditingAddon(null);
      setFormData(defaultFormData);
      await refreshAddons();
    },
  });

  const updateAddonMutation = useCommonMutationApi<
    { message: string; data: Addon },
    AddonFormData
  >({
    url: editingAddon ? `/addon/update?id=${editingAddon._id}` : "/addon/update",
    method: "PATCH",
    successMessage: "Addon updated",
    withToken: true,
    withCredentials: true,
    onSuccess: async () => {
      setDialogOpen(false);
      setEditingAddon(null);
      setFormData(defaultFormData);
      await refreshAddons();
    },
  });

  const deleteAddonMutation = useCommonMutationApi<
    { message: string; data: Addon },
    string
  >({
    url: "/addon/delete",
    method: "DELETE",
    successMessage: "Addon deleted",
    withToken: true,
    withCredentials: true,
    onSuccess: async () => {
      await refreshAddons();
    },
  });

  const handleOpenDialog = (addon?: Addon) => {
    if (addon) {
      setEditingAddon(addon);
      setFormData({
        title: addon.title,
        description: addon.description || "",
        credit: addon.credit,
        price: addon.price,
        currency: addon.currency,
        order: addon.order,
        isActive: addon.isActive,
      });
    } else {
      setEditingAddon(null);
      setFormData(defaultFormData);
    }

    setDialogOpen(true);
  };

  const handleSubmit = () => {
    if (!formData.title.trim()) {
      return;
    }

    if (editingAddon) {
      updateAddonMutation.mutate(formData);
      return;
    }

    createAddonMutation.mutate(formData);
  };

  const handleDelete = (id: string) => {
    if (!confirm("Are you sure you want to delete this addon?")) {
      return;
    }

    deleteAddonMutation.mutate(id);
  };

  const addons = addonsQuery.data?.data || [];
  const loading = addonsQuery.isLoading;
  const submitting =
    createAddonMutation.isPending ||
    updateAddonMutation.isPending ||
    deleteAddonMutation.isPending;

  return (
    <AdminLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Addons</h1>
            <p className="text-muted-foreground">
              Create credit packs users can buy.
            </p>
          </div>
          <Button onClick={() => handleOpenDialog()}>
            <Plus className="mr-2 h-4 w-4" />
            Create Addon
          </Button>
        </div>

        {loading ? (
          <div className="flex h-64 items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
            {addons.map((addon) => (
              <Card key={addon._id}>
                <CardHeader>
                  <CardTitle className="flex items-center justify-between">
                    {addon.title}
                    {!addon.isActive && <Badge variant="secondary">Inactive</Badge>}
                  </CardTitle>
                  <CardDescription>{addon.description || "No description"}</CardDescription>
                </CardHeader>
                <CardContent className="space-y-3">
                  <div className="flex items-end justify-between">
                    <div>
                      <p className="text-xs uppercase text-muted-foreground">Credits</p>
                      <p className="text-2xl font-bold">{addon.credit}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-xs uppercase text-muted-foreground">Price</p>
                      <p className="text-2xl font-bold">
                        {addon.currency} {addon.price}
                      </p>
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground">Order: {addon.order}</p>
                </CardContent>
                <CardFooter className="gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    className="flex-1"
                    onClick={() => handleOpenDialog(addon)}
                  >
                    <Pencil className="mr-2 h-4 w-4" />
                    Edit
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleDelete(addon._id)}
                  >
                    <Trash2 className="h-4 w-4 text-red-500" />
                  </Button>
                </CardFooter>
              </Card>
            ))}
          </div>
        )}

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>{editingAddon ? "Edit Addon" : "Create Addon"}</DialogTitle>
              <DialogDescription>
                Add title, description, credit, price, currency.
              </DialogDescription>
            </DialogHeader>

            <div className="grid gap-6 py-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="title">Title</Label>
                  <Input
                    id="title"
                    value={formData.title}
                    onChange={(event) =>
                      setFormData({ ...formData, title: event.target.value })
                    }
                    placeholder="Extra Credit Pack"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="order">Order</Label>
                  <Input
                    id="order"
                    type="number"
                    value={formData.order}
                    onChange={(event) =>
                      setFormData({
                        ...formData,
                        order: parseInt(event.target.value, 10) || 0,
                      })
                    }
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="description">Description</Label>
                <Textarea
                  id="description"
                  value={formData.description}
                  onChange={(event) =>
                    setFormData({ ...formData, description: event.target.value })
                  }
                  placeholder="Short addon description"
                />
              </div>

              <div className="grid gap-4 md:grid-cols-3">
                <div className="space-y-2">
                  <Label htmlFor="credit">Credit</Label>
                  <Input
                    id="credit"
                    type="number"
                    value={formData.credit}
                    onChange={(event) =>
                      setFormData({
                        ...formData,
                        credit: parseInt(event.target.value, 10) || 0,
                      })
                    }
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="price">Price</Label>
                  <Input
                    id="price"
                    type="number"
                    value={formData.price}
                    onChange={(event) =>
                      setFormData({
                        ...formData,
                        price: parseFloat(event.target.value) || 0,
                      })
                    }
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="currency">Currency</Label>
                  <Select
                    value={formData.currency}
                    onValueChange={(value) =>
                      setFormData({ ...formData, currency: value })
                    }
                  >
                    <SelectTrigger id="currency">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {currencyOptions.map((currency) => (
                        <SelectItem key={currency} value={currency}>
                          {currency}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="flex items-center gap-2">
                <Switch
                  checked={formData.isActive}
                  onCheckedChange={(checked) =>
                    setFormData({ ...formData, isActive: checked })
                  }
                />
                <Label>Active</Label>
              </div>
            </div>

            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button
                onClick={handleSubmit}
                disabled={
                  submitting ||
                  !formData.title.trim() ||
                  formData.credit < 1 ||
                  formData.price < 0
                }
              >
                {submitting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                {editingAddon ? "Update" : "Create"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </AdminLayout>
  );
}

