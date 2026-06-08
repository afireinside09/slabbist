import { Nav } from '@/components/marketing/nav';
import { Hero } from '@/components/marketing/hero';
import { FlowWalkthrough } from '@/components/marketing/flow-walkthrough';
import { FeatureSections } from '@/components/marketing/feature-sections';
import { EasterEggTeaser } from '@/components/marketing/easter-egg-teaser';
import { Pricing } from '@/components/marketing/pricing';
import { FinalCta } from '@/components/marketing/final-cta';
import { Footer } from '@/components/marketing/footer';

export default function Home() {
  return (
    <>
      <Nav />
      <Hero />
      <FlowWalkthrough />
      <FeatureSections />
      <EasterEggTeaser />
      <Pricing />
      <FinalCta />
      <Footer />
    </>
  );
}
