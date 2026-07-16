import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Check } from "lucide-react";

interface PricingCardProps {
  tier: "silver" | "gold" | "platinum";
  badge: string;
  price: string;
  originalPrice?: string;
  currency?: string;
  period?: string;
  features: string[];
  highlighted?: boolean;
  className?: string;
}

const tierStyles = {
  silver: {
    accent: "border-l-4 border-l-secondary",
    button: "blue" as const,
    badgeBg: "bg-card-yellow text-primary",
  },
  gold: {
    accent: "border-l-4 border-l-secondary",
    button: "orange" as const,
    badgeBg: "bg-orange-100 text-orange-700",
  },
  platinum: {
    accent: "border-l-4 border-l-primary",
    button: "default" as const,
    badgeBg: "bg-card-pink text-primary",
  },
};

const PricingCard = ({
  tier,
  badge,
  price,
  originalPrice,
  currency = "$",
  period = "/month",
  features,
  highlighted = false,
  className,
  buttonText = "Get started",
  onBuyNow,
}: PricingCardProps & { buttonText?: string; onBuyNow?: () => void }) => {
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
        {originalPrice && originalPrice !== price ? (
          <div className="mb-1 text-sm text-muted-foreground line-through">
            {currency}{originalPrice}{period}
          </div>
        ) : null}
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

      {onBuyNow ? (
        <Button variant={styles.button} className="w-full" size="lg" onClick={onBuyNow}>
          {buttonText}
        </Button>
      ) : (
        <Button variant={styles.button} className="w-full" size="lg">
          {buttonText}
        </Button>
      )}
    </div>
  );
};

export default PricingCard;
