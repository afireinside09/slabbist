export type FlowStepId = 'scan' | 'comp' | 'margin' | 'offer' | 'paid';

export type FlowStep = {
  id: FlowStepId;
  n: string;        // '01'..'05'
  kicker: string;   // short uppercase label
  title: string;    // serif headline
  body: string;     // one or two sentences, dealer voice
};

export const FLOW_STEPS: FlowStep[] = [
  {
    id: 'scan',
    n: '01',
    kicker: 'Scan the stack',
    title: 'Aim the camera and keep going.',
    body: 'The camera reads the cert number off each slab and queues it. Rows fill in as comps land. It keeps queuing offline when the show wifi dies.',
  },
  {
    id: 'comp',
    n: '02',
    kicker: 'Real comp',
    title: 'A real price, backed by real sales.',
    body: 'We average recent sold listings into one price and show the price at each grade. It\'s a number you can show the seller.',
  },
  {
    id: 'margin',
    n: '03',
    kicker: 'Set your margin',
    title: 'Your markup, on every card.',
    body: 'Every line gets a buy price — comp times your margin. Use a flat percentage or your buy-price rules. Override any single line by hand.',
  },
  {
    id: 'offer',
    n: '04',
    kicker: 'Send the offer',
    title: 'One total. Every line. Right now.',
    body: 'Roll the lot into an offer with a total, per-slab lines, and payment method. Make the call while the seller is still at the counter.',
  },
  {
    id: 'paid',
    n: '05',
    kicker: 'Mark it paid',
    title: 'Paid and locked.',
    body: 'Paid lots lock into a receipt — vendor, total, method, timestamp. Void with a reason if you must. The trail stays intact.',
  },
];
