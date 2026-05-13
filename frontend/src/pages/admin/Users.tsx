import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2, Loader2, Search, MoreHorizontal, UserCog, CreditCard } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
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
import AdminLayout from "./AdminLayout";
import {
  PatchRequestAxios,
  DeleteRequestAxios,
  GetRequestNormal,
  PostRequestAxios,
} from "@/api-hooks/api-hooks";

type UserType = "admin" | "editor" | "user" | "photographer";

type SubscriptionPlan = {
  _id: string;
  title: string;
  price: number;
};

type User = {
  _id: string;
  name: string;
  email?: string;
  phone?: string;
  role: UserType;
  gender?: string;
  age?: number;
  isActive: boolean;
  createdAt: string;
  isSubscriber?: boolean;
  subscriptionPlanId?: SubscriptionPlan | null;
  subscriptionEndDate?: string;
  credits?: number;
};

type UsersResponse = {
  data: User[];
  page: number;
  limit: number;
  totalItems: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
};

type UserFormData = {
  name: string;
  email: string;
  phone: string;
  password: string;
  role: UserType;
  gender: string;
  age: number;
  isActive: boolean;
};

const defaultFormData: UserFormData = {
  name: "",
  email: "",
  phone: "",
  password: "",
  role: "user",
  gender: "",
  age: 0,
  isActive: true,
};

const roleLabels: Record<UserType, string> = {
  admin: "Admin",
  editor: "Editor",
  user: "User",
  photographer: "Photographer",
};

const roleColors: Record<UserType, string> = {
  admin: "bg-red-100 text-red-800",
  editor: "bg-blue-100 text-blue-800",
  user: "bg-green-100 text-green-800",
  photographer: "bg-purple-100 text-purple-800",
};

