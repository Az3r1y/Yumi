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

## Phase 3 : île repliée vivante, chat sans facture

La phase 2 est terminée et fusionnée : personnage, île et cœur sont dans `main`. La répartition des fichiers de la phase 2 reste valable. Deux chantiers, deux sessions.

Décisions prises en voyant l'app réelle :

- **Taille de l'île** : on garde celle de `main` (échelle 1,4 par rapport à la maquette). La maquette reste la référence pour les proportions et le mouvement, plus pour la taille.
- **L'approbation depuis la notch fonctionne** de bout en bout (testée le 1er octobre 2026 avec le script de hook).

### Chantier A, session Cœur : le chat passe par Claude Code

Aujourd'hui le chat appelle l'API avec une clé facturée à l'usage et ne sait que répondre par du texte. Il doit piloter le Claude Code installé sur le Mac : plus de facture à l'usage (l'abonnement de l'utilisateur), et la capacité d'agir (créer des fichiers, lancer des commandes, coder dans un dossier). Les demandes de permission passent par la notch, jamais contournées.

L'interface vue par l'île ne change pas : `ClaudeService.shared.chat(query:context:state:)`, `clearConversation()`, et les réponses dans `AppState.chatHistory`.

### Chantier B, sessions Cœur puis Île : l'île repliée montre ce qui est vivant

Le contrat `Contracts/ModuleTypes.swift` a gagné `ModuleSnapshot.live` (texte court, priorité, deux boutons au plus). Le cœur le renseigne, l'île repliée affiche le module vivant de plus haute priorité et ses boutons au survol. Priorités : quelqu'un attend une réponse, puis ce qui tourne (musique, focus), puis ce qui est bon à savoir (prochain rendez-vous).

### Chantier C, sessions Cœur puis Île : le chat en direct

Les chantiers A et B sont terminés et fusionnés. Le chat crée des fichiers et lance des commandes, mais on ne le voit pas faire : la réponse arrive d'un bloc. Le contrat `Contracts/ChatLive.swift` et `AppState.chatLive` décrivent la réponse en cours : le texte qui s'écrit mot à mot, l'action en cours (lit, écrit, lance) avec un aperçu, et les actions déjà faites. Le cœur le renseigne en continu, l'île l'affiche en direct, ouverte comme repliée.

Le dossier de travail du chat devient le dossier Téléchargements de l'utilisateur, pour que les fichiers créés y arrivent directement.

## Phase 2 : porter la maquette, répartition des fichiers

Trois sessions en parallèle. Un fichier n'appartient qu'à une seule session. Les fichiers Swift sont dans `Yumi/Sources/App/`. Chaque session peut créer de nouveaux fichiers dans son propre sous-dossier.

| Session | Branche | Fichiers possédés |
|---|---|---|
| Personnage | `yumi/personnage` | `BotEngine.swift`, `BotCanvasView.swift`, nouveau dossier `Character/` |
| Île | `yumi/ile` | `IslandRootView.swift`, `IslandViewContent.swift`, `IslandTypes.swift`, `IslandWindowController.swift`, `IslandStateMachine.swift` et ses tests, `GreetingCanvasView.swift`, `UploadCanvasView.swift`, `UploadSequenceEngine.swift`, `FileDropView.swift`, `SettingsView.swift`, `SoundEngine.swift`, nouveau dossier `Island/` |
| Cœur | `yumi/coeur` | `AppState.swift`, `AppDelegate.swift`, `AppIdentity.swift`, `HookServer.swift`, `ClaudeService.swift`, `WindowContextCapture.swift`, tous les `*Poller.swift`, `Yumi/project.yml`, nouveaux dossiers `Core/` et `Modules/`, nouveaux fichiers de tests |

### Les contrats entre sessions

Deux fichiers dans `Contracts/` sont déjà sur `main` et servent d'interface. **Personne ne les modifie pendant le travail en parallèle** ; si un contrat doit changer, on s'arrête et on le décide ensemble.

- `Contracts/CharacterCommands.swift` : l'île commande le personnage par notifications (`yumiPose`, `yumiHabit`, `yumiMood`, `yumiRim`, `yumiLit`, `yumiGaze`). La session Personnage les écoute, la session Île les émet. L'île ne touche jamais au moteur du personnage, et le place où elle veut à la taille qu'elle veut avec `BotCanvasView`.
- `Contracts/ModuleTypes.swift` : le cœur remplit `AppState.modules` avec des `ModuleSnapshot`, l'île les dessine. Les cinq premiers vont dans l'île, les suivants dans le second carré. L'île signale un clic par la notification `moduleAction`. `AppState.modules` contient des données d'exemple tant que le cœur ne les remplace pas.

