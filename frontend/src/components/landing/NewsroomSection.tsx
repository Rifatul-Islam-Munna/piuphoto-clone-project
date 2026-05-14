import NewsCard from "./NewsCard";
import eventPhoto from "@/assets/event-photo.jpg";
import { useSiteSettings } from "./site-settings-context";

const NewsroomSection = () => {
  const { settings, t } = useSiteSettings();

  return (
    <section className="section-padding bg-card">
      <div className="container-custom">
        <div className="text-center mb-12">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            {t(settings.newsroom.heading)}
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            {t(settings.newsroom.description)}
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {settings.newsroom.items.map((item, index) => (
            <NewsCard
              key={index}
              image={eventPhoto}
              date={item.date}
              title={t(item.title)}
              excerpt={t(item.excerpt)}
              readMoreLabel={t(settings.newsroom.readMoreLabel)}
            />
          ))}
        </div>

        <div className="flex justify-center gap-2 mt-8">
          <div className="w-2 h-2 rounded-full bg-primary" />
          <div className="w-2 h-2 rounded-full bg-border" />
          <div className="w-2 h-2 rounded-full bg-border" />
        </div>
      </div>
    </section>
  );
};

export default NewsroomSection;
