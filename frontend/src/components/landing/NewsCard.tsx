import { cn } from "@/lib/utils";
import { ArrowRight } from "lucide-react";

interface NewsCardProps {
  image: string;
  date: string;
  title: string;
  excerpt: string;
  className?: string;
}

const NewsCard = ({ image, date, title, excerpt, className }: NewsCardProps) => {
  return (
    <article
      className={cn(
        "bg-card rounded-xl border border-border overflow-hidden card-hover group",
        className
      )}
    >
      <div className="aspect-video relative overflow-hidden">
        <img
          src={image}
          alt={title}
          className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
          loading="lazy"
        />
        <div className="absolute top-4 left-4 bg-primary text-primary-foreground px-3 py-1 rounded-full text-xs font-medium">
          {date}
        </div>
      </div>
      
      <div className="p-6">
        <h3 className="text-lg font-bold text-foreground mb-2 line-clamp-2 group-hover:text-primary transition-colors">
          {title}
        </h3>
        <p className="text-muted-foreground text-sm mb-4 line-clamp-3">
          {excerpt}
        </p>
        <a
          href="#"
          className="inline-flex items-center gap-2 text-primary font-medium text-sm group-hover:gap-3 transition-all"
        >
          Read more
          <ArrowRight className="w-4 h-4" />
        </a>
      </div>
    </article>
  );
};

export default NewsCard;
