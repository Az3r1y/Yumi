# Yumi : stratégie de distribution

Diagnostic établi le 2026-10-08 sur l'état réel du dépôt (0.1.0-alpha.7, README alpha 5 réécrit, site `site/`, projet Remotion `motion/`, `docs/POST_ALPHA_STATUS.md`). Les chiffres GitHub (stars, forks, issues) n'ont pas pu être lus : `gh` n'est pas installé sur cette machine.

**Positionnement validé (2026-10-08), remplace les versions précédentes.**
- Message principal : *The little AI in your notch that asks before it acts.*
- Promesse : *Yumi does small things for you (reminders, calendar events, notes and more), shows you exactly what will change, waits for your click, then checks it really happened.*
- Preuve : demande, plan, contenu exact, permission, action réelle, vérification, avec le résultat visible hors de la notch (Rappels, Calendrier, Finder, Notion).
- Piliers : Lives in your notch, Does small things for you, Always asks first.
- Abandonné : « Your Mac has a new little friend » (piège Tamagotchi), « keeps you company », Claude Code comme identité, « control center for agents », habitudes animées (jamais la cigarette), toute promesse de contrôle total du Mac ou d'automatisation générale.
- Boucle de contenu : « Will Yumi do it? », les demandes du public testées face caméra (il le fait, il refuse, ou il ne sait pas encore et l'apprend dans une prochaine release via le modèle d'issue « new trick »).
- Les sections ci-dessous datent du premier diagnostic : en cas de désaccord, ce bloc fait foi.

---

## Étape 1 : analyse

### 1. Positionnement actuel
« A small companion that lives in the notch of your Mac. He shows what your AI agents are doing, asks before anything changes on your Mac, and keeps you company the rest of the day. »
Trois promesses dans une phrase : moniteur d'agents, garde-fou, compagnon. C'est honnête mais dilué. Le lecteur retient « encore une app d'encoche ».

### 2. Hook actuel
Le `demo.gif` : Claude Code demande `npm test`, on approuve depuis l'encoche. C'est le meilleur actif du repo, mais il montre la fonction la plus proche de Coucou (approbation Claude Code), pas la plus différenciante (Yumi agit lui-même, après un clic, puis vérifie).

### 3. Éléments à potentiel viral
- **Le moment « il demande avant »** : une carte qui montre exactement le fichier et son contenu avant création. Visuel, rassurant, inédit pour un agent.
- **La vérification** : « Je l'ai fait, et j'ai vérifié que c'est vraiment là. » Personne d'autre ne montre ça.
- **Le personnage dessiné en code** : slime, yeux qui suivent le curseur, habitudes (café, matcha) pendant qu'un agent travaille. Très « Reels ».
- **Le refus explicite** : « Supprime mon dossier Téléchargements » → Yumi refuse et explique pourquoi. Contre-pied parfait du discours « agents dangereux ».
- **Notion = risque haut** : une écriture hors du Mac est demandée à chaque fois, même si on a dit « toujours ». Argument sécurité concret.
- **Ollama : rien ne quitte le Mac.** Démo 100 % locale.
- **Release vérifiable** : build par GitHub Actions, attestation de provenance. Rare pour un indie, parle aux devs sécurité.

### 4. Trop technique pour la première impression
Tableau des moteurs, `PlanValidator`, planchers de risque, `shasum`/`gh attestation`, liste des permissions macOS, « 28 700 lignes, 820 tests », section build from source. Tout ça est un excellent second écran, mais pas un premier.

