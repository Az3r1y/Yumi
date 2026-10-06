// Every word of the recap, in French and in English. Same beats, same facts: only the
// language changes. The takes stay as they were filmed, with the app in French.

export type Langue = "fr" | "en";

type Item = { readonly lines: readonly string[]; readonly sub?: string; readonly legende: string };
type Chiffre = { readonly n: number; readonly label: string; readonly about?: boolean; readonly unit?: string };

export type Texte = {
  /** 27 000 or 27,000. */
  readonly groupe: (n: number) => string;
  readonly ouverture: { readonly lines: readonly string[]; readonly sub: string };
  readonly depart: { readonly kicker: string; readonly lines: readonly string[]; readonly sub: string; readonly legende: string };
  readonly construit: { readonly kicker: string; readonly lines: readonly string[]; readonly legende: string; readonly items: readonly Item[]; readonly langues: readonly string[] };
  readonly chiffres: { readonly kicker: string; readonly list: readonly Chiffre[]; readonly legendes: readonly [string, string, string] };
  readonly comment: { readonly kicker: string; readonly avant: readonly string[]; readonly apres: readonly string[]; readonly legendes: readonly [string, string] };
  readonly suite: { readonly kicker: string; readonly retours: readonly string[]; readonly agir: readonly string[]; readonly agirSub: string; readonly citation: string; readonly legendes: readonly [string, string] };
  readonly pied: { readonly prises: string; readonly branches: string };
  readonly fin: { readonly alpha: string };
};

const NBSP = " ";

