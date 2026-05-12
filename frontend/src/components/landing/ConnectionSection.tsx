import { Button } from "@/components/ui/button";
import { Link } from "react-router-dom";
import { Cable, Wifi } from "lucide-react";
import connectionDiagram from "@/assets/connection-diagram.png";

const ConnectionSection = () => {
  return (
    <section id="connect" className="section-padding gradient-hero">
      <div className="container-custom">
        {/* Header */}
        <div className="text-center mb-16">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            Plug & Play or Go Wireless
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Connect your camera to your phone in seconds - wired or wireless
          </p>
        </div>

        {/* Two Ways Section */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 items-center mb-12">
          {/* Wired Card */}
          <div className="bg-card rounded-xl border border-border p-6 card-hover">
            <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
              <Cable className="w-6 h-6 text-primary" />
            </div>
            <h3 className="text-xl font-bold text-foreground mb-2">
              Wired (OTG Cable)
            </h3>
            <p className="text-muted-foreground">
              Connect directly with an OTG cable for the fastest, most reliable transfer speeds
            </p>
          </div>

          {/* Center Image */}
          <div className="flex justify-center">
            <img
              src={connectionDiagram}
              alt="Camera to phone connection"
              className="w-full max-w-sm object-contain"
              loading="lazy"
            />
          </div>

          {/* Wireless Card */}
          <div className="bg-card rounded-xl border border-border p-6 card-hover">
            <div className="w-12 h-12 rounded-xl bg-secondary/10 flex items-center justify-center mb-4">
              <Wifi className="w-6 h-6 text-secondary" />
            </div>
            <h3 className="text-xl font-bold text-foreground mb-2">
              Wireless (FTP)
            </h3>
            <p className="text-muted-foreground">
              Go cable-free with FTP connection for ultimate flexibility during events
            </p>
          </div>
        </div>

        {/* CTA */}
        <div className="text-center">
          <Button variant="default" size="lg" asChild>
            <Link to="/login">Get Started</Link>
          </Button>
        </div>
      </div>
    </section>
  );
};

export default ConnectionSection;