export default function Users() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [genderFilter, setGenderFilter] = useState("all");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<User | null>(null);
  const [formData, setFormData] = useState<UserFormData>(defaultFormData);
  const [planDialogOpen, setPlanDialogOpen] = useState(false);
  const [selectedUserForPlan, setSelectedUserForPlan] = useState<User | null>(null);
  const [selectedPlanId, setSelectedPlanId] = useState<string>("");

  const { data: usersData, isLoading } = useQuery({
    queryKey: ["users", page, search, genderFilter],
    queryFn: async () => {
      const params = new URLSearchParams();
      params.append("page", page.toString());
      params.append("limit", "10");
      if (search) params.append("query", search);
      if (genderFilter !== "all") params.append("gender", genderFilter);
      return GetRequestNormal<UsersResponse>(
        `/user/get-all-admin?${params.toString()}`,
        0,
        "users",
        { withToken: true, withCredentials: true },
      );
    },
  });

  const { data: plansData, isLoading: plansLoading } = useQuery({
    queryKey: ["plans"],
    queryFn: async () =>
      GetRequestNormal<{ data: SubscriptionPlan[] }>(
        "/subscription-plan/get-all?limit=100&isActive=all",
        0,
        "plans",
        { withToken: true, withCredentials: true },
      ),
  });

  const plans = plansData?.data || [];

  const assignPlan = async ({ userId, planId }: { userId: string; planId: string }) => {
    const [response, error] = await PatchRequestAxios<User>(
      `/user/assign-plan`,
      { userId, planId },
      { withToken: true, withCredentials: true },
    );
    if (error || !response) throw new Error(error?.message || "Failed to assign plan");
    return response;
  };

  const assignPlanMutation = useMutation({
    mutationFn: assignPlan,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      toast.success("Plan assigned successfully");
      setPlanDialogOpen(false);
      setSelectedUserForPlan(null);
      setSelectedPlanId("");
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to assign plan");
    },
  });

  const createUser = async (data: UserFormData) => {
    const [response, error] = await PostRequestAxios<User>("/user", data, {
      withToken: true,
      withCredentials: true,
    });
    if (error || !response) throw new Error(error?.message || "Failed to create user");
    return response;
  };

  const updateUser = async ({ id, data }: { id: string; data: Partial<UserFormData> }) => {
    const [response, error] = await PatchRequestAxios<User>(
      `/user/update-user-admin?id=${id}`,
      data,
      { withToken: true, withCredentials: true },
    );
    if (error || !response) throw new Error(error?.message || "Failed to update user");
    return response;
  };

  const deleteUser = async (id: string) => {
    const [response, error] = await DeleteRequestAxios<User>(
      `/user/delete-user-admin?id=${id}`,
      { withToken: true, withCredentials: true },
    );
    if (error || !response) throw new Error(error?.message || "Failed to delete user");
    return response;
  };

  const toggleUserActive = async (id: string) => {
    const [response, error] = await PatchRequestAxios<User>(
      `/user/toggle-active?id=${id}`,
      {},
      { withToken: true, withCredentials: true },
    );
    if (error || !response) throw new Error(error?.message || "Failed to update status");
    return response;
  };

  const changeUserRole = async ({ id, role }: { id: string; role: UserType }) => {
    const [response, error] = await PatchRequestAxios<User>(
      `/user/change-role`,
      { userId: id, role },
      { withToken: true, withCredentials: true },
    );
    if (error || !response) throw new Error(error?.message || "Failed to update role");
    return response;
  };

  const createMutation = useMutation({
    mutationFn: createUser,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      toast.success("User created successfully");
      setDialogOpen(false);
      setFormData(defaultFormData);
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to create user");
    },
  });

  const updateMutation = useMutation({
    mutationFn: updateUser,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      toast.success("User updated successfully");
      setDialogOpen(false);
      setEditingUser(null);
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to update user");
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteUser,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      toast.success("User deleted successfully");
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to delete user");
    },
  });

  const toggleActiveMutation = useMutation({
    mutationFn: toggleUserActive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      toast.success("User status updated");
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to update status");
    },
  });

  const changeRoleMutation = useMutation({
    mutationFn: changeUserRole,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      toast.success("Role updated successfully");
    },
    onError: (error: any) => {
      toast.error(error?.message || "Failed to update role");
    },
  });

  const handleOpenDialog = (user?: User) => {
    if (user) {
      setEditingUser(user);
      setFormData({
        name: user.name,
        email: user.email || "",
        phone: user.phone || "",
        password: "",
        role: user.role,
        gender: user.gender || "",
        age: user.age || 0,
        isActive: user.isActive,
      });
    } else {
      setEditingUser(null);
      setFormData(defaultFormData);
    }
    setDialogOpen(true);
  };

  const handleSubmit = () => {
    if (editingUser) {
      updateMutation.mutate({ id: editingUser._id, data: formData });
    } else {
      createMutation.mutate(formData);
    }
  };

  const handleDelete = (id: string) => {
    if (!confirm("Are you sure you want to delete this user?")) return;
    deleteMutation.mutate(id);
  };

  const handleOpenPlanDialog = (user: User) => {
    setSelectedUserForPlan(user);
    setSelectedPlanId(user.subscriptionPlanId?._id || "");
    setPlanDialogOpen(true);
  };

  const handleAssignPlan = () => {
    if (!selectedUserForPlan || !selectedPlanId) return;
    assignPlanMutation.mutate({ userId: selectedUserForPlan._id, planId: selectedPlanId });
  };

  return (
    <AdminLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Users</h1>
            <p className="text-muted-foreground">Manage users and their roles.</p>
          </div>
          <Button onClick={() => handleOpenDialog()}>
            <Plus className="mr-2 h-4 w-4" />
            Add User
          </Button>
        </div>

        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-1 items-center gap-2">
            <div className="relative flex-1 max-w-sm">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                placeholder="Search users..."
                className="pl-9"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <Select value={genderFilter} onValueChange={setGenderFilter}>
              <SelectTrigger className="w-32">
                <SelectValue placeholder="Gender" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All</SelectItem>
                <SelectItem value="male">Male</SelectItem>
                <SelectItem value="female">Female</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        {isLoading ? (
          <div className="flex h-64 items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <>
            <div className="rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead>Email</TableHead>
                    <TableHead>Role</TableHead>
                    <TableHead>Gender</TableHead>
                    <TableHead>Age</TableHead>
                    <TableHead>Plan</TableHead>
                    <TableHead>Credits</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {usersData?.data?.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={9} className="h-24 text-center">
                        No users found.
                      </TableCell>
                    </TableRow>
                  ) : (
                    usersData?.data?.map((user) => (
                      <TableRow key={user._id}>
                        <TableCell className="font-medium">{user.name}</TableCell>
                        <TableCell>{user.email || "-"}</TableCell>
                        <TableCell>
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Badge className={`cursor-pointer ${roleColors[user.role as UserType]}`}>
                                {roleLabels[user.role as UserType]}
                              </Badge>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent>
                              {Object.entries(roleLabels).map(([value, label]) => (
                                <DropdownMenuItem
                                  key={value}
                                  onClick={() => changeRoleMutation.mutate({ id: user._id, role: value as UserType })}
                                  disabled={user.role === value}
                                >
                                  {label}
                                </DropdownMenuItem>
                              ))}
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </TableCell>
                        <TableCell>{user.gender || "-"}</TableCell>
                        <TableCell>{user.age || "-"}</TableCell>
                        <TableCell>
                          {user.isSubscriber && user.subscriptionPlanId ? (
                            <Badge variant="outline" className="bg-green-50">
                              {user.subscriptionPlanId.title}
                            </Badge>
                          ) : (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-7 text-xs text-muted-foreground hover:text-primary"
                              onClick={() => handleOpenPlanDialog(user)}
                            >
                              <CreditCard className="mr-1.5 h-3.5 w-3.5" />
                              Assign Plan
                            </Button>
                          )}
                        </TableCell>
                        <TableCell>{user.credits || 0}</TableCell>
                        <TableCell>
                          <Badge variant={user.isActive ? "default" : "secondary"}>
                            {user.isActive ? "Active" : "Inactive"}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button variant="ghost" size="sm" className="h-8 w-8 p-0">
                                <MoreHorizontal className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => handleOpenDialog(user)}>
                                <Pencil className="mr-2 h-4 w-4" />
                                Edit
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => toggleActiveMutation.mutate(user._id)}>
                                <UserCog className="mr-2 h-4 w-4" />
                                Toggle Active
                              </DropdownMenuItem>
                              <DropdownMenuItem
                                onClick={() => handleDelete(user._id)}
                                className="text-red-600 focus:text-red-600"
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
            </div>

            {usersData?.totalPages && usersData.totalPages > 1 && (
              <div className="flex items-center justify-end space-x-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={!usersData?.hasPreviousPage}
                >
                  Previous
                </Button>
                <span className="text-sm text-muted-foreground">
                  Page {usersData?.page} of {usersData?.totalPages}
                </span>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setPage((p) => p + 1)}
                  disabled={!usersData?.hasNextPage}
                >
                  Next
                </Button>
              </div>
            )}
          </>
        )}

        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>{editingUser ? "Edit User" : "Create User"}</DialogTitle>
              <DialogDescription>
                {editingUser ? "Update user details and role." : "Add a new user to the system."}
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-6 py-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="name">Full Name</Label>
                  <Input
                    id="name"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    placeholder="John Doe"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="email">Email</Label>
                  <Input
                    id="email"
                    type="email"
                    value={formData.email}
                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                    placeholder="john@example.com"
                  />
                </div>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="phone">Phone</Label>
                  <Input
                    id="phone"
                    value={formData.phone}
                    onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                    placeholder="+1234567890"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="role">Role</Label>
                  <Select
                    value={formData.role}
                    onValueChange={(v: UserType) => setFormData({ ...formData, role: v })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {Object.entries(roleLabels).map(([value, label]) => (
                        <SelectItem key={value} value={value}>
                          {label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              {!editingUser && (
                <div className="space-y-2">
                  <Label htmlFor="password">Password</Label>
                  <Input
                    id="password"
                    type="password"
                    value={formData.password}
                    onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                    placeholder="Enter password"
                  />
                </div>
              )}

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="gender">Gender</Label>
                  <Select
                    value={formData.gender}
                    onValueChange={(v) => setFormData({ ...formData, gender: v })}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Select gender" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="male">Male</SelectItem>
                      <SelectItem value="female">Female</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="age">Age</Label>
                  <Input
                    id="age"
                    type="number"
                    value={formData.age || ""}
                    onChange={(e) => setFormData({ ...formData, age: parseInt(e.target.value) || 0 })}
                    placeholder="25"
                  />
                </div>
              </div>

              <div className="flex items-center gap-6">
                <div className="flex items-center gap-2">
                  <Switch
                    checked={formData.isActive}
                    onCheckedChange={(checked) => setFormData({ ...formData, isActive: checked })}
                  />
                  <Label>Active</Label>
                </div>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogOpen(false)}>
                Cancel
              </Button>
              <Button onClick={handleSubmit} disabled={createMutation.isPending || updateMutation.isPending}>
                {(createMutation.isPending || updateMutation.isPending) && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {editingUser ? "Update" : "Create"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        <Dialog open={planDialogOpen} onOpenChange={setPlanDialogOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Assign Plan to User</DialogTitle>
              <DialogDescription>
                Select a subscription plan for {selectedUserForPlan?.name}
              </DialogDescription>
            </DialogHeader>
            <div className="py-4">
              {plansLoading ? (
                <div className="flex items-center justify-center py-4">
                  <Loader2 className="h-4 w-4 animate-spin" />
                  <span className="ml-2 text-sm text-muted-foreground">Loading plans...</span>
                </div>
              ) : plans.length === 0 ? (
                <p className="text-sm text-muted-foreground py-4 text-center">No plans available. Please create a plan first.</p>
              ) : (
                <Select value={selectedPlanId} onValueChange={setSelectedPlanId}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select a plan" />
                  </SelectTrigger>
                  <SelectContent>
                    {plans.map((plan) => (
                      <SelectItem key={plan._id} value={plan._id}>
                        {plan.title} - ${plan.price}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setPlanDialogOpen(false)}>
                Cancel
              </Button>
              <Button 
                onClick={handleAssignPlan} 
                disabled={!selectedPlanId || assignPlanMutation.isPending || plansLoading || plans.length === 0}
              >
                {assignPlanMutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Assign Plan
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </AdminLayout>
  );
}

