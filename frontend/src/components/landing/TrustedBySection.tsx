const brands = [
  "Canon", "Nikon", "Sony", "Adobe", "Capture One", "Lightroom",
  "DJI", "GoPro", "Leica", "Fujifilm", "Olympus", "Panasonic",
  "Hasselblad", "Phase One", "Sigma", "Tamron", "Profoto", "Godox",
  "Peak Design", "Think Tank", "Lowepro", "Manfrotto", "SanDisk", "Lexar",
];

const TrustedBySection = () => {
  return (
    <section className="section-padding bg-card">
      <div className="container-custom">
        <div className="text-center mb-12">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            Trusted by Top Brands
          </h2>
        </div>

        <div className="grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 gap-4 md:gap-6">
          {brands.map((brand, index) => (
            <div
              key={index}
              className="h-12 md:h-16 flex items-center justify-center rounded-lg bg-muted/50 border border-border"
            >
              <span className="text-xs md:text-sm font-medium text-muted-foreground/60">
                {brand}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default TrustedBySection;
