import { Button } from "@/components/ui/button";
import { Apple, Play } from "lucide-react";

const HeroSection = () => {
  return (
    <section className="gradient-hero pt-32 pb-20 px-6">
      <div className="container-custom text-center">
        <h1 className="text-4xl md:text-5xl lg:text-6xl font-bold text-foreground mb-6 animate-fade-in">
          <span className="text-primary">nikofly</span>, Photos Can Fly
        </h1>
        
        <p className="text-lg md:text-xl text-muted-foreground max-w-2xl mx-auto mb-10 animate-fade-in" style={{ animationDelay: "0.1s" }}>
          An event live streaming photos solution to let photographers & guests enjoy photos as easy as ABC
        </p>

        <div className="flex flex-col sm:flex-row items-center justify-center gap-4 animate-fade-in" style={{ animationDelay: "0.2s" }}>
          <Button variant="hero" size="lg" className="w-full sm:w-auto gap-3">
            <Apple className="w-5 h-5" />
            Download on App Store
          </Button>
          <Button variant="hero-outline" size="lg" className="w-full sm:w-auto gap-3">
            <Play className="w-5 h-5" />
            Get it on Google Play
          </Button>
        </div>
      </div>
    </section>
  );
};

export default HeroSection;
