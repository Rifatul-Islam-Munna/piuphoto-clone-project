import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2, Check, Star, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import AdminLayout from "./AdminLayout";
import { featureMapping, limitMapping, getFeatureDescription, getLimitDescription } from "@/lib/constants/features";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { useCommonMutationApi } from "@/api-hooks/use-api-mutation";

type SubscriptionPlan = {
  _id: string;
  title: string;
  description?: string;
  price: number;
  discount_price?: number;
  features: string[];
  permissions: Record<string, unknown>[];
  order: number;
  isPopular: boolean;
  currency: string;
  billingUnit: "PER_MONTH" | "PER_YEAR";
  isActive: boolean;
};

type SubscriptionPlanResponse = {
  data: SubscriptionPlan[];
  page: number;
  limit: number;
  totalItems: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
};

type PlanFormData = {
  title: string;
  description: string;
  price: number;
  discount_price: number;
  features: string[];
  limits: Record<string, number>;
  order: number;
  isPopular: boolean;
  currency: string;
  billingUnit: "PER_MONTH" | "PER_YEAR";
  isActive: boolean;
};

type PlanPayload = Omit<PlanFormData, "limits"> & {
  permissions: { key: string; value: number }[];
};

const defaultFormData: PlanFormData = {
  title: "",
  description: "",
  price: 0,
  discount_price: 0,
  features: [],
  limits: {},
  order: 0,
  isPopular: false,
  currency: "USD",
  billingUnit: "PER_MONTH",
  isActive: true,
};

