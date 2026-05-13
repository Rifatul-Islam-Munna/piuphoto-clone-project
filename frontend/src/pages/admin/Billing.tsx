import { useState } from "react";
import { FileText, Loader2, Receipt } from "lucide-react";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
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
import AdminLayout from "./AdminLayout";
import { useQueryWrapper } from "../../../api-hooks/react-query-wrapper";

type PurchaseItem = {
  _id: string;
  title: string;
};

type PurchaseUser = {
  _id: string;
  name: string;
  email?: string | null;
  phone?: string | null;
  userId?: string | null;
};

type PurchaseHistoryRow = {
  _id: string;
  type: "plan" | "addon";
  status: string;
  stripeSessionId: string;
  stripePaymentIntentId?: string | null;
  price: number;
  currency: string;
  credit: number;
  createdAt: string;
  completedAt?: string | null;
  item: PurchaseItem | null;
  user: PurchaseUser | null;
};

type PurchaseHistoryResponse = {
  data: PurchaseHistoryRow[];
  totalItems: number;
};

type InvoiceResponse = {
  type: "plan" | "addon";
  invoiceNumber: string;
  status: string;
  stripeSessionId: string;
  stripePaymentIntentId?: string | null;
  createdAt: string;
  completedAt?: string | null;
  price: number;
  currency: string;
  credit: number;
  item?: {
    _id: string;
    title: string;
    description?: string;
  } | null;
  user?: PurchaseUser | null;
};

export default function Billing() {
  const [typeFilter, setTypeFilter] = useState("all");
  const [selectedInvoice, setSelectedInvoice] = useState<{
    id: string;
    type: "plan" | "addon";
  } | null>(null);

  const historyQuery = useQueryWrapper<PurchaseHistoryResponse>(
    ["purchase-history", typeFilter],
    `/subscription-plan/purchase-history?type=${typeFilter}`,
    { withToken: true, withCredentials: true },
  );

  const invoiceQuery = useQueryWrapper<InvoiceResponse>(
    ["invoice", selectedInvoice?.id, selectedInvoice?.type],
    selectedInvoice
      ? `/subscription-plan/invoice?id=${selectedInvoice.id}&type=${selectedInvoice.type}`
      : "/subscription-plan/invoice?id=none&type=plan",
    {
      withToken: true,
      withCredentials: true,
      enabled: !!selectedInvoice,
    },
  );

  const rows = historyQuery.data?.data || [];

  return (
    <AdminLayout>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Purchase History</h1>
            <p className="text-muted-foreground">
              Admin can review purchases and invoice details here.
            </p>
          </div>
          <div className="w-40">
            <Select value={typeFilter} onValueChange={setTypeFilter}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All</SelectItem>
                <SelectItem value="plan">Plans</SelectItem>
                <SelectItem value="addon">Addons</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Billing History</CardTitle>
            <CardDescription>
              Stripe purchase rows for plans and addons.
            </CardDescription>
          </CardHeader>
          <CardContent>
            {historyQuery.isLoading ? (
              <div className="flex h-40 items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Type</TableHead>
                    <TableHead>Item</TableHead>
                    <TableHead>User</TableHead>
                    <TableHead>Price</TableHead>
                    <TableHead>Credits</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead className="text-right">Invoice</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={8} className="h-24 text-center">
                        No purchase history found.
                      </TableCell>
                    </TableRow>
                  ) : (
                    rows.map((row) => (
                      <TableRow key={row._id}>
                        <TableCell>
                          <Badge variant="outline">{row.type}</Badge>
                        </TableCell>
                        <TableCell>{row.item?.title || "-"}</TableCell>
                        <TableCell>
                          {row.user?.name || "-"}
                          <div className="text-xs text-muted-foreground">
                            {row.user?.email || row.user?.phone || row.user?.userId || ""}
                          </div>
                        </TableCell>
                        <TableCell>
                          {row.currency} {row.price}
                        </TableCell>
                        <TableCell>{row.credit}</TableCell>
                        <TableCell>
                          <Badge
                            variant={row.status === "completed" ? "default" : "secondary"}
                          >
                            {row.status}
                          </Badge>
                        </TableCell>
                        <TableCell>{new Date(row.createdAt).toLocaleDateString()}</TableCell>
                        <TableCell className="text-right">
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() =>
                              setSelectedInvoice({ id: row._id, type: row.type })
                            }
                          >
                            <Receipt className="mr-2 h-4 w-4" />
                            View
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Dialog
          open={!!selectedInvoice}
          onOpenChange={(open) => !open && setSelectedInvoice(null)}
        >
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>Invoice Details</DialogTitle>
              <DialogDescription>
                Admin invoice summary for selected purchase.
              </DialogDescription>
            </DialogHeader>

            {invoiceQuery.isLoading ? (
              <div className="flex h-40 items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : invoiceQuery.data ? (
              <div className="space-y-4">
                <div className="rounded-lg border p-4">
                  <div className="flex items-center gap-2">
                    <FileText className="h-5 w-5 text-muted-foreground" />
                    <span className="font-medium">{invoiceQuery.data.invoiceNumber}</span>
                  </div>
                </div>

                <div className="grid gap-4 md:grid-cols-2">
                  <Card>
                    <CardHeader>
                      <CardTitle className="text-base">Purchase</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-2 text-sm">
                      <p>Type: {invoiceQuery.data.type}</p>
                      <p>Item: {invoiceQuery.data.item?.title || "-"}</p>
                      <p>Status: {invoiceQuery.data.status}</p>
                      <p>
                        Amount: {invoiceQuery.data.currency} {invoiceQuery.data.price}
                      </p>
                      <p>Credits: {invoiceQuery.data.credit}</p>
                    </CardContent>
                  </Card>

                  <Card>
                    <CardHeader>
                      <CardTitle className="text-base">User</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-2 text-sm">
                      <p>Name: {invoiceQuery.data.user?.name || "-"}</p>
                      <p>Email: {invoiceQuery.data.user?.email || "-"}</p>
                      <p>Phone: {invoiceQuery.data.user?.phone || "-"}</p>
                      <p>User ID: {invoiceQuery.data.user?.userId || "-"}</p>
                    </CardContent>
                  </Card>
                </div>

                <Card>
                  <CardHeader>
                    <CardTitle className="text-base">Stripe</CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-2 text-sm break-all">
                    <p>Session: {invoiceQuery.data.stripeSessionId}</p>
                    <p>
                      Payment Intent: {invoiceQuery.data.stripePaymentIntentId || "-"}
                    </p>
                    <p>
                      Created: {new Date(invoiceQuery.data.createdAt).toLocaleString()}
                    </p>
                    <p>
                      Completed:{" "}
                      {invoiceQuery.data.completedAt
                        ? new Date(invoiceQuery.data.completedAt).toLocaleString()
                        : "-"}
                    </p>
                  </CardContent>
                </Card>
              </div>
            ) : null}
          </DialogContent>
        </Dialog>
      </div>
    </AdminLayout>
  );
}

