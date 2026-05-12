import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Check } from "lucide-react";

interface PricingCardProps {
  tier: "silver" | "gold" | "platinum";
  badge: string;
  price: string;
  currency?: string;
  period?: string;
  features: string[];
  highlighted?: boolean;
  className?: string;
}

const tierStyles = {
  silver: {
    accent: "border-l-4 border-l-blue-500",
    button: "blue" as const,
    badgeBg: "bg-blue-100 text-blue-700",
  },
  gold: {
    accent: "border-l-4 border-l-secondary",
    button: "orange" as const,
    badgeBg: "bg-orange-100 text-orange-700",
  },
  platinum: {
    accent: "border-l-4 border-l-primary",
    button: "default" as const,
    badgeBg: "bg-purple-100 text-purple-700",
  },
};

const PricingCard = ({
  tier,
  badge,
  price,
  currency = "$",
  period = "/month",
  features,
  highlighted = false,
  className,
}: PricingCardProps) => {
  const styles = tierStyles[tier];

  return (
    <div
      className={cn(
        "bg-card rounded-xl border border-border p-6 card-hover",
        styles.accent,
        highlighted && "border-2 border-primary/30 scale-105",
        className
      )}
    >
      <div className={cn("inline-block px-3 py-1 rounded-full text-xs font-semibold mb-4", styles.badgeBg)}>
        {badge}
      </div>
      
      <div className="mb-6">
        <p className="text-sm text-muted-foreground mb-1">starts from:</p>
        <div className="flex items-baseline gap-1">
          <span className="text-3xl font-bold text-foreground">{currency}{price}</span>
          <span className="text-muted-foreground">{period}</span>
        </div>
      </div>

      <ul className="space-y-3 mb-8">
        {features.map((feature, index) => (
          <li key={index} className="flex items-start gap-3">
            <Check className="w-5 h-5 text-primary shrink-0 mt-0.5" />
            <span className="text-sm text-foreground">{feature}</span>
          </li>
        ))}
      </ul>

      <Button variant={styles.button} className="w-full" size="lg">
        Get started
      </Button>
    </div>
  );
};

export default PricingCard;