### 5. Ce qui rend Yumi difficile à comprendre
- Trois identités en une (moniteur, agent, compagnon). Il faut choisir laquelle on vend en premier.
- Le README commence par « small companion », alors que la vraie rupture est « il agit, mais demande ». Le safety model arrive après 150 lignes.
- Les actions disponibles sont modestes (fichier texte, rappel, événement, tâche Notion). Les présenter comme « agit sur ton Mac » sans les citer crée une déception à l'installation. Il faut être précis : petites actions, toujours visibles.
- « Open Anyway » au premier lancement : friction et méfiance, surtout pour un outil qui parle de sécurité.
- Pas de vidéo de 20 s qui montre le parcours complet demande → plan → clic → vérification.
- Héritage Coucou : si ce n'est pas dit clairement et tôt, quelqu'un le dira à ta place sur HN ou Reddit, et ce sera lu comme « clone ». À assumer dans une ligne (« built on Coucou's MIT notch app, then rebuilt around an agent runtime and a permission gate »).

### 6. Fonctionnalités qui méritent une vidéo
1. Demande → carte de plan → clic → fichier créé → « vérifié ».
2. Demande dangereuse → refus motivé.
3. Claude Code demande une permission → réponse depuis l'encoche (déjà le GIF).
4. Plusieurs sessions Claude Code visibles en direct (« 3/7 », « Edits X.swift »).
5. Tâche Notion : demande à chaque fois, même après « toujours ».
6. Mode Ollama hors ligne (Wi-Fi coupé à l'écran).
7. Le personnage : habitudes pendant qu'un agent travaille, scène GitHub (star reçue).
8. Glisser une fenêtre sur Yumi pour poser une question dessus.
9. L'historique des décisions (Réglages › Permissions).

### 7. Fonctionnalités qui peuvent devenir posts / releases
Chaque release alpha = un post « une capacité, une vidéo » : Notion high-risk (alpha 6), grille de contributions GitHub (alpha 7), ce que fait chaque session Claude Code (alpha 5). À venir : « read then act » (« prépare ma journée »), modules externes déclaratifs, notarisation, Macs sans encoche. Chacun est un événement de distribution, pas seulement un tag.

### 8. Pourquoi star
- Un agent qui demande avant d'agir et vérifie après : idée qu'on veut soutenir.
- Swift 6 natif, zéro dépendance, 820 tests : signal de qualité.
- Pas de compte, pas de télémétrie, build attesté.
- Le personnage est mignon. Ça compte.

### 9. Pourquoi fork
- Ajouter un outil (le contrat d'outil `check / execute / verify / reply` est propre et réutilisable).
- Ajouter un module d'île (la liste existe, le modèle est clair).
- Étudier un Permission Gate réel pour son propre agent.
- Changer le personnage / la skin.
- Ajouter un moteur (Mistral, LM Studio).

### 10. Pourquoi installer
- Utilisateurs Claude Code : voir et approuver toutes les sessions sans changer de fenêtre. C'est le besoin le plus immédiat, la porte d'entrée.
- Curieux d'agents mais méfiants : essayer un agent qui ne peut rien casser.
- Possesseurs de MacBook à encoche qui veulent « un truc vivant » dedans.

---

## Étape 2 : positionnement

### A. « The AI that asks before it touches your Mac »
- **Tagline** : *An AI companion that can act on your Mac, and always asks first.*
- **Présentation** : Yumi vit dans l'encoche. Tu demandes, il prépare un plan, te montre exactement ce qui va changer, attend ton clic, agit, puis vérifie.
- **Cible** : devs et power users curieux des agents mais méfiants.
- **Hook** : la carte d'approbation + « vérifié ».
- **Différence avec Coucou** : Coucou montre et relaie des agents tiers. Yumi a son propre agent, son runtime, son gate et sa vérification.
- **Avantage** : thème « confiance » très actuel, compréhensible par des non-devs, différenciant.
- **Risque** : promesse plus grande que le catalogue d'actions actuel (fichiers texte, rappels, événements). À cadrer par la précision.

### B. « Mission control for Claude Code, in your notch »
- **Tagline** : *See and approve every Claude Code session from your notch.*
- **Présentation** : toutes tes sessions, ce qu'elles font, et leurs demandes de permission, sans quitter ce que tu fais.
- **Cible** : utilisateurs intensifs de Claude Code.
- **Hook** : 3 terminaux qui tournent, une seule encoche qui résume tout.
- **Différence avec Coucou** : faible. C'est le terrain le plus proche de Coucou.
- **Avantage** : besoin immédiat, communauté identifiée, conversion rapide.
- **Risque** : être perçu comme un clone ; dépendance à un seul outil tiers.

### C. « A companion with hands »
- **Tagline** : *I gave my AI companion hands, and a conscience.*
- **Présentation** : un petit être vivant dans ton Mac qui te tient compagnie, suit tes agents et peut faire des choses pour toi, toujours avec ta permission.
- **Cible** : grand public tech, créateurs, TikTok/Reels.
- **Hook** : le personnage + un geste concret.
- **Différence avec Coucou** : personnage, voix, initiative, mémoire.
- **Avantage** : le plus partageable visuellement.
- **Risque** : perçu comme gadget ; ne convertit pas en contributeurs.

### Recommandation (révisée le 2026-10-08) : C en tête, pour tout le monde
Décision : Yumi s'adresse à tout le monde, pas d'abord aux devs. L'accroche doit être mignonne, donner envie et faire cliquer. Le petit nombre de modules n'est pas une faiblesse : Yumi apprend vite, et chaque nouveau module devient une nouvelle raison d'en parler.

> **Your Mac has a new little friend.**

Sous-titre : *Yumi lives in your notch, helps with your day, and always asks before touching anything. He learns new tricks every week.*

En français : **« Ton Mac a un nouveau petit ami. »** / *« Yumi vit dans l'encoche, t'aide au quotidien et demande toujours avant de toucher à quoi que ce soit. Il apprend de nouveaux tours chaque semaine. »*

Variantes pour les vidéos :
- « Il y a quelqu'un qui vit dans mon Mac. »
- « Il est petit, il est mignon, et il demande toujours la permission. »
- « Cette semaine, Yumi a appris à… » (format récurrent, une compétence par post)

Logique : le personnage attire (C), « il demande toujours » rassure tout le monde, y compris les non-devs (A), et Claude Code devient un module parmi d'autres pour les devs (B), plus le message principal. « De nouveaux tours chaque semaine » transforme la vitesse de développement en rendez-vous : chaque module est un épisode.

---

## Étape 3 : distribution par canal

| Canal | Type de contenu | Fréquence | Hook | Format | CTA | Objectif |
|---|---|---|---|---|---|---|
| **GitHub** | README réordonné, releases avec vidéo, issues `good first issue`, Discussions | Chaque release + tri hebdo | La phrase A + GIF du parcours complet | README, release notes avec MP4 | Star, installer, ouvrir une Discussion | Conversion et rétention |
| **X** | Clips 15-30 s, threads de build, réponses dans les fils Claude Code | 3-4 posts/sem. | « Mon agent m'a demandé avant de créer un fichier » | Vidéo native + 1 lien en réponse | Lien repo en réponse | Découverte devs, communauté Claude Code |
| **LinkedIn** | Récit de construction, angle confiance / IA responsable | 1/sem. | « Pourquoi j'ai mis un Permission Gate entre l'IA et mon Mac » | Texte + vidéo carrée | Lien en commentaire | Crédibilité, recruteurs, devs FR |
| **TikTok** | Démos face écran, personnage | 3/sem. pendant 3 sem., puis 2 | « Mon Mac a un petit habitant » / « je lui demande de tout supprimer » | Vertical 15-25 s, texte à l'écran, son | « Lien dans la bio, gratuit, open source » | Portée large, effet waouh |
| **Reels** | Même clips que TikTok | Republication | Idem | Idem | Idem | Portée sans effort supplémentaire |
| **YouTube Shorts** | Mêmes clips + 1 vidéo longue (5 min) au jour 21 | Republication + 1 long | « Construire un agent qui ne peut rien casser » | Vertical + horizontal | Lien en description | Recherche long terme |
| **Reddit** | Post de lancement, puis réponses utiles | 1 post par sub, une fois ; commentaires au fil de l'eau | « I built a macOS agent where the model can only propose » | Texte + GIF, transparence Coucou | Feedback demandé, pas de « star please » | Feedback qualifié, premiers contributeurs |
| **Communautés Claude Code / agents / macOS** | Discord Anthropic, r/ClaudeAI, communautés MCP, forums Swift | Ponctuel, quand utile | « Approuver Claude Code depuis l'encoche » | Message court + GIF | Repo | Utilisateurs cœur de cible |
| **Product Hunt** | Lancement unique | Une fois, après notarisation ou en assumant l'alpha | Phrase A | Galerie 5 visuels + vidéo 40 s | Download | Pic de visibilité, backlinks |
| **Hacker News** | Show HN | Une fois, un mardi/mercredi 15h-16h FR | « Show HN: Yumi, a macOS agent that asks before changing anything » | Lien repo, premier commentaire technique | Discussion | Devs seniors, stars en masse |

Règles : ne jamais poster sans vidéo réelle ; Reddit et HN demandent l'honnêteté (alpha, non notarisé, base Coucou) dès le premier commentaire ; Product Hunt et HN à des semaines différentes.

---

## Étape 4 : content engine (24 idées)

| # | Hook | Démonstration | Durée | Plateforme | CTA | Fonction |
|---|---|---|---|---|---|---|
| 1 | « Je demande à mon Mac de créer un fichier. Il me demande d'abord. » | « Crée todo.md avec deux tâches » → carte avec contenu exact → clic → fichier dans le Finder → « vérifié » | 20 s | TikTok, X | Lien bio | Agent + Gate + Verify |
| 2 | « J'ai demandé à mon IA de vider mes Téléchargements. » | Demande destructive → refus motivé | 12 s | TikTok, X | « Open source, lis le code du refus » | Refus, liste deny |
| 3 | « Trois Claude Code en parallèle. Une seule encoche. » | 3 terminaux + île qui résume « 3/7 », « Runs swift test » | 25 s | X, r/ClaudeAI | Repo | Module Claude Code |
| 4 | « Claude veut lancer une commande. Je réponds sans quitter Figma. » | Permission Claude Code → Allow depuis l'encoche | 15 s | X, LinkedIn | Download | Hooks, approbation |
| 5 | « Même si je clique "toujours", il redemande. Exprès. » | Tâche Notion → Always → nouvelle demande quand même | 20 s | X, LinkedIn | Lire le safety model | Notion high risk |
| 6 | « Wi-Fi coupé. Mon assistant marche encore. » | Coupe le Wi-Fi, Ollama, crée un rappel | 20 s | TikTok, Reddit r/LocalLLaMA | Repo | Ollama |
| 7 | « Mon agent travaille. Mon compagnon boit un matcha. » | Session Claude Code, habitude animée | 10 s | TikTok, Reels | Lien bio | Personnage |
| 8 | « Quelqu'un a star mon repo. Regarde sa réaction. » | Scène GitHub déclenchée | 8 s | X, TikTok | « Fais-le réagir » (star) | Module GitHub, scène |
| 9 | « Il m'a dit de faire une pause. Il avait raison. » | Initiative après 2 h | 12 s | Reels | Lien bio | Initiative |
| 10 | « Je glisse une fenêtre sur lui et je pose une question. » | Drag d'une fenêtre sur Yumi | 15 s | X | Download | Context Engine |
| 11 | « Ce que mon IA sait de moi : un fichier texte que je peux effacer. » | Ouvre memoire.md, efface une ligne | 15 s | LinkedIn, X | Repo | Mémoire locale |
| 12 | « Le modèle propose. Le code décide. » | Schéma animé Remotion du pipeline | 30 s | LinkedIn, X, Shorts | Lire le safety model | Runtime |
| 13 | « Tout ce qu'il a fait, et tout ce que j'ai refusé. » | Historique Réglages › Permissions | 15 s | LinkedIn | Repo | Audit |
| 14 | « Bloque jeudi 14 h. Sans inviter personne, jamais. » | add_event, carte, vérif dans Calendrier | 18 s | TikTok, X | Lien bio | add_event |
| 15 | « Combien de temps libre j'ai demain ? » | Lecture seule, réponse, aucune question | 12 s | Reels | Lien bio | get_today |
| 16 | « Mon IA n'a pas de compte. Pas de serveur. Voilà comment je le prouve. » | Little Snitch / moniteur réseau pendant usage | 30 s | X, HN commentaire | Repo | Privacy |
| 17 | « Cette app est buildée par GitHub, pas sur mon Mac. Vérifie toi-même. » | `gh attestation verify` | 20 s | X | Release | Provenance |
| 18 | « Un seul fichier Swift pour ajouter un outil à mon agent. » | Écran code du contrat d'outil, check/execute/verify | 45 s | X, YouTube | « Ajoute le tien » | Tool contract |
| 19 | « Je change de modèle sans changer de sécurité. » | Même demande via Claude, GPT, Gemini, Ollama : même carte | 25 s | X, Reddit | Repo | LLMProvider |
| 20 | « Mon personnage est dessiné en code. Zéro image. » | Timelapse SwiftUI du slime | 20 s | TikTok, X | Repo | Personnage |
| 21 | « Il m'aide à pousser mon code et il me montre mon graphe. » | Grille de contributions dans l'île | 10 s | X | Download | GitHub grid |
| 22 | « Avant / après : un agent qui agit vs un agent qui demande. » | Split screen | 20 s | LinkedIn, TikTok | Lien | Positionnement |
| 23 | « Vous avez demandé, je l'ai codé : [feature de la communauté]. » | Issue → démo | 20 s | X, GitHub release | « Ouvre une issue » | Boucle communauté |
| 24 | « Prépare ma journée. » (quand read-then-act sort) | Lecture agenda → plan multi-étapes → une approbation groupée | 30 s | Partout, release majeure | Download | Roadmap |

---

## Étape 5 : boucle open source

| Étape | Déclencheur concret |
|---|---|
| Contenu → GitHub | Chaque vidéo se termine sur le nom « Yumi » et `github.com/estebanbaigts/Yumi` à l'écran ; lien en premier commentaire/bio. Une seule destination. |
| GitHub → installation | Le haut du README = phrase A + vidéo + un bouton Download. L'étape « Open Anyway » expliquée avec une capture, et une phrase sur pourquoi (pas de compte Apple payant). |
| Installation → utilisation | Premier lancement : Yumi propose une première demande sûre (« Crée hello.md sur ton bureau ») pour vivre le moment Gate en 30 s. Et propose les hooks si Claude Code est détecté. *(changement produit léger, onboarding, à discuter)* |
| Utilisation → star | Le personnage réagit aux stars (scène existante). Dans le README : « Star the repo and watch Yumi react. » La star devient un jeu, pas une aumône. |
| Star → issue | Bouton « Send feedback » déjà là (Tally). Ajouter des templates d'issue : « Tool request », « Module request », « Bug ». Le feedback Tally est recopié en issues publiques (anonymisé) pour montrer que ça vit. |
| Issue → contribution | 5 à 8 issues `good first issue` bien décrites (nouveau module météo, traduction, moteur LM Studio, test). `CONTRIBUTING.md` avec « Add a tool in 1 file » et « Add a module ». |
| Contribution → fork | Les forks viennent naturellement des contributions ; encourager aussi les « skins » du personnage et les modules perso. |
| Fork → nouveau contenu | Chaque PR mergée = un post « Yumi peut maintenant X, merci @contributeur » (idée 23). Les contributeurs repartagent. La boucle se referme. |

---

## Étape 6 : plan 30 jours (environ 1 h/jour, 2-3 h les jours de lancement)

**Semaine 1 : préparer le terrain (pas de lancement)**
- J1 : valider la phrase A. Réordonner le haut du README (Claude Code le fait). Une ligne d'attribution Coucou visible.
- J2 : enregistrer 4 clips bruts (idées 1, 2, 3, 7). Écran propre, police grosse, 1080p.
- J3 : monter les 4 clips (Remotion `motion/` pour les sous-titres et la fin standard).
- J4 : templates d'issues, 6 `good first issue`, Discussions activées, topics GitHub, description et social preview.
- J5 : site : même phrase, même vidéo. Premier post X (clip 1) pour tester le hook.
- J6-7 : repos. Observer les réactions au clip 1.

**Semaine 2 : lancement communautés**
- J8 : r/ClaudeAI (clip 3, angle sessions + approbation).
- J9 : TikTok/Reels/Shorts clip 1.
- J10 : X clip 2 (refus). LinkedIn : récit « pourquoi un Permission Gate ».
- J11 : répondre à tout, transformer les retours en issues.
- J12 : TikTok clip 7. r/macapps.
- J13 : Show HN (mardi ou mercredi) si les retours Reddit n'ont pas révélé de bug bloquant. Bloquer 3 h pour répondre.
- J14 : repos.

**Semaine 3 : rythme**
- J15 : release alpha.8 avec ce qui est corrigé grâce aux retours, vidéo dans les notes.
- J16-20 : 1 clip par jour ouvré (idées 5, 6, 10, 14, 19), recyclés sur toutes les plateformes verticales.
- J21 : vidéo YouTube 5 min « J'ai construit un agent qui ne peut rien casser ».

**Semaine 4 : communauté**
- J22 : r/LocalLLaMA (clip 6, Ollama).
- J23 : post « merci aux premiers contributeurs » (idée 23).
- J24-27 : 3 clips (idées 8, 12, 18), LinkedIn hebdo.
- J28 : bilan chiffré (stars, installs via téléchargements de release, issues). Décider Product Hunt (idéalement après notarisation).
- J29-30 : planifier le mois 2 autour de « read then act ».

---

## Étape 7 : priorités

| Prio | Tâche | Impact | Effort | Raison | Dépendances |
|---|---|---|---|---|---|
| P0 | Fixer la phrase de positionnement | Très haut | 15 min | Tout le reste en découle | Aucune |
| P0 | Nouveau haut de README (phrase, vidéo du parcours complet, Download, attribution Coucou) | Très haut | 1-2 h | Premier écran de chaque visiteur | Phrase, vidéo |
| P0 | Enregistrer la vidéo « demande → plan → clic → vérifié » | Très haut | 1-2 h | L'actif n°1, n'existe pas encore | Aucune |
| P0 | Description, topics, social preview du repo | Haut | 20 min | Aperçu partout où le lien est collé | Phrase |
| P1 | 4 clips courts montés | Haut | 3 h | Carburant de 2 semaines | Vidéo P0 |
| P1 | Templates d'issues + 6 good first issues + Discussions | Haut | 1 h | Sans ça, l'intérêt ne se convertit pas | Aucune |
| P1 | CONTRIBUTING « Add a tool / a module » | Moyen-haut | 1 h | Ouvre la porte aux forks utiles | Aucune |
| P1 | Post r/ClaudeAI + premier post X | Haut | 1 h | Test du message sur la cible cœur | Clips |
| P1 | Page « Open Anyway » claire avec capture | Moyen | 30 min | Réduit l'abandon à l'installation | Aucune |
| P2 | Show HN | Très haut (variance) | 3 h le jour J | Une seule chance, à faire avec un produit rodé | Retours Reddit corrigés |
| P2 | Onboarding « première demande sûre » | Haut | 0,5-1 j de code | Fait vivre le Gate dès la minute 1 | Décision produit |
| P2 | Notarisation | Très haut | 99 $/an | Supprime la plus grosse friction | Budget (aucun au 2026-10-03) |
| P2 | Product Hunt | Moyen | 1 j | Mieux après notarisation | Notarisation |
| P2 | Vidéo YouTube longue | Moyen | 4 h | Découverte long terme | Clips |
| P2 | Release « read then act » comme lancement n°2 | Très haut | Dev en cours | Démo la plus forte possible | Roadmap |

---

## Qui fait quoi

### Toi (non automatisable)
- Valider la phrase de positionnement.
- Enregistrer les démos à l'écran (ta voix, ton Mac, ta vraie utilisation).
- Publier sur X, LinkedIn, TikTok, Instagram, YouTube, Reddit, HN, Product Hunt (comptes, envoi).
- Répondre aux commentaires, surtout HN et Reddit, en personne.
- Décider du budget Apple Developer.
- Choisir quelles idées de la communauté deviennent des features.

### Claude Code (automatisable, sur demande)
- Réécrire le haut du README et le site `site/` avec la nouvelle phrase, sans toucher au produit.
- Rédiger CONTRIBUTING « Add a tool / Add a module », les templates d'issues, et les 6 good first issues (texte prêt à coller, ou création via `gh` une fois installé).
- Monter les clips dans `motion/` (Remotion) : sous-titres, carte de fin standard, formats 9:16 / 1:1 / 16:9, à partir de tes enregistrements bruts.
- Générer les animations explicatives (idée 12, pipeline du safety model) entièrement en Remotion.
- Écrire les brouillons de chaque post (X, LinkedIn, Reddit, Show HN avec premier commentaire technique) à partir de chaque release.
- Rédiger les release notes « une capacité, une vidéo » à chaque tag.
- Ajouter au workflow de release l'upload de la vidéo et la génération du changelog.
- Préparer (si tu valides) le petit onboarding « première demande sûre ».
- Un tableau hebdo des stars / téléchargements de release (après installation de `gh`).
