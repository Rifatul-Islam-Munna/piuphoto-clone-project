import { cn } from "@/lib/utils";

interface FeatureCardProps {
  icon: string;
  title: string;
  description: string;
  variant: "yellow" | "blue" | "purple" | "pink";
  className?: string;
}

const variantStyles = {
  yellow: "bg-card-yellow",
  blue: "bg-card-blue", 
  purple: "bg-card-purple",
  pink: "bg-card-pink",
};

const FeatureCard = ({ icon, title, description, variant, className }: FeatureCardProps) => {
  return (
    <div
      className={cn(
        "rounded-xl border border-border/50 p-6 card-hover",
        variantStyles[variant],
        className
      )}
    >
      <div className="text-4xl mb-4">{icon}</div>
      <h3 className="text-xl font-bold mb-2 text-foreground">{title}</h3>
      <p className="text-muted-foreground leading-relaxed">{description}</p>
    </div>
  );
};

export default FeatureCard;
