import { cn } from "@/lib/utils";
import { Quote } from "lucide-react";

interface TestimonialCardProps {
  quote: string;
  name: string;
  title: string;
  company?: string;
  logo?: string;
  className?: string;
}

const TestimonialCard = ({
  quote,
  name,
  title,
  company,
  logo,
  className,
}: TestimonialCardProps) => {
  return (
    <div
      className={cn(
        "bg-card rounded-xl border border-border p-8",
        className
      )}
    >
      {logo && (
        <img 
          src={logo} 
          alt={company || "Company"} 
          className="h-8 mb-6 object-contain opacity-70"
        />
      )}
      
      <Quote className="w-8 h-8 text-primary/30 mb-4" />
      
      <blockquote className="text-lg text-foreground leading-relaxed mb-6">
        "{quote}"
      </blockquote>

      <div className="flex items-center gap-4">
        <div className="w-12 h-12 rounded-full bg-gradient-to-br from-primary to-secondary flex items-center justify-center text-white font-bold">
          {name.charAt(0)}
        </div>
        <div>
          <p className="font-semibold text-foreground">{name}</p>
          <p className="text-sm text-muted-foreground">
            {title}{company && `, ${company}`}
          </p>
        </div>
      </div>
    </div>
  );
};

export default TestimonialCard;
