import { PesuBrand } from '@/components/ui/pesu-brand';
import { ScrollStoryHero } from '@/components/ui/scroll-story-hero';

export default function Home() {
  return (
    <main>
      <ScrollStoryHero />
      <footer className="founding-footer">
        <a className="footer-brand" href="#top" aria-label="Pēsu home">
          <PesuBrand />
        </a>
        <div className="footer-promise">
          <p>Join early. Keep Pēsu free for life.</p>
        </div>
      </footer>
    </main>
  );
}
