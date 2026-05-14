import heroMockup from "@/assets/hero-mockup.png";
import { useSiteSettings } from "./site-settings-context";

const ProductShowcase = () => {
  const { settings } = useSiteSettings();

  return (
    <section className="py-12 px-6 bg-card">
      <div className="container-custom">
        <div className="relative max-w-5xl mx-auto">
          {/* Glow effect using border */}
          <div className="absolute inset-0 bg-gradient-to-r from-primary/20 via-secondary/20 to-primary/20 rounded-3xl blur-3xl -z-10 scale-95" />
          
          <div className="rounded-2xl border border-primary/20 overflow-hidden bg-dark-section">
            <img
              src={settings.productShowcase.imageUrl || heroMockup}
              alt="nikofly app interface showing photo gallery on tablet and phone"
              className="w-full h-auto"
              loading="eager"
            />
          </div>
        </div>
      </div>
    </section>
  );
};

export default ProductShowcase;
