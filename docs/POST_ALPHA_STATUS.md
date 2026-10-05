# Yumi : état après l'alpha

Audit du 2026-10-05 sur `main` à e6d7620 (v0.1.0-alpha est taguée à d684e98). 726 tests Swift Testing, builds Yumi et YumiAppStore verts. Les audits de stabilisation (198e622) et de premier lancement (cc43d5a, d684e98) ne sont pas refaits ici : leurs conclusions sont reprises.

Alpha publiée en pre-release GitHub : zip signé avec un certificat local auto-signé « Yumi Local », sans notarisation (pas de compte Apple Developer). 8 téléchargements, 0 issue. Site sur GitHub Pages.

## 1. Ce que Yumi sait réellement faire

Vérifié dans le code et par les tests, build directe (hors App Store) :

| Domaine | Capacité réelle |
|---|---|
| Claude Code | Suit les sessions de tous les terminaux par hooks (relais Python lancé par `/bin/sh`), affiche activité et demandes de permission dans l'île, répond depuis l'encoche. |
| Chat | Passe par le Claude Code installé, réduit à des outils de lecture (`ChatTools` : Read, Glob, Grep, WebSearch, WebFetch, aucun MCP). Garde le fil, y compris les tours traités par l'agent. |
| Agent | Une demande devient un plan (Claude Code sans outil, sinon clé API Anthropic), validé (`PlanValidator`), chaque étape passe par `PermissionManager`, l'outil s'exécute, l'effet est vérifié, Yumi dit le résultat. |
| Outils | `create_file`, `append_to_file` (fichiers créés par Yumi seulement), `add_reminder`, `add_event`, `start_focus`, `get_today`, `get_current_time`, `get_current_context`. |
| Permissions | Allow, ask, deny ; une fois, session, ressource, projet ; expiration ; audit local ; planchers de risque fixes ; chemins secrets en critique ; accès macOS demandé par le `check` avant l'accord de Yumi. |
| Context Engine | App et fenêtre au premier plan, document, activité ; local, désactivable, envoyé au modèle seulement sur choix explicite. |
| Modules | Claude Code, GitHub (jeton), Musique, Focus, Notes et Rappels, Agenda, Météo. |
| Mémoire | Fichier `memoire.md` local, visible, modifiable, injecté dans le chat. |
| Personnage | États de l'agent (réflexion, travail, vérification, succès, erreur) reliés aux humeurs et poses existantes. |

## 2. Ce qui marche bien

- La séparation Runtime / UI : `AgentRuntime/` et `Permissions/` ne dépendent d'aucune vue ; l'île observe les événements (`AgentReaction`, `ApprovalReaction`).
- La porte unique : aucun outil ne s'exécute sans `PermissionManager`, le risque vient du code de l'outil (`Tool.action(for:)`), jamais du modèle.
- Le contrat d'outil : descripteur, schéma plat, `check` avant l'accord, `execute`, `verify`, `reply` écrit par le code.
- La défense contre l'injection : contexte et conversation balisés comme données, plan validé, tests dédiés (ChatSafetyTests, WriteToolsRefusalTests).
- Les fournisseurs de modèle interchangeables (`LLMProvider`, `FallbackLLMProvider`).

## 3. Partiel ou fragile

