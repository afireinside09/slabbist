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
    title: 'Point the camera. Keep going.',
    body: 'OCR reads the cert off each slab and queues it. Rows fill in as comps land — and keep queuing offline when the show wifi drops.',
  },
  {
    id: 'comp',
    n: '02',
    kicker: 'The defensible number',
    title: 'A real number, with its receipts.',
    body: 'Recent sold sales reconciled into one price, with a per-grade ladder and confidence. Not a vibe — a number you can show the seller.',
  },
  {
    id: 'margin',
    n: '03',
    kicker: 'Set your margin',
    title: 'Your spread, applied down the stack.',
    body: 'Every line gets a buy price — comp × your margin. Use a flat percentage or the store ladder, and override any single line by hand.',
  },
  {
    id: 'offer',
    n: '04',
    kicker: 'Send the offer',
    title: 'One total. Every line. In front of them.',
    body: 'Roll the lot into an offer: total, per-slab lines, payment method and reference. Make the call while the seller is still at the counter.',
  },
  {
    id: 'paid',
    n: '05',
    kicker: 'Mark it paid',
    title: 'Closed, frozen, on the books.',
    body: 'Paid lots lock into an immutable receipt — vendor, total, method, timestamp. Void with a reason if you must; the trail stays intact.',
  },
];
