import NewsCard from "./NewsCard";
import eventPhoto from "@/assets/event-photo.jpg";

const newsItems = [
  {
    image: eventPhoto,
    date: "Jan 15, 2026",
    title: "nikofly Launches AI-Powered Photo Selection Feature",
    excerpt: "Our new AI technology automatically selects the best photos from your event, saving photographers hours of manual curation work.",
  },
  {
    image: eventPhoto,
    date: "Dec 28, 2025",
    title: "How Event Photographers Are Embracing Real-Time Streaming",
    excerpt: "A deep dive into the growing trend of instant photo delivery at weddings, corporate events, and concerts.",
  },
  {
    image: eventPhoto,
    date: "Dec 10, 2025",
    title: "nikofly Partners with Major Camera Manufacturers",
    excerpt: "New partnerships enable seamless integration with Canon, Nikon, and Sony cameras for enhanced workflow efficiency.",
  },
];

const NewsroomSection = () => {
  return (
    <section className="section-padding bg-card">
      <div className="container-custom">
        <div className="text-center mb-12">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            Newsroom
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Stay updated with the latest from nikofly
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {newsItems.map((item, index) => (
            <NewsCard
              key={index}
              image={item.image}
              date={item.date}
              title={item.title}
              excerpt={item.excerpt}
            />
          ))}
        </div>

        {/* Pagination Dots */}
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
