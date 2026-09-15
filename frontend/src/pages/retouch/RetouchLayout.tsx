import { type ReactNode } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { Images, LogOut, Scissors, Settings, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useWorkspaceAccess } from "@/hooks/use-workspace-access";
export default function RetouchLayout({children}:{children:ReactNode}){
  const location=useLocation(); const navigate=useNavigate(); const access=useWorkspaceAccess();
  const userRaw=localStorage.getItem("user"); const user=userRaw?JSON.parse(userRaw):null;
  const logout=()=>{localStorage.removeItem("access_token");localStorage.removeItem("user");navigate("/login")};
  const items=[{label:"Retouch queue",href:"/retouch",icon:Scissors}];
  return <div className="min-h-screen bg-muted/20">
    <header className="border-b bg-background"><div className="mx-auto flex h-16 max-w-[1500px] items-center justify-between px-4 sm:px-6"><Link to="/retouch" className="flex items-center gap-2 font-bold"><Scissors className="h-5 w-5"/>airpix retouch</Link><div className="flex gap-2">{access.data?.planner?<Button variant="outline" size="sm" onClick={()=>navigate("/planner/dashboard")}><ArrowLeft className="mr-2 h-4 w-4"/>Planner</Button>:null}<Button variant="ghost" size="icon" onClick={logout}><LogOut className="h-4 w-4"/></Button></div></div></header>
    <div className="mx-auto grid max-w-[1500px] gap-6 px-4 py-6 sm:px-6 lg:grid-cols-[220px_minmax(0,1fr)]"><aside className="h-fit rounded-2xl border bg-background p-3"><div className="mb-3 rounded-xl bg-muted/50 p-3"><p className="text-sm font-semibold">{user?.name||"Retoucher"}</p><p className="truncate text-xs text-muted-foreground">{user?.email||""}</p></div><nav className="space-y-1">{items.map(item=><Link key={item.href} to={item.href} className={cn("flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium",location.pathname===item.href?"bg-primary text-primary-foreground":"text-muted-foreground hover:bg-muted")}><item.icon className="h-4 w-4"/>{item.label}</Link>)}</nav></aside><main className="min-w-0">{children}</main></div>
  </div>
}
