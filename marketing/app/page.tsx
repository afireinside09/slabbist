import { Nav } from '@/components/marketing/nav';
import { Hero } from '@/components/marketing/hero';
import { FeatureRow } from '@/components/marketing/feature-row';
import { IntelligenceSuite } from '@/components/marketing/intelligence-suite';
import { Workflow } from '@/components/marketing/workflow';
import { EasterEggTeaser } from '@/components/marketing/easter-egg-teaser';
import { Pricing } from '@/components/marketing/pricing';
import { FinalCta } from '@/components/marketing/final-cta';
import { Footer } from '@/components/marketing/footer';

export default function Home() {
  return (
    <>
      <Nav />
      <Hero />
      <FeatureRow />
      <IntelligenceSuite />
      <Workflow />
      <EasterEggTeaser />
      <Pricing />
      <FinalCta />
      <Footer />
    </>
  );
}
