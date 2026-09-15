import { Badge } from "@/components/ui/badge";
import PricingSection from "@/components/landing/PricingSection";
import PhotographerLayout from "./PhotographerLayout";

export default function PhotographerPlans() {
  const raw = localStorage.getItem("user");
  const user = raw ? JSON.parse(raw) : null;
  const plan = user?.subscriptionPlanId;
  const permissions = Array.isArray(plan?.permissions) ? plan.permissions : [];
  const quota = (key: string) => {
    const item = permissions.find((entry: Record<string, unknown>) => entry?.key === key);
    return item?.value ?? "Not included";
  };

  return (
    <PhotographerLayout>
      <div className="space-y-6">
        <section className="rounded-2xl border bg-background p-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div><p className="text-sm text-muted-foreground">Photographer billing</p><h1 className="text-2xl font-bold">Plans & delivery limits</h1></div>
            <Badge variant={user?.isSubscriber ? "default" : "secondary"}>{user?.isSubscriber ? plan?.title || "Active plan" : "No active plan"}</Badge>
          </div>
          <div className="mt-4 grid gap-3 sm:grid-cols-3">
            <div className="rounded-xl bg-muted/50 p-3"><p className="text-xs text-muted-foreground">Email deliveries</p><p className="mt-1 text-lg font-semibold">{quota("notifications.email")}</p></div>
            <div className="rounded-xl bg-muted/50 p-3"><p className="text-xs text-muted-foreground">WhatsApp deliveries</p><p className="mt-1 text-lg font-semibold">{quota("notifications.whatsapp")}</p></div>
            <div className="rounded-xl bg-muted/50 p-3"><p className="text-xs text-muted-foreground">Solo sessions</p><p className="mt-1 text-lg font-semibold">{Array.isArray(plan?.features) && plan.features.includes("event.create") ? "Enabled" : "Upgrade required"}</p></div>
          </div>
        </section>
        <PricingSection />
      </div>
    </PhotographerLayout>
  );
}
