import { AuthProvider } from '@/components/marketing/auth-context';
import { Nav } from '@/components/marketing/nav';
import { Hero } from '@/components/marketing/hero';
import { FeatureRow } from '@/components/marketing/feature-row';
import { Workflow } from '@/components/marketing/workflow';
import { Pricing } from '@/components/marketing/pricing';
import { FinalCta } from '@/components/marketing/final-cta';
import { Footer } from '@/components/marketing/footer';

export default function Home() {
  return (
    <AuthProvider>
      <Nav />
      <Hero />
      <FeatureRow />
      <Workflow />
      <Pricing />
      <FinalCta />
      <Footer />
    </AuthProvider>
  );
}
