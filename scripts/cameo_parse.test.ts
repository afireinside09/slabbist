import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseCameoSheet } from "./cameo_parse.ts";

// Rows are header-stripped, position-based arrays:
// [Ndex/region, CameoName, CardName, Set, #, Notes]
Deno.test("forward-fills subject, reprints, and resets card at the next subject", () => {
  const rows = [
    ["152", "Chikorita", "Pokémon March", "Neo Genesis", "102", ""],
    ["", "", "", "Unseen Forces", "89", "reprint"],   // reprint: blank card name
    ["", "", "Professor Elm", "Expedition", "148", ""], // new card, same subject
    ["155", "Cyndaquil", "Switch", "Neo Genesis", "94", ""], // new subject resets card
  ];

  const subjects = parseCameoSheet(rows, { generation: "Gen 2", kind: "pokemon" });

  assertEquals(subjects.length, 2);

  assertEquals(subjects[0], {
    kind: "pokemon", ndex: 152, region: null, name: "Chikorita",
    cards: [
      { cardName: "Pokémon March",  setName: "Neo Genesis",  cardNumber: "102", notes: "",        generation: "Gen 2" },
      { cardName: "Pokémon March",  setName: "Unseen Forces", cardNumber: "89",  notes: "reprint", generation: "Gen 2" },
      { cardName: "Professor Elm",  setName: "Expedition",    cardNumber: "148", notes: "",        generation: "Gen 2" },
    ],
  });

  assertEquals(subjects[1].name, "Cyndaquil");
  assertEquals(subjects[1].cards[0].cardName, "Switch"); // did NOT bleed "Professor Elm"
});

Deno.test("trainer sheet forward-fills region from column 0", () => {
  const rows = [
    ["KANTO", "Red",  "Red's Pikachu", "SM-P Promos",    "270", ""],
    ["",      "",     "Pikachu",       "Cosmic Eclipse", "241", ""], // same region+subject
    ["",      "Blue", "Blue's Pikachu","SV Promos",      "1",   ""], // new subject, region carries
  ];

  const subjects = parseCameoSheet(rows, { generation: "Trainers", kind: "trainer" });

  assertEquals(subjects[0], {
    kind: "trainer", ndex: null, region: "KANTO", name: "Red",
    cards: [
      { cardName: "Red's Pikachu", setName: "SM-P Promos",    cardNumber: "270", notes: "", generation: "Trainers" },
      { cardName: "Pikachu",       setName: "Cosmic Eclipse", cardNumber: "241", notes: "", generation: "Trainers" },
    ],
  });
  assertEquals(subjects[1], {
    kind: "trainer", ndex: null, region: "KANTO", name: "Blue",
    cards: [
      { cardName: "Blue's Pikachu", setName: "SV Promos", cardNumber: "1", notes: "", generation: "Trainers" },
    ],
  });
});