### Premiers modules réels

Claude Code, Agenda, Notes et rappels, Focus, Musique, Météo. Ils se branchent sur le Mac sans compte externe. Notion, n8n, Make et ChatGPT viennent ensuite.

### La maquette est la source

`design/yumi/maquette/reference.html` contient les formules exactes : le contour du corps (`bodyPath`), les ressorts et leurs constantes (`Blob`), chaque pose (`POSE_FX`), chaque habitude (`SCENES`), les visages (`MOODS`), les couleurs de liseré (`RIMS`), les places de Yumi (`SEATS`) et la chronologie du lancement (`launch`). On porte ces valeurs, on ne les réinvente pas.

## Règles communes

- Le `.xcodeproj` et les `Info.plist` sont générés : lancer `cd Yumi && xcodegen` avant de compiler, ne jamais les éditer.
- Compiler en Debug avant chaque commit : `cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug build`.
- État de référence : le build Debug réussit sur `main` avec 19 avertissements (concurrence et API dépréciées). Ne pas en ajouter.
- Chaque session pousse sur sa propre branche, jamais sur `main`.
- Quand un rendu est porté, le comparer à la maquette ouverte dans un navigateur.
- Ne jamais copier d'icône, de son ou de média depuis Coucou : le dépôt est public.
- Conserver `LICENSE` avec le copyright d'origine.

## Direction produit et maquette de référence

Yumi est un compagnon généraliste, pour le travail comme pour la vie. Trois gestes le définissent : il veille (il ne se manifeste que quand on est concerné), il reçoit (un fichier, une fenêtre, une phrase), il répond (sur place).

La maquette validée est `design/yumi/maquette/reference.html` (à ouvrir dans un navigateur). C'est la référence visuelle et de mouvement pour le portage en Swift. Les fichiers `ile-v1` à `ile-v8` sont l'historique des essais.

Décisions validées sur cette maquette :

| Sujet | Décision |
|---|---|
| Taille | Île ouverte de 480 points de large, aussi basse que le contenu le permet (environ 150). |
| Mise en page | Yumi à gauche, une seule information à droite, trois boutons (accueil, parler, déposer). |
| Modules | Catalogue de 40, dix au plus. Les cinq premiers dans l'île, les autres dans un second carré détaché sous l'île. |
| Apparence des modules | Par leur nom en toutes lettres, précédé de leur couleur. Pas d'abréviations. |
| Corps | Souple : hauteur et inclinaison sont des ressorts, le contour est recalculé à chaque image. Corps de la couleur exacte de l'île. |
| Volume | Les yeux sont posés sur une sphère (la tête tourne), reflet et éclat mobiles, lumière qui déborde à l'intérieur du contour. |
| État | Porté par la couleur du liseré, jamais par le corps. |
| Poses | Saut, étirer, s'écraser, secouer, célébrer. |
| Habitudes | Clope (agent au travail), épuisé, café, casque (musique), lunettes (réussite), nuage (erreur), sifflote (attente), dodo (inactif). La cigarette doit pouvoir être désactivée. |
| Lancement | Une goutte sous la notch, deux yeux endormis dans le noir, ils s'ouvrent et regardent autour, l'île s'ouvre, la lumière s'allume et le contour se dessine, salut, nom, modules, clin d'œil, repli. Environ 5 secondes. |
| Débordement | Yumi est dessiné au-dessus de l'île : gouttes, fumée et poses peuvent dépasser sur les côtés et en bas, jamais au-dessus du bord supérieur de l'écran. |
| Langue et ton | Interface en français, Yumi tutoie et parle court. |

Conséquence pour le code : les sept intégrations câblées en dur et la tâche Claude unique doivent laisser la place à un système de modules. Le moteur d'événements typé de la branche `legacy-v0` est la fondation prévue.

## État au 1er octobre 2026

Les trois branches ont été fusionnées dans `main` et les renommages internes sont faits (`YumiApp`, `YumiConst`, `yumiPath`, `drawYumi`, état `.greeting`, préfixe de notifications `yumi.`). Les seules mentions restantes de Coucou dans le code sont les marqueurs des anciens hooks à retirer.

Vérifié sur `main` : build Debug, 26 tests de la machine d'état, build du target App Store, script de hook et socket Yumi de bout en bout.

Les branches `yumi/identite`, `yumi/personnage` et `yumi/build-docs` restent ouvertes et alignées sur `main` : on continue à y travailler, et `main` ne reçoit que du code vérifié. La répartition des fichiers ci-dessus reste valable tant que les trois sessions travaillent en parallèle.