export const TEXTE: Record<Langue, Texte> = {
  fr: {
    groupe: (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " "),
    ouverture: { lines: ["Il vit dans", "la notch", "de mon Mac."], sub: "Voilà ce que j'ai construit en quelques jours." },
    depart: {
      kicker: "01 · Le point de départ",
      lines: ["Un fork", "de Coucou."],
      sub: `Code MIT de Louis Raillé, crédité. 1er${NBSP}octobre 2026.`,
      legende: "Début octobre, je pars d'un fork de Coucou, sous licence MIT, crédité.",
    },
    construit: {
      kicker: "02 · Ce qui a été construit",
      lines: ["En quelques", "jours."],
      legende: "Depuis, voilà ce qui a été construit.",
      items: [
        { lines: ["Un personnage", "dessiné en code."], legende: "D'abord, un personnage dessiné en code." },
        { lines: ["L'île,", "dans la notch."], legende: "Il vit dans l'île, sous la notch." },
        { lines: ["Claude Code,", "l'accord depuis", "la notch."], legende: "Il suit mes sessions Claude Code. J'accorde depuis la notch." },
        { lines: ["Un agent qui", "propose un plan."], legende: "Un agent propose un plan avant d'agir." },
        { lines: ["Une seule", "porte."], sub: "Le Permission System : le risque est décidé par le code.", legende: "Chaque action passe par la même porte, puis elle est vérifiée." },
        { lines: ["6 actions."], sub: "Fichier · ajout à un fichier · rappel · agenda · focus · résumé du jour et temps libre", legende: "Six actions, du fichier au résumé du jour et au temps libre." },
        { lines: ["Les modules."], sub: "Musique · agenda · rappels · météo · GitHub", legende: "Des modules : musique, agenda, rappels, météo, GitHub." },
        { lines: ["Une mémoire", "locale.", "L'initiative."], legende: "Une mémoire qui reste sur le Mac, et il prend l'initiative." },
        { lines: ["5 moteurs."], legende: "Cinq moteurs au choix." },
        { lines: ["Anglais", "et français."], sub: "Des réglages refaits.", legende: "En anglais et en français, avec des réglages refaits." },
      ],
      langues: ["English.", "Français."],
    },
    chiffres: {
      kicker: "03 · En chiffres",
      list: [
        { n: 206, label: "commits" },
        { n: 27000, label: "lignes de Swift", about: true },
        { n: 778, label: "tests" },
        { n: 2, label: "alphas publiées" },
        { n: 6, label: "de code d'origine restant", about: true, unit: `${NBSP}%` },
        { n: 1, label: "site" },
        { n: 4, label: "vidéos" },
        { n: 40000, label: "impressions, premier post LinkedIn", about: true },
        { n: 11, label: "étoiles sur GitHub" },
      ],
      legendes: [
        "206 commits, environ 27 000 lignes de Swift, 778 tests.",
        "2 alphas publiées, environ 6 % de code d'origine restant, un site.",
        "4 vidéos, environ 40 000 impressions sur le premier post, 11 étoiles.",
      ],
    },
    comment: {
      kicker: "04 · Comment",
      avant: ["Plusieurs sessions", "en parallèle."],
      apres: ["Une qui coordonne", "et fusionne."],
      legendes: ["Plusieurs sessions Claude Code travaillent en parallèle.", "Une session de coordination tient les contrats et fusionne."],
    },
    suite: {
      kicker: "05 · La suite",
      retours: ["Les retours", "de l'alpha."],
      agir: ["Lire,", "puis agir."],
      agirSub: "Un aperçu du plan avant d'agir.",
      citation: `«${NBSP}Prépare ma journée.${NBSP}»`,
      legendes: ["La suite : les retours de l'alpha.", "Puis « lire puis agir » : prépare ma journée, avec un aperçu du plan."],
    },
    pied: { prises: "Prises réelles de l'app · mode tournage, données d'exemple", branches: "Branches réelles du dépôt" },
    fin: { alpha: "Alpha gratuite." },
  },
  en: {
    groupe: (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","),
    ouverture: { lines: ["It lives in", "my Mac's", "notch."], sub: "Here's what I built in a few days." },
    depart: {
      kicker: "01 · Where it started",
      lines: ["A fork", "of Coucou."],
      sub: "MIT code by Louis Raillé, credited. October 1, 2026.",
      legende: "Early October, I started from a fork of Coucou: MIT licensed, and credited.",
    },
    construit: {
      kicker: "02 · What got built",
      lines: ["In a few", "days."],
      legende: "Since then, here's what got built.",
      items: [
        { lines: ["A character", "drawn in code."], legende: "First, a character drawn in code." },
        { lines: ["The island,", "in the notch."], legende: "It lives in the island, under the notch." },
        { lines: ["Claude Code,", "approved from", "the notch."], legende: "It follows my Claude Code sessions. I approve right from the notch." },
        { lines: ["An agent that", "proposes a plan."], legende: "An agent proposes a plan before it acts." },
        { lines: ["One single", "door."], sub: "The Permission System: the code decides the risk.", legende: "Every action goes through the same door, then gets verified." },
        { lines: ["6 actions."], sub: "File · append to a file · reminder · calendar · focus · daily summary and free time", legende: "Six actions, from files to a daily summary and free time." },
        { lines: ["The modules."], sub: "Music · calendar · reminders · weather · GitHub", legende: "Modules: music, calendar, reminders, weather, GitHub." },
        { lines: ["Local", "memory.", "Initiative."], legende: "Memory that stays on the Mac, and it speaks up on its own." },
        { lines: ["5 engines."], legende: "Five engines to choose from." },
        { lines: ["English", "and French."], sub: "Rebuilt settings.", legende: "In English and French, with rebuilt settings." },
      ],
      langues: ["English.", "Français."],
    },
    chiffres: {
      kicker: "03 · By the numbers",
      list: [
        { n: 206, label: "commits" },
        { n: 27000, label: "lines of Swift", about: true },
        { n: 778, label: "tests" },
        { n: 2, label: "public alphas" },
        { n: 6, label: "of the original code left", about: true, unit: "%" },
        { n: 1, label: "website" },
        { n: 4, label: "videos" },
        { n: 40000, label: "impressions, first LinkedIn post", about: true },
        { n: 11, label: "GitHub stars" },
      ],
      legendes: [
        "206 commits, about 27,000 lines of Swift, 778 tests.",
        "2 public alphas, about 6% of the original code left, a website.",
        "4 videos, about 40,000 impressions on the first post, 11 stars.",
      ],
    },
    comment: {
      kicker: "04 · How",
      avant: ["Several sessions", "in parallel."],
      apres: ["One coordinates", "and merges."],
      legendes: ["Several Claude Code sessions work in parallel.", "One coordinating session keeps the contracts and merges."],
    },
    suite: {
      kicker: "05 · What's next",
      retours: ["Feedback", "from the alpha."],
      agir: ["Read,", "then act."],
      agirSub: "A preview of the plan before acting.",
      citation: "“Plan my day.”",
      legendes: ["Next: feedback from the alpha.", "Then “read, then act”: plan my day, with a preview of the plan first."],
    },
    pied: { prises: "Real takes from the app (in French) · filming mode, sample data", branches: "Real branches from the repo" },
    fin: { alpha: "Free alpha." },
  },
};