export default function Plans() {
  const queryClient = useQueryClient();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingPlan, setEditingPlan] = useState<SubscriptionPlan | null>(null);
  const [formData, setFormData] = useState<PlanFormData>(defaultFormData);
  const [page, setPage] = useState(1);

  const plansQuery = useQueryWrapper<SubscriptionPlanResponse>(
    ["subscription-plans", page],
    `/subscription-plan/get-all?page=${page}&limit=6&isActive=all`,
    {
      withToken: true,
      withCredentials: true,
    },
  );

  const refreshPlans = async () => {
    await queryClient.invalidateQueries({ queryKey: ["subscription-plans"] });
  };

  const createPlanMutation = useCommonMutationApi<
    { message: string; data: SubscriptionPlan },
    PlanPayload
  >({
    url: "/subscription-plan",
    method: "POST",
    successMessage: "Plan created",
    withToken: true,
    withCredentials: true,
    onSuccess: async () => {
      setDialogOpen(false);
      setEditingPlan(null);
      setFormData(defaultFormData);
      await refreshPlans();
    },
  });

  const updatePlanMutation = useCommonMutationApi<
    { message: string; data: SubscriptionPlan },
    PlanPayload
  >({
    url: editingPlan ? `/subscription-plan/update?id=${editingPlan._id}` : "/subscription-plan/update",
    method: "PATCH",
    successMessage: "Plan updated",
    withToken: true,
    withCredentials: true,
    onSuccess: async () => {
      setDialogOpen(false);
      setEditingPlan(null);
      setFormData(defaultFormData);
      await refreshPlans();
    },
  });

  const deletePlanMutation = useCommonMutationApi<
    { message: string; data: SubscriptionPlan },
    string
  >({
    url: "/subscription-plan/delete",
    method: "DELETE",
    successMessage: "Plan deleted",
    withToken: true,
    withCredentials: true,
    onSuccess: async () => {
      await refreshPlans();
    },
  });

  const extractLimitsFromPermissions = (permissions: Record<string, unknown>[] = []) => {
    const parsedLimits: Record<string, number> = {};

    permissions.forEach((permission) => {
      if (permission.key && permission.value !== undefined && permission.value !== null) {
        const numericValue = Number(permission.value);

        if (!Number.isNaN(numericValue)) {
          parsedLimits[String(permission.key)] = numericValue;
        }

        return;
      }

      Object.entries(permission).forEach(([key, value]) => {
        if (key === "_id" || key === "id") {
          return;
        }

        const numericValue = Number(value);

        if (!Number.isNaN(numericValue)) {
          parsedLimits[key] = numericValue;
        }
      });
    });

    return parsedLimits;
  };

  const handleOpenDialog = (plan?: SubscriptionPlan) => {
    if (plan) {
      setEditingPlan(plan);
      const limits = extractLimitsFromPermissions(plan.permissions || []);

      setFormData({
        title: plan.title,
        description: plan.description || "",
        price: plan.price,
        discount_price: plan.discount_price || 0,
        features: plan.features || [],
        limits,
        order: plan.order,
        isPopular: plan.isPopular,
        currency: plan.currency,
        billingUnit: plan.billingUnit,
        isActive: plan.isActive,
      });
    } else {
      setEditingPlan(null);
      setFormData(defaultFormData);
    }

    setDialogOpen(true);
  };

  const handleFeatureToggle = (feature: string) => {
    setFormData((prev) => ({
      ...prev,
      features: prev.features.includes(feature)
        ? prev.features.filter((item) => item !== feature)
        : [...prev.features, feature],
    }));
  };

  const handleLimitChange = (key: string, value: string) => {
    setFormData((prev) => ({
      ...prev,
      limits: {
        ...prev.limits,
        [key]: value ? parseInt(value, 10) : 0,
      },
    }));
  };

  const handleSubmit = () => {
    const {
      title,
      description,
      price,
      discount_price,
      features,
      limits,
      order,
      isPopular,
      currency,
      billingUnit,
      isActive,
    } = formData;

    const payload: PlanPayload = {
      title,
      description,
      price,
      discount_price,
      features,
      order,
      isPopular,
      currency,
      billingUnit,
      isActive,
      permissions: Object.entries(limits)
        .filter(([, value]) => value > 0)
        .map(([key, value]) => ({ key, value })),
    };

    if (editingPlan) {
      updatePlanMutation.mutate(payload);
      return;
    }

    createPlanMutation.mutate(payload);
  };

  const handleDelete = (id: string) => {
    if (!confirm("Are you sure you want to delete this plan?")) return;
    deletePlanMutation.mutate(id);
  };

  const plans = plansQuery.data?.data || [];
  const featureKeys = Object.keys(featureMapping);
  const limitKeys = Array.from(
    new Set([...Object.keys(limitMapping), ...Object.keys(formData.limits)]),
  );
  const loading = plansQuery.isLoading;
  const submitting =
    createPlanMutation.isPending ||
    updatePlanMutation.isPending ||
    deletePlanMutation.isPending;

  return (
    <AdminLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Subscription Plans</h1>
            <p className="text-muted-foreground">Manage your subscription plans and pricing.</p>
          </div>
          <Button onClick={() => handleOpenDialog()}>
            <Plus className="mr-2 h-4 w-4" />
            Create Plan
          </Button>
        </div>

        {loading ? (
          <div className="flex h-64 items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
            {plans.map((plan) => (
              <Card key={plan._id} className={plan.isPopular ? "border-primary" : ""}>
                <CardHeader className="relative">
                  {plan.isPopular && (
                    <Badge className="absolute -top-3 right-4" variant="default">
                      <Star className="mr-1 h-3 w-3" />
                      Popular
                    </Badge>
                  )}
                  <CardTitle className="flex items-center justify-between">
                    {plan.title}
                    {!plan.isActive && <Badge variant="secondary">Inactive</Badge>}
                  </CardTitle>
                  <CardDescription>{plan.description}</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="mb-4 flex items-baseline gap-2">
                    <span className="text-3xl font-bold">
                      {plan.currency} {plan.discount_price || plan.price}
                    </span>
                    {plan.discount_price && (
                      <span className="text-sm text-muted-foreground line-through">
                        {plan.currency} {plan.price}
                      </span>
                    )}
                    <span className="text-sm text-muted-foreground">
                      /{plan.billingUnit === "PER_MONTH" ? "mo" : "yr"}
                    </span>
                  </div>
                  <div className="space-y-2">
                    <p className="text-sm font-medium">Features</p>
                    <ul className="space-y-1 text-sm text-muted-foreground">
                      {plan.features?.slice(0, 3).map((feature, index) => (
                        <li key={index} className="flex items-center gap-2">
                          <Check className="h-4 w-4 text-green-500" />
                          {getFeatureDescription(feature)}
                        </li>
                      ))}
                      {(plan.features?.length || 0) > 3 && (
                        <li className="text-xs">+{plan.features.length - 3} more</li>
                      )}
                    </ul>
                  </div>
                </CardContent>
                <CardFooter className="gap-2">
                  <Button variant="outline" size="sm" className="flex-1" onClick={() => handleOpenDialog(plan)}>
                    <Pencil className="mr-2 h-4 w-4" />
                    Edit
                  </Button>
                  <Button variant="outline" size="sm" onClick={() => handleDelete(plan._id)}>
                    <Trash2 className="h-4 w-4 text-red-500" />
                  </Button>
                </CardFooter>
              </Card>
            ))}
          </div>
        )}

        {plansQuery.data && plansQuery.data.totalPages > 1 ? (
          <div className="flex items-center justify-end gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setPage((value) => Math.max(1, value - 1))}
              disabled={!plansQuery.data.hasPreviousPage}
            >
              Previous
            </Button>
            <span className="text-sm text-muted-foreground">
              Page {plansQuery.data.page} of {plansQuery.data.totalPages}
            </span>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setPage((value) => value + 1)}
              disabled={!plansQuery.data.hasNextPage}
            >
              Next
            </Button>
          </div>
        ) : null}

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent className="max-h-[90vh] overflow-y-auto max-w-3xl">
            <DialogHeader>
              <DialogTitle>{editingPlan ? "Edit Plan" : "Create Plan"}</DialogTitle>
              <DialogDescription>Configure plan details, features, and limits.</DialogDescription>
            </DialogHeader>
            <div className="grid gap-6 py-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="title">Plan Name</Label>
                  <Input
                    id="title"
                    value={formData.title}
                    onChange={(event) => setFormData({ ...formData, title: event.target.value })}
                    placeholder="Premium Plan"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="order">Display Order</Label>
                  <Input
                    id="order"
                    type="number"
                    value={formData.order}
                    onChange={(event) =>
                      setFormData({ ...formData, order: parseInt(event.target.value, 10) || 0 })
                    }
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="description">Description</Label>
                <Textarea
                  id="description"
                  value={formData.description}
                  onChange={(event) => setFormData({ ...formData, description: event.target.value })}
                  placeholder="Plan description..."
                />
              </div>

              <div className="grid gap-4 md:grid-cols-4">
                <div className="space-y-2">
                  <Label htmlFor="price">Price</Label>
                  <Input
                    id="price"
                    type="number"
                    value={formData.price}
                    onChange={(event) =>
                      setFormData({ ...formData, price: parseInt(event.target.value, 10) || 0 })
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="discount_price">Discount Price</Label>
                  <Input
                    id="discount_price"
                    type="number"
                    value={formData.discount_price}
                    onChange={(event) =>
                      setFormData({ ...formData, discount_price: parseInt(event.target.value, 10) || 0 })
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="currency">Currency</Label>
                  <Select
                    value={formData.currency}
                    onValueChange={(value) => setFormData({ ...formData, currency: value })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="USD">USD</SelectItem>
                      <SelectItem value="BDT">BDT</SelectItem>
                      <SelectItem value="EUR">EUR</SelectItem>
                      <SelectItem value="GBP">GBP</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="billingUnit">Billing</Label>
                  <Select
                    value={formData.billingUnit}
                    onValueChange={(value: "PER_MONTH" | "PER_YEAR") =>
                      setFormData({ ...formData, billingUnit: value })
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="PER_MONTH">Monthly</SelectItem>
                      <SelectItem value="PER_YEAR">Yearly</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="flex items-center gap-4">
                <div className="flex items-center gap-2">
                  <Switch
                    checked={formData.isPopular}
                    onCheckedChange={(checked) => setFormData({ ...formData, isPopular: checked })}
                  />
                  <Label>Popular Plan</Label>
                </div>
                <div className="flex items-center gap-2">
                  <Switch
                    checked={formData.isActive}
                    onCheckedChange={(checked) => setFormData({ ...formData, isActive: checked })}
                  />
                  <Label>Active</Label>
                </div>
              </div>

              <div className="space-y-3">
                <Label>Features</Label>
                <div className="grid gap-2 md:grid-cols-2">
                  {featureKeys.map((key) => (
                    <div key={key} className="flex items-center gap-2">
                      <Checkbox
                        id={`feature-${key}`}
                        checked={formData.features.includes(key)}
                        onCheckedChange={() => handleFeatureToggle(key)}
                      />
                      <Label htmlFor={`feature-${key}`} className="font-normal">
                        {featureMapping[key as keyof typeof featureMapping]}
                      </Label>
                    </div>
                  ))}
                </div>
              </div>

              <div className="space-y-3">
                <Label>Limits</Label>
                <div className="grid gap-4 md:grid-cols-2">
                  {limitKeys.map((key) => (
                    <div key={key} className="flex items-center gap-2">
                      <Label htmlFor={`limit-${key}`} className="w-40 font-normal">
                        {getLimitDescription(key)}
                      </Label>
                      <Input
                        id={`limit-${key}`}
                        type="number"
                        placeholder="0"
                        className="h-8"
                        value={formData.limits[key] || ""}
                        onChange={(event) => handleLimitChange(key, event.target.value)}
                      />
                    </div>
                  ))}
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button onClick={handleSubmit} disabled={submitting}>
                {submitting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                {editingPlan ? "Update" : "Create"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </AdminLayout>
  );
}