Reste à faire : recette manuelle complète dans la notch (étape 7 de `ARCHITECTURE.md`), sons définitifs (les 28 actuels sont synthétisés et provisoires), équipe de signature, puis les sujets hors migration listés à la fin de `ARCHITECTURE.md`.

## Cœur : moteur et modules (branche `yumi/coeur`)

Le chemin d'un événement : script de hook, socket, `ClaudeHookTranslator`, `EventEngine`, `SessionStore`, puis les modules et la pastille Claude Code. `Core/` et `Modules/` ne dépendent ni des vues, ni d'`AppState`, ni des sons : ils sont compilés tels quels dans les tests.

| Sujet | État |
|---|---|
| `AppState.modules` | Rempli par `ModuleRegistry`, un snapshot par module sélectionné, dans l'ordre de sélection. Les cinq premiers vont dans l'île. La sélection est persistée sous la clé `selectedModules`. |
| Modules livrés | `claude-code`, `agenda`, `notes`, `focus`, `music`, `weather`. Ce sont aussi les modules sélectionnés au premier lancement. |
| `moduleAction` | Reçue par le registre, transmise au module (`primary` ou `secondary`). |
| Claude Code | Tous les terminaux, plusieurs sessions. La pastille `integration_claude` montre la session qui attend une réponse, sinon la dernière active. |
| Approbations | Une file : une demande par session, la plus ancienne à l'écran. Repli vers le terminal après 115 s, ou dès que le script de hook disparaît. |
| Script de hook | Protocole 2 : le script attend un accusé de réception 2 s avant d'attendre la décision. Une app figée ne retient plus Claude Code. Les scripts plus anciens restent acceptés. |
| Permissions | Jamais demandées au lancement, seulement au clic sur le bouton du module. Textes en français dans `project.yml`, entitlements calendrier et position dans `Resources/`. |
| Météo | Open-Meteo, sans clé. Position arrondie au kilomètre, ou ville fixée par la préférence `weatherCity`. |
| Notes | Fichier texte `notes.txt` dans le dossier de support. « Nouvelle note » enregistre le presse-papiers tant que l'île n'a pas de champ de saisie. |
| Pollers hérités | Chacun ne tourne que si son intégration est cochée. |

Reste à faire côté île : dessiner `AppState.modules`, remplacer les « VS Code » écrits en dur par le nom de la pastille, proposer le choix des modules et la ville de la météo dans les réglages. Reste à vérifier à la main : Musique et Spotify en lecture, Agenda et rappels après autorisation, Météo par localisation, boutons Deny et Always.

## Cœur, phase 3 : île repliée et chat par Claude Code

| Sujet | État |
|---|---|
| `ModuleSnapshot.live` | Claude Code : attention quand une session attend. Musique : activité en lecture, puis cinq minutes plus discrètement après une pause. Focus : activité pendant le décompte. Agenda : prochain rendez-vous du jour. Notes : seulement un rappel en retard. Météo : rien. |
| Bouton « Voir » de Claude Code | Ouvre le dossier de la session dans l'éditeur de code (celui de la session, sinon la préférence `codeEditor`, sinon VS Code et ses cousins). Une approbation en attente reste traitée dans l'île. |
| Chat | Un processus `claude -p` par message, entrée et sortie en `stream-json`, session reprise par `--resume`. Dossier de travail `~/Documents/Yumi`, modifiable par la préférence `chatFolder`. Sans Claude Code : l'API si une clé existe. Build App Store : toujours l'API. |
| Permissions du chat | En mode `-p` simple, Claude Code n'appelle jamais le hook `PermissionRequest` et refuse l'outil. Le mécanisme prévu pour un programme hôte est `--permission-prompt-tool stdio` : la demande arrive sur la sortie du processus (`control_request`), la réponse repart sur son entrée. Yumi l'affiche dans la même file d'approbations que les autres sessions. Les hooks de la session du chat sont ignorés pour ne pas la compter deux fois. Aucune option qui saute les permissions, mode `default` imposé. |
| « Toujours » dans le chat | N'applique que les règles proposées pour ce qui est affiché, jamais un changement de mode ni l'ouverture d'un dossier. |
| Fichier joint | Seul le dossier `inbox` de Yumi est ouvert en lecture au chat. |

Reste à faire côté île : afficher l'état `working` dans la vue du chat (elle ne connaît que `thinking`), montrer la commande entière d'une approbation (une seule ligne tronquée aujourd'hui), distinguer les lignes d'action des réponses.