| Point | Pourquoi |
|---|---|
| Plans figés | Les arguments de chaque étape sont écrits avant l'exécution. Une étape ne peut pas utiliser le résultat d'une précédente, et il n'y a pas de replanification. Toute tâche « regarde puis agis » est impossible. |
| Lecture limitée | Aucun outil ne lit le calendrier au-delà d'aujourd'hui, ni un fichier, ni les rappels existants. `get_today` est un résumé en phrases, pas une donnée exploitable par un plan. |
| Mémoire hors agent | `memoire.md` nourrit le chat, pas le planificateur. |
| Historique | Les exécutions de l'agent ne vivent qu'en mémoire vive : rien à relire après redémarrage (seul l'audit des permissions persiste). |
| Coût et latence | Chaque message du chat déclenche d'abord un appel au planificateur. |
| Routage chat / agent | Décidé par le plan : un plan invalide pour une vraie action finit en conversation (sans risque, mais la réponse est floue). |
| Accords non mémorisables | Rappels et événements utilisent une ressource `unknown` : jamais couverts par un accord de session, donc une question à chaque fois. |
| Installation des hooks | Seulement dans la fenêtre Réglages, en anglais ; l'île ne signale pas leur absence. |
| Packaging | `scripts/release.sh` suppose la notarisation (notarytool) ; l'alpha réelle a été signée à la main avec « Yumi Local ». Pas de `docs/RELEASE.md`, pas de CHANGELOG. |
| Vérification Gatekeeper | Sans notarisation, chaque testeur doit passer par « Ouvrir quand même » ; c'est un frein direct au feedback. |

## 4. Prototypes

- Section Agent des réglages (`AgentDebugPanel`) : outil de développeur, visible.
- `ContextDebugPanel`, `IslandDemo`, mode tournage : outils internes.
- Pollers hérités de Coucou (Resend, n8n, Vercel, Stripe, Cal.com, Notion) : présents dans le code et les réglages, hors du positionnement agent.
- Initiative (remarques spontanées) : fonctionne, mais sans lien avec l'agent.

## 5. Le chemin Intent → Plan → Permission → Tool → Execution → Verification

| Étape | État | Trou |
|---|---|---|
| Intent | Message du chat ou des réglages. | Pas de clarification : une demande ambiguë devient conversation, jamais une question de Yumi. |
| Context | Snapshot attaché, envoyé au modèle seulement si choisi. | Pas de contexte calendrier, fichiers ou git exploitable par le planificateur. |
| Plan | Un seul appel, JSON validé. | Pas d'enchaînement de données entre étapes, pas de replanification après une observation. |
| Permission | Solide. | Une question par étape pour rappels et événements : trois rappels, trois questions (sauf regroupement par `upcoming`, limité aux ressources identifiées). |
| Execution | Délai, reprise pour les outils sûrs, jamais deux fois une écriture. | Pas d'annulation par l'utilisateur depuis le chat. |
| Verification | Par outil, indépendante. | Pas de vérification de l'objectif global (« la journée est-elle préparée ? »). |
| Result | Phrases écrites par les outils. | Pas de résumé structuré de mission, pas d'historique consultable. |

## 6. Le benchmark « Prépare ma journée de demain »

Aujourd'hui il échoue à coup sûr : aucun outil ne lit les rendez-vous de demain, et même avec un tel outil le plan ne pourrait pas choisir les plages libres, puisque ses arguments sont fixés avant toute lecture. C'est le goulot d'étranglement du produit : sans boucle observer puis planifier, chaque nouvel outil reste une action isolée.

## 7. Risques avant Browser et MCP

- Techniques : plans figés (le navigateur est par nature observer puis agir) ; pas de budget global de mission (étapes, durée, coût) ; pas d'historique persistant pour comprendre un échec.
- Sécurité : le contenu externe arrivera dans les résultats d'outils, pas seulement dans le contexte ; il faudra le baliser comme donnée à chaque replanification. `Read` et `WebFetch` du chat passent par l'encoche, hors `PermissionManager`. Pas de revue de sécurité complète (Keychain, logs, crash reports) depuis l'alpha.
- UX : trop de questions d'accord sur une mission à plusieurs étapes ; pas de vue « voilà ce que je vais faire » avant la première question.

## 8. Tests manquants

- Mission multi-étapes de bout en bout (lecture puis écriture dépendante).
- Benchmark suite 01 à 13 décrite comme données (entrée, plan attendu, permissions, vérification) et rejouable avec un modèle scripté.
- Injection venant d'une sortie d'outil (titre d'événement, contenu de fichier) relue par le planificateur.
- Performance : CPU au repos, mémoire, réveils (aucune mesure automatisée).
- Interface : aucun test UI ; l'île n'est vérifiée qu'à l'œil.

## 9. Architecture à préserver

- `AgentRuntime/` et `Permissions/` sans vue, sans `AppState`, compilés dans le bundle de tests.
- `PermissionManager` comme porte unique ; risque décidé par l'outil et les planchers de `RiskTable`.
- `PlanValidator` comme seul constructeur d'`AgentPlan`.
- `LLMProvider` abstrait ; Claude Code utilisé comme modèle sans outil.
- Le chat sans outil d'écriture (`ChatTools`).
- Le personnage ne contient aucune logique métier : il lit `AgentActivity`.

## 10. Priorités

| Priorité | Sujet | Classe |
|---|---|---|
| 1 | Boucle observer puis planifier : une étape peut s'appuyer sur ce qu'une lecture a rapporté, avec replanification bornée. | P1 |
| 2 | Outils de lecture structurés : rendez-vous d'un jour donné, plages libres, rappels ouverts, lecture d'un fichier créé par Yumi. | P1 |
| 3 | Aperçu du plan et accord groupé pour une mission (« voilà ce que je vais faire »), sans affaiblir le refus par étape. | P1 |
| 4 | Suite de benchmarks rejouable (01 à 13) avec modèle scripté, plus un passage réel manuel par release. | P2 |
| 5 | Distribution : `docs/RELEASE.md` et CHANGELOG fidèles au processus réel (signature « Yumi Local », sans notarisation), consignes Gatekeeper pour les testeurs. | P2 |

## Prochaine tâche unique

Permettre à un plan de lire puis d'agir : le Runtime exécute d'abord les étapes de lecture, rend leurs sorties au planificateur comme données balisées, puis valide un second plan d'action, avec au plus deux tours et les mêmes règles (validation, permissions, vérification). À livrer avec un seul outil de lecture structurée (`get_events` sur une date donnée, plages libres comprises) et le test de bout en bout du benchmark « prépare ma journée de demain » avec un modèle scripté.
