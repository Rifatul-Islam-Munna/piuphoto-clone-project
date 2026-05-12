import { Users, Calendar, Image, CreditCard } from "lucide-react";
import AdminLayout from "./AdminLayout";

export default function Dashboard() {
  const stats = [
    { label: "Total Users", value: "1,234", icon: Users, change: "+12%", positive: true },
    { label: "Active Events", value: "56", icon: Calendar, change: "+8%", positive: true },
    { label: "Photos Uploaded", value: "8.4k", icon: Image, change: "+24%", positive: true },
    { label: "Active Subscriptions", value: "89", icon: CreditCard, change: "-3%", positive: false },
  ];

  return (
    <AdminLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Dashboard</h1>
            <p className="text-muted-foreground">Welcome back! Here is your overview.</p>
          </div>
        </div>

        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {stats.map((stat) => (
            <div key={stat.label} className="rounded-lg border bg-card p-6">
              <div className="flex items-center justify-between">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                  <stat.icon className="h-5 w-5 text-primary" />
                </div>
                <span className={stat.positive ? "text-green-500" : "text-red-500"}>{stat.change}</span>
              </div>
              <div className="mt-4">
                <p className="text-2xl font-bold">{stat.value}</p>
                <p className="text-sm text-muted-foreground">{stat.label}</p>
              </div>
            </div>
          ))}
        </div>

        <div className="grid gap-4 md:grid-cols-2">
          <div className="rounded-lg border bg-card p-6">
            <h3 className="font-semibold">Recent Activity</h3>
            <div className="mt-4 space-y-4">
              {[1, 2, 3].map((i) => (
                <div key={i} className="flex items-center gap-3">
                  <div className="h-2 w-2 rounded-full bg-primary" />
                  <div className="flex-1">
                    <p className="text-sm">New user registered</p>
                    <p className="text-xs text-muted-foreground">2 minutes ago</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
          <div className="rounded-lg border bg-card p-6">
            <h3 className="font-semibold">Quick Actions</h3>
            <div className="mt-4 grid grid-cols-2 gap-3">
              <a href="/admin/plans" className="rounded-lg border p-3 text-center hover:bg-accent">
                <CreditCard className="mx-auto h-5 w-5" />
                <span className="text-sm">Manage Plans</span>
              </a>
              <a href="/admin/users" className="rounded-lg border p-3 text-center hover:bg-accent">
                <Users className="mx-auto h-5 w-5" />
                <span className="text-sm">Manage Users</span>
              </a>
            </div>
          </div>
        </div>
      </div>
    </AdminLayout>
  );
}