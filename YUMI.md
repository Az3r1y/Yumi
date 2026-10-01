# Yumi : décisions et répartition du travail

Contrat partagé entre les trois sessions de travail. Lire aussi `ARCHITECTURE.md`. En cas de désaccord entre les deux, ce fichier fait foi.

## Origine du code

- Ce dépôt (`estebanbaigts/Yumi`) est le seul endroit où l'on travaille et où l'on pousse.
- Le code de départ est celui de l'application macOS de Coucou (MIT, Louis Raillé), importé dans `Yumi/` sans ses créations protégées : ni icônes, ni sons, ni médias, ni prototypes. Voir `ATTRIBUTION.md`.
- Le clone local de Coucou (`/Users/thewise/coucou`) sert uniquement de référence en lecture. On n'y modifie rien.
- `ARCHITECTURE.md` décrit Coucou tel qu'il était. Ses chemins `NotchBuddy/...` correspondent ici à `Yumi/...`.
- La première version de Yumi (moteur d'événements typé, sessions multiples, 26 tests) est conservée sur la branche `legacy-v0`. Elle pourra être reprise plus tard pour la gestion multi-session.

## Décisions

| Sujet | Décision |
|---|---|
| Nom de l'application | Yumi |
| Nom du personnage | Yumi |
| Design du personnage | Concept 4, « Le Slime Graphique » (`design/yumi/concepts-4-et-6.webp`, moitié gauche) |
| Cohabitation avec Coucou | Non. Yumi remplace Coucou : à l'installation des hooks, Yumi retire aussi les anciens hooks Coucou et NotchBuddy. |
| Target App Store | Plus tard. Le target et les blocs `#if APPSTORE` restent en place et doivent continuer à compiler, sans travail spécifique. |
| Windows et Linux | Plus tard. Le portage Windows de Coucou n'a pas été importé. |
| Identifiant de bundle | `app.yumi` (repris de la première version de Yumi). Target App Store : `app.yumi.appstore`. |
| Équipe de signature | À fournir avant la première release. Le build Debug n'est pas signé et n'en a pas besoin. |

## Valeurs d'identité (à utiliser telles quelles)

| Élément | Valeur Coucou | Valeur Yumi |
|---|---|---|
| Nom du produit | `Coucou` | `Yumi` |
| Service Keychain | `fr.louisraille.NotchBuddy` | `app.yumi` |
| Dossier de support | `Application Support/NotchBuddy` | `Application Support/Yumi` |
| Socket | `nb.sock` | `yumi.sock` |
| Script de hook | `nb-hook` | `yumi-hook` |
| Script de hook App Store | `~/.claude/coucou/nb-hook` | `~/.claude/yumi/yumi-hook` |
| Dossier de logs | `Logs/NotchBuddy` | `Logs/Yumi` |
| Message de refus | `Denied from Coucou` | `Denied from Yumi` |
| Reconnaissance de ses propres hooks | sous-chaîne `NotchBuddy` ou `coucou` | égalité avec la commande exacte générée par Yumi |
| Hooks hérités à retirer | sans objet | toute commande contenant `NotchBuddy` ou `coucou` |

Le chemin du conteneur sandbox dans le script App Store doit être dérivé de l'identifiant de bundle, pas écrit en dur.

## Design de Yumi (concept 4)

Lecture de la planche, à traduire dans les trois moteurs de rendu (`BotEngine`, `GreetingCanvasView`, `UploadCanvasView`) :

- **Corps** : dôme noir, sommet arrondi, base plus large et presque plate. Ce n'est plus la superellipse symétrique de Mochi.
- **Yeux** : deux grands ovales blancs, pupille noire ronde avec un petit reflet blanc. Les pupilles portent le regard (elles suivent la souris).
- **Lumière de contour** : liseré dégradé bleu, violet, rose le long du bord, plus marqué en bas et sur les côtés.
- **Palette approximative** (relevée à l'œil, à ajuster) : noir `#0B0F1A`, indigo `#2A2A8C`, bleu `#5B8CFF`, violet rosé `#C77DFF`, blanc `#FFFFFF`.
- **Expressions de la planche** : neutre, heureux, curieux, concentré, réfléchi, sommeil, inquiet, confus, agacé, surpris, paniqué, clin d'œil. Elles passent par les paupières et la position des pupilles.
- **Poses** : saut, étirement, écrasement, secousse, célébration (petits bras), sommeil (aplati).

Deux contraintes propres à l'application, absentes de la planche :

1. **L'île est noire.** Un corps noir sur fond noir est invisible : la silhouette doit être portée par la lumière de contour et par les yeux, y compris en mode compact (diamètre 20 pt) et pour les mini-personnages (12 pt).
2. **La couleur d'état.** Mochi change la teinte de son corps selon l'état (bleu au travail, violet en réflexion, ambre pour une approbation, rouge en erreur, vert quand c'est fini). Pour Yumi, le corps reste noir et c'est la lumière de contour qui prend la couleur de l'état. Au repos, elle garde le dégradé bleu, violet, rose. Les mini-personnages des intégrations portent la couleur de leur marque sur le contour.

Correspondance proposée entre les états existants et les expressions de la planche :

| État ou émote du code | Expression Yumi |
|---|---|
| `idle` | neutre |
| `working` | concentré |
| `thinking` | réfléchi |
| `searching` | curieux |
| `approval` | surpris |
| `question` | curieux, tête penchée |
| `error` | inquiet |
| `finished`, émote `happy`, `proud` | heureux, pose célébrer |
| `ratelimit` | paniqué |
| `sleeping`, émote `yawn` | sommeil |
| `dizzy` | confus |
| émote `annoyed` | agacé |
| émote `wink` | clin d'œil |
| émote `love`, `surprised` | à dessiner dans le même style |

## Répartition des fichiers

Un fichier n'appartient qu'à une seule session. Les fichiers Swift sont dans `Yumi/Sources/App/`. Personne ne renomme de type ni de fichier partagé : ces renommages se font à la fin, après fusion.

| Session | Branche | Fichiers possédés |
|---|---|---|
| 1. Identité et hooks | `yumi/identite` | `HookServer.swift`, `ClaudeService.swift`, `AppDelegate.swift`, `SettingsView.swift`, `FileDropView.swift`, `N8nPoller.swift`, `IslandViewContent.swift`, `IslandTypes.swift`, `IslandWindowController.swift`, nouveau `AppIdentity.swift` |
| 2. Personnage et créations | `yumi/personnage` | `BotEngine.swift`, `BotCanvasView.swift`, `GreetingCanvasView.swift`, `UploadCanvasView.swift`, `UploadSequenceEngine.swift`, `Yumi/Assets.xcassets/` (vide : icônes à créer), `Yumi/Resources/sounds/` (vide : 28 sons à créer) |
| 3. Build, docs, licence | `yumi/build-docs` | `Yumi/project.yml`, `Yumi/Resources/*.entitlements`, `scripts/` (script de release à écrire), `.github/`, `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `ATTRIBUTION.md`, `LICENSE`, `docs/` (site à écrire), nouveau target de tests |

Fichiers que personne ne touche pendant le travail en parallèle : `NotchBuddyApp.swift`, `AppState.swift`, `IslandStateMachine.swift`, `IslandRootView.swift`, les autres pollers, `WindowContextCapture.swift`, `ARCHITECTURE.md`, `YUMI.md`.

## Règles communes

- Le `.xcodeproj` et les `Info.plist` sont générés : lancer `cd Yumi && xcodegen` avant de compiler, ne jamais les éditer.
- Compiler en Debug avant chaque commit : `cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug build`.
- État de référence : le build Debug réussit sur `main` avec 19 avertissements (concurrence et API dépréciées). Ne pas en ajouter.
- Chaque session pousse sur sa propre branche, jamais sur `main`.
- Ne jamais copier d'icône, de son ou de média depuis Coucou : le dépôt est public.
- Conserver `LICENSE` avec le copyright d'origine.

## Après fusion des trois branches

1. Renommages internes : `NotchBuddyApp`, `MochiConst`, `mochiPath`, `drawMochi`, l'état `.coucou`, le préfixe `notchBuddy.` des notifications.
2. Recette manuelle complète (étape 7 de `ARCHITECTURE.md`).
