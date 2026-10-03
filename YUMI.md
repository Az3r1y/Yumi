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

## Phase 4 : la nouvelle interface, par activités

La phase 3 est terminée et fusionnée (chat piloté par Claude Code et affiché en direct, île repliée vivante). L'interface de l'île a été jugée moins sérieuse que celle de Coucou et repensée. **La maquette de référence a changé** : `design/yumi/maquette/reference.html` est maintenant la version 13. Là où elle contredit le tableau « Décisions validées » plus haut, c'est elle qui fait foi. Le personnage ne change pas.

Ce qui change :

| Sujet | Nouvelle décision |
|---|---|
| Principe | L'île montre une seule activité à la fois, et chaque activité a sa propre mise en page. Plus de rangée de pastilles, plus de cartes, plus de légende sous Yumi, plus de second carré. |
| Boutons | Gros boutons ronds avec un symbole. Une permission se présente comme un appel entrant : rouge pour refuser, vert pour autoriser, « Toujours autoriser » en petit texte. |
| Activités dessinées | Agenda (un bouton rejoindre), agent au travail (durée et arrêter), alerte, terminé (la coche se dessine), erreur (relancer), musique (onde, barre de lecture, trois commandes), focus (gros chiffres, deux boutons). Les autres modules suivent un modèle commun : chiffre clé en couleur, une phrase, un bouton. |
| Barre du bas | Toujours là : la vue d'ensemble, une icône par module (celui à l'écran déplie son nom, un point signale ce qui est vivant, le nom apparaît en étiquette au survol), puis le chat et les réglages. |
| Vue « Tous » | Tous les modules sur deux colonnes : icône, nom complet, chiffre clé. C'est ce qui s'affiche quand on ouvre l'île et que rien n'est urgent. |
| Chat | Accessible par son icône dans la barre et par un clic sur Yumi. La réponse s'écrit en direct, l'action en cours s'affiche sous le texte. |
| Réglages dans l'île | Sons et volume, délai avant que l'île se replie (5 s, 15 s, 30 s, 1 min, jamais ; 15 s par défaut), cigarette quand un agent travaille (sinon café). Ces réglages doivent réellement agir. |
| Île repliée | Yumi d'un côté de la notch, l'activité principale de l'autre. Une seconde activité vit dans une bulle qui se détache de l'île comme une goutte. |
| Lancement | Yumi seul, sans aucun texte : la goutte, les yeux dans le noir, l'ouverture, la lumière, le salut, le clin d'œil, le repli. Environ 4,5 secondes. |
| Départ | En quittant : il salue, clin d'œil, s'endort, sa lumière s'éteint comme elle s'était allumée, la goutte remonte dans la notch. |
| Typographie | Police du système pour le texte ; la police ronde est réservée aux gros chiffres. |
| Taille | Les proportions de la maquette, à l'échelle déjà retenue dans l'app. |

Contrats ajoutés sur `main` pour cette phase :

- `Contracts/ModuleTypes.swift` : `symbol` (icône du module), `primarySymbol` et `secondarySymbol` (symboles des boutons ronds), `progress` (barre de lecture ou de minuteur).
- `Contracts/AppLifecycle.swift` : `yumiQuitRequested` et `yumiQuitReady`, pour jouer l'animation de départ avant la fin de l'app.

Deux sessions : Cœur renseigne les nouveaux champs et retarde la fin de l'app ; Île porte la maquette.

## Phase 5 : un compagnon, pas un tableau de bord

La phase 4 est terminée et fusionnée (interface par activités). Yumi a un corps de compagnon et un cerveau d'indicateur d'état. Priorité : qu'il connaisse la personne, se souvienne, et parle avec sa propre voix. La référence est `design/yumi/voix.md`.

- **La voix** : tout ce que Yumi dit est réécrit selon la fiche. Les libellés très courts restent neutres.
- **La mémoire** : il retient de lui-même, dans un fichier local lisible. Contrat `Contracts/MemoryTypes.swift`, `AppState.memory` et `AppState.userName`. Le cœur tient la mémoire, l'île la montre et permet de la corriger ou de l'effacer.
- **Le prénom** est demandé au premier lancement, jamais écrit en dur.

Viendront ensuite, dans cet ordre : l'initiative (il parle le premier, rarement et à propos, avec un réglage de discrétion), puis le lien entre les modules (une phrase qui résume la situation).

## Phase 6 : l'initiative

La mémoire et la voix sont en place et fusionnées. Yumi doit maintenant parler le premier, rarement et à propos. La référence est la section « Quand il parle le premier » de `design/yumi/voix.md`.

Contrat `Contracts/RemarkTypes.swift` et `AppState.remark` : le cœur décide quand et quoi dire, l'île l'affiche près de Yumi, replié comme ouvert, et rapporte si la personne a répondu ou ignoré. Le réglage de discrétion (silencieux, discret, bavard) se trouve dans les réglages de l'île.

Reste ensuite le lien entre les modules, et un défaut connu de la mémoire : le résumé de fin de conversation répète parfois un souvenir déjà noté.

## Phase 7 : GitHub en scènes, et le processeur en usage réel

L'initiative et la baisse du processeur au repos sont fusionnées. Deux sujets.

**GitHub.** Un vrai module GitHub, et une petite scène de Yumi pour chaque événement : étoile, fork, pull request ouverte, fusion, push, commit, issue, release, nouvel abonné. Contrat `Contracts/EventAnimations.swift` : un module poste `yumiScene`, le personnage joue la scène une fois. Le cœur détecte les événements et fait dire à Yumi une phrase quand ça compte ; l'île dessine l'activité GitHub.

**Le processeur en usage réel.** Mesuré le 2 octobre en Release : au repos complet, 6,7 % île repliée et 0,6 % île masquée. Mais avec de la musique en lecture et des sessions Claude actives, donc en usage normal, l'app reste entre 12 et 23 %, parce que les habitudes animées (casque, cigarette) tournent à pleine cadence. C'est le prochain objectif : une habitude qui dure ne doit pas coûter plus de 5 %.

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
| Boutons « Voir » | Tous vont là où se trouve la discussion : l'application dans laquelle tourne la session (son terminal, son éditeur ouvert sur le projet, ou l'app Claude). VS Code ne s'ouvre que si la session y tourne. Une approbation en attente se traite dans l'île. Les cartes de l'île passent par `ClaudeTaskMirror.openSession()`. |
| Chat | Un processus `claude -p` par message, entrée et sortie en `stream-json`, session reprise par `--resume`. Dossier de travail : Téléchargements, modifiable par la préférence `chatFolder`. Sans Claude Code : l'API si une clé existe. Build App Store : toujours l'API. |
| Permissions du chat | En mode `-p` simple, Claude Code n'appelle jamais le hook `PermissionRequest` et refuse l'outil. Le mécanisme prévu pour un programme hôte est `--permission-prompt-tool stdio` : la demande arrive sur la sortie du processus (`control_request`), la réponse repart sur son entrée. Yumi l'affiche dans la même file d'approbations que les autres sessions. Les hooks de la session du chat sont ignorés pour ne pas la compter deux fois. Aucune option qui saute les permissions, mode `default` imposé. |
| « Toujours » dans le chat | N'applique que les règles proposées pour ce qui est affiché, jamais un changement de mode ni l'ouverture d'un dossier. |
| Fichier joint | Seul le dossier `inbox` de Yumi est ouvert en lecture au chat. |

Reste à faire côté île : afficher l'état `working` dans la vue du chat (elle ne connaît que `thinking`), montrer la commande entière d'une approbation (une seule ligne tronquée aujourd'hui), distinguer les lignes d'action des réponses.

## Cœur, chantier C : le chat en direct

| Sujet | État |
|---|---|
| `AppState.chatLive` | Renseigné pendant toute la réponse, remis à `nil` à la fin (réponse ajoutée à `chatHistory`, erreur, ou annulation). Dix mises à jour par seconde au plus. |
| `text` | Grandit mot à mot (messages partiels de Claude Code). Repart de zéro à chaque nouveau message de la même réponse : entre deux actions, c'est la phrase en cours qui s'affiche. |
| `activity` | Apparaît dès que l'outil est nommé (« Écrit un fichier »), puis se précise (« Écrit bonjour.txt »). En attente de permission : `kind` vaut `waiting`, libellé « Attend ton accord », `detail` = ce qui est demandé. Si plusieurs actions sont annoncées ensemble, celle qui attend passe devant, sinon la plus ancienne. |
| `detail` | Quatre lignes de 80 caractères au plus : le début du fichier écrit ou du texte modifié, les dernières lignes affichées par une commande terminée. |
| `done` | Une entrée par action finie, `succeeded` faux si elle a échoué ou a été refusée. |
| Île repliée | Le module Claude Code annonce l'action du chat dans `live` (priorité activité, attention pendant une attente de permission). Une session qui attend l'utilisateur reste devant. Rien quand le chat est au repos. |
| Historique | Les lignes d'action (« Fichier créé : … ») sont toujours ajoutées à `chatHistory` : à l'île de choisir entre elles et `done` pendant la réponse. |
| Dossier du chat | Téléchargements par défaut. Un ancien `~/Documents/Yumi` n'est ni déplacé ni supprimé. |

## Cœur, phase 4 : champs de l'interface par activités

| Sujet | État |
|---|---|
| `symbol` | Claude Code `terminal.fill`, Agenda `calendar`, Notes `note.text`, Focus `timer`, Musique `music.note`, Météo selon le ciel (`sun.max.fill`, `cloud.rain.fill`…, `cloud.sun.fill` tant que le temps n'est pas connu). |
| `primarySymbol`, `secondarySymbol` | Déduits du libellé du bouton par une table unique (`Modules/ModuleSymbols.swift`) : chaque libellé a son symbole, `secondarySymbol` est nil quand il n'y a pas de second bouton. |
| `progress` | Focus : avancement de la phase en cours (temps écoulé à gauche, durée de la phase à droite), figé en pause. Musique : position dans le morceau, republiée chaque seconde pendant la lecture. nil ailleurs, et nil pour la musique tant que la durée ou la position ne sont pas connues. |
| Position de la musique | Spotify l'annonce. Pour Musique, elle est demandée au lecteur si l'automatisation est déjà accordée, sinon comptée depuis le début du morceau et figée en pause : elle peut dériver si l'utilisateur déplace la tête de lecture. |
| Départ | `applicationShouldTerminate` annule la fin, poste `yumiQuitRequested`, et termine à la réception de `yumiQuitReady`, après six secondes au plus, ou tout de suite si l'utilisateur quitte une seconde fois. Une fermeture de session, un redémarrage ou une extinction ne sont jamais retardés. |
| Historique du chat | Tout le texte est gardé dans l'ordre : le texte écrit avant une action entre dans `chatHistory` au moment où l'action commence, puis la ligne d'action, puis la suite. `chatLive.text` repart alors de zéro pour ne pas l'afficher deux fois. |

## Cœur, phase 5 : mémoire et voix

| Sujet | État |
|---|---|
| Fichier | `memoire.md` dans le dossier de support de Yumi : Markdown lisible, un prénom puis trois rubriques (Toi, Tes projets, Le fil). Écrit par fichier temporaire, lisible par l'utilisateur seul. Modifiable à la main : il est relu au lancement. |
| `AppState.memory`, `AppState.userName` | Tenus à jour par `Memory/MemoryStore`, qui répond à `memorySetName`, `memoryEdit`, `memoryDelete` et `memoryClear`. |
| Limite | 120 souvenirs. Au-delà, les plus anciens du fil partent d'abord, puis les plus anciens sur les projets ; jamais ceux sur la personne. |
| Apprentissage | C'est la conversation qui trie : elle termine sa réponse par un bloc `<memoire>` que la personne ne voit jamais (ni dans l'historique ni dans `chatLive`). « Oublie ça » retire le souvenir par son identifiant. Un prénom donné dans le chat va dans `userName` (ligne « prénom | … »), pas dans un souvenir. Aucun tiret long, ni dans les réponses ni dans les souvenirs : la consigne le demande et l'app les remplace. Fichier ou fenêtre montrés : elle retient de quoi il s'agissait. |
| Résumé de fin | Quand une conversation d'au moins une réponse se termine (`clearConversation`), elle est résumée en quelques lignes dans le fil. Le résumé reçoit la consigne complète, et ses lignes vont au fil quel que soit le mot qui les commence. Pas de résumé quand on quitte l'app. |
| Filtre | `MemoryGuard` passe sur chaque phrase avant écriture, quelle que soit la décision de la conversation : mot de passe, clé, code, numéro de carte ou de compte, texte plus long qu'une phrase. L'interdit « information sur une autre personne » ne peut pas être garanti par du code : il repose sur la consigne donnée à la conversation. |
| Se souvenir | Chaque message part avec le prénom, tout ce qui concerne la personne et ses projets, et les quinze derniers souvenirs du fil. |
| Voix | Consigne du chat réécrite d'après `design/yumi/voix.md`. Titres, sous-titres, attentes et erreurs des modules réécrits à la première personne ; noms de modules, chiffres clés et boutons restent neutres. `Tests/Modules/VoiceTests.swift` échoue si une formule interdite ou un emoji apparaît. |
| Libellés du chat en direct | À la première personne : « J'écris bonjour.txt », « Je lance swift test », « J'attends ton accord ». |
| Textes de permission | Réécrits à la première personne dans `project.yml`. |

## Cœur, phase 6 : l'initiative

| Sujet | État |
|---|---|
| Moteur | `Initiative/InitiativeEngine` (pur) : une occasion et son contexte entrent, une `YumiRemark` sort, ou rien. `InitiativeWatch` (pur) reconnaît les occasions, `InitiativeDriver` écoute le Mac et pose `AppState.remark`. |
| Occasions | Premier réveil du jour, retour après trente minutes d'absence, deux heures sans pause (puis toutes les deux heures), tâche d'agent de dix minutes ou plus qui se termine, rendez-vous à dix minutes ou moins pendant qu'un agent attend, 23 h 30, batterie à 15 % ou moins sans chargeur, vendredi 18 h. Trois formulations au moins par occasion, écrites à l'avance. |
| Garde-fous | Jamais pendant un focus, un partage d'écran, une présentation, Ne pas déranger. Vingt minutes entre deux remarques, sauf si quelqu'un attend. Un sujet ignoré trois fois de suite est abandonné trois jours. Jamais la même phrase deux jours de suite. |
| Réglage | `YumiTalk` lu à chaque remarque : silencieux rien ; discret ce qui compte, quatre par jour au plus ; bavard ajoute bonjours et encouragements, dix par jour au plus. |
| Remarque | Posée dans `AppState.remark`, retirée à la fin de sa durée (comptée comme ignorée), à `remarkAccepted` ou à `remarkDismissed`. Une seule à la fois. |
| Actions | « Pause » lance une pause de cinq minutes dans le module Focus. « Voir » amène devant l'application de la session de l'agent. |
| Coût au repos | Aucun minuteur répétitif : le pilote réagit aux notifications du système (réveil, verrouillage, batterie) et aux événements de session, et dort jusqu'au prochain moment exact (deux heures, 23 h 30, vendredi 18 h, dix minutes avant un rendez-vous). |
| Limites | Ne pas déranger : lu dans un fichier du système, illisible dans le bac à sable (réponse « non »). Partage d'écran : appel du serveur de fenêtres absent des en-têtes publics, non utilisé dans le build App Store. Présentation : écran recopié, ou diaporama Keynote ou PowerPoint. Sans accès au calendrier, le bonjour ne parle pas de la journée. |

## Cœur, phase 7 : le module GitHub

| Sujet | État |
|---|---|
| Module | `Modules/GitHub`, identifiant `github`. Il remplace `GithubPoller` (supprimé) et rejoint une fois la sélection des installations existantes. |
| Jeton | Jeton personnel lu dans le trousseau sous la clé `github-token`. Sans jeton : « Je ne vois pas ton GitHub. », bouton « Brancher » qui ouvre les réglages. L'action `secondary` de `moduleAction` fait relire le jeton tout de suite. |
| Ce qu'il suit | Étoile, fork, pull request ouverte, fusion, push, issue, release (flux `events` et `received_events` de la personne, limités à ses dépôts pour ce que font les autres) ; nouvel abonné (compteur de `/user`). Le commit local vient des sessions Claude Code (une commande `git commit` qui se termine), sans surveiller le disque. |
| Quota | Chaque requête porte l'`ETag` de la réponse précédente : un flux inchangé ne coûte rien. Les flux sont relus toutes les 60 s au plus tôt, ou moins souvent si `X-Poll-Interval` le demande ; dépôts, abonnés et relectures une fois sur cinq. Quota épuisé : attente jusqu'à l'heure donnée par GitHub. |
| Scènes | `yumiScene` à chaque événement nouveau, une par type, avec `count` quand plusieurs arrivent ensemble. Le premier regard sert de référence : l'historique n'est jamais rejoué. Ce qui a été vu est gardé entre deux lancements. |
| Snapshot | `status` : « étoiles · forks · pull requests ouvertes » du dépôt le plus actif. `subtitle` : le dépôt. `title` : le dernier événement en une phrase. « Ouvrir » ouvre le dépôt. Une pull request qui attend une relecture passe devant : `needsAttention`, bouton « Relire », `live` en priorité attention. |
| Parole | Étoile, fork, fusion et release passent par le moteur d'initiative (`Occasion.repository`), avec tous ses garde-fous. Un mot au plus par lot d'événements. |

## Cœur : mode tournage

`YUMI_STUDIO=1` au lancement, dans tous les builds (Release compris). Rien de réel ne démarre : ni serveur de hooks, ni modules, ni mémoire, ni initiative, ni chat, ni pollers. Le trousseau n'est ni lu ni écrit, le dossier de Yumi non plus, et aucune permission ne peut être demandée par le cœur. `AppState` reste entièrement à la main de l'île, qui sait qu'on tourne par `AppState.isStudio` (ou `StudioMode.isOn`). `ClaudeService.chat` ne fait rien dans ce mode : à l'île de mettre en scène `chatHistory` et `chatLive`.

Reste côté île : le dépôt d'un fichier copie encore dans le dossier `inbox` de Yumi (`FileDropView`).

## Cœur : le Context Engine (branche `yumi/contexte`)

Première fondation de l'intelligence : Yumi sait ce que la personne fait sur son Mac, sans pouvoir agir dessus. `Context/` suit la règle de `Core/` : ni vue, ni `AppState`, ni son, compilé tel quel dans les tests.

| Sujet | État |
|---|---|
| Ce qu'il sait | Application au premier plan et depuis quand, application précédente, applications récentes, fenêtre au premier plan (titre, fichier montré), durée de la session, événements récents, part du temps récent par catégorie d'application (`LSApplicationCategoryType` lu dans chaque application, rien d'écrit en dur). |
| Événements | `ContextMessage.event` : `sessionStarted`, `sessionEnded`, `applicationChanged`, `windowChanged`, lancement et fermeture d'application, veille, réveil, verrouillage, changement d'utilisateur, permission. Puis `contextUpdated` avec le nouveau `ContextSnapshot`. Abonnement par `ContextEngine.messages()` (`AsyncStream`), moteur `@Observable`. |
| Session | Commence au démarrage du moteur, au réveil ou au déverrouillage ; finit à la veille, au verrouillage, à l'extinction des écrans. Un réveil sur écran verrouillé ne compte pas. Le temps d'absence n'est pas compté comme temps passé dans l'application. |
| Déduplication | La même application ou la même fenêtre signalée deux fois ne produit rien ; un signal système répété non plus ; une fenêtre d'une application qui n'est plus devant est ignorée. |
| Historique | En mémoire seulement : 300 événements et 4 heures au plus. Couper le moteur efface tout. |
| Coût | Aucune boucle : notifications de `NSWorkspace`, notifications distribuées du système, et notifications d'accessibilité de l'application au premier plan. Un seul minuteur ponctuel ramène Yumi de `contextChanged` à `observing`. |
| Permissions | Aucune n'est demandée. Le titre des fenêtres n'est lu que si l'Accessibilité est déjà accordée (`AXIsProcessTrusted`, sans invite) ; le changement de permission est suivi. Pas d'enregistrement d'écran. Build App Store : pas de fenêtre. |
| Désactivation | Réglages, section Context : interrupteur persisté sous `contextEngineEnabled`. Mode tournage : le moteur ne démarre pas (`LaunchPlan.context`). |
| Personnage | `ContextPresence` : `idle`, `observing`, `contextChanged`. Quand l'application change, île repliée et rien d'autre en cours, Yumi jette un coup d'œil vers le bas puis reprend le pointeur. Rien de plus : pas d'action, pas de remarque. |
| Confidentialité | Pas de capture d'écran, pas de frappes, rien envoyé à un modèle ni ailleurs. `ClaudeService` ne lit pas le contexte. |

Prochaines étapes possibles : providers de facettes (`ContextFacet` : écran, presse-papiers, fichiers, navigateur, calendrier, git, projet), puis un lien vers l'initiative et le chat, chacun derrière son propre réglage.

## Cœur : l'Agent Runtime (branche `yumi/agent`)

Le cerveau de Yumi, pas encore ses mains : une intention entre, un plan vérifié sort, des étapes s'exécutent sous contrôle, un `AgentResult` termine toujours la course. `AgentRuntime/` suit la règle de `Core/` : ni vue, ni `AppState`, ni son, compilé tel quel dans les tests. Il part de la branche `yumi/contexte`.

| Sujet | État |
|---|---|
| Entrée | `AgentRequest` : l'intention, le `ContextSnapshot` du moment (ou rien), l'heure. Le contexte est joint par celui qui crée la demande, une fois, quand la personne demande : le runtime ne capture rien et ne s'abonne pas au Context Engine. |
| Contexte transmis | `RequestContext` : application, fenêtre, nom du fichier (sans son dossier), application précédente, activité principale. Ni historique d'événements, ni liste d'applications. Dans la consigne du modèle il est entre balises `<context>`, présenté comme des données ; ses chevrons sont neutralisés pour qu'il ne puisse pas fermer le bloc. |
| Modèle | `LLMProvider` (texte en entrée, texte en sortie) : Anthropic, OpenAI, Gemini ou un modèle local s'y branchent sans toucher au runtime. Aucun n'est branché : `UnavailableLLMProvider` répond « aucun modèle », le runtime n'invente jamais de plan. |
| Planification | `AgentPlanner` propose (`LLMAgentPlanner` lit un objet JSON), `PlanValidator` décide : outil enregistré, sous le plafond de la politique, arguments conformes au schéma, douze étapes au plus. Le risque, les approbations et les identifiants d'étape viennent du registre et de la politique, jamais du modèle. Un modèle peut ajouter une approbation, jamais en retirer. `cannotPlan` permet de dire que ce n'est pas faisable. |
| Outils | `Tool` (descripteur : id, nom, description, schéma d'entrée, risque, clés de sortie promises ; `execute`). `ToolRegistry` construit une fois, au lancement. Livrés : `get_current_time` (risque nul) et `get_current_context` (lecture, ne lit que le snapshot de la demande). |
| Politique | `AgentPolicy` : plafond `read` (rien qui écrive ou sorte du Mac ne peut tourner, même approuvé), approbation à partir de `write`, et `write` comme `external` demandent toujours, quel que soit le réglage. |
| Permissions | `PermissionManager` est la seule porte : chaque étape qui le demande y passe, le plan entier est revérifié avant l'exécution, aucun drapeau ne la contourne. Implémentation actuelle : `DenyingPermissionManager`, qui refuse tout. Un refus annule la course (ou saute l'étape si elle est facultative). |
| Exécution | `AgentExecutor` : étape par étape, revérifie l'outil, demande l'accord, exécute hors du fil principal avec un délai maximal (30 s), contrôle la sortie, met l'état à jour. Une erreur d'outil devient une valeur, jamais un plantage. |
| Reprise | `RecoveryPolicy` : `retry` pour une panne passagère ou un délai dépassé (3 essais par étape, 6 relances par course, plafonnés à 5 et 20), `skip` pour une étape facultative, `cancel` sur un refus, `fail` sinon. |
| Vérification | `AgentVerifier` : `StructuralVerifier` exige que chaque étape non facultative soit terminée avec un résultat. Un vérificateur futur pourra refuser un résultat, jamais exécuter. |
| États | `ExecutionState` : idle, planning, awaitingApproval, executing, verifying, completed, failed, cancelled. `AgentActivity` les traduit pour le personnage (idle, thinking, planning, working, waiting, success, error), sans rien dire des poses : c'est au personnage de décider. |
| Événements | `AgentEvent` : agentStarted, planCreated, stepStarted, stepCompleted, stepFailed, stepSkipped, approvalRequired, approvalGranted, approvalDenied, verificationStarted, agentCompleted, agentFailed, agentCancelled. Abonnement par `RuntimeAgent.events()`. `suggestedPriority` (`InteractionPriority` : silent, ambient, attention, blocking) n'est qu'une indication : seule une demande d'accord est bloquante, la progression est silencieuse. Aucune notification n'est affichée par le runtime. |
| Historique | `AgentRun` : la tâche et ses événements (200 au plus), sérialisable pour un futur replay. `AgentRunHistory` garde les 20 dernières courses, en mémoire seulement. |
| Interface | Réglages, section Agent : planificateur, outils, but, état, étape en cours, progression, erreur, derniers événements ; un champ pour lancer une demande, « Check tools » (un plan écrit par le développeur, qui passe par les mêmes règles) et « Cancel ». Le contexte n'est joint qu'au clic. Mode tournage : pas de runtime. |
| Nommage | `RuntimeAgent` et `RuntimeTask`, parce que `Agent` (Core/) désigne déjà un produit externe et `AgentTask` une carte de l'île. `AgentPermissionRequest` pour la même raison (`PermissionRequest` est la demande d'un hook Claude Code). |

Reste à faire : brancher un vrai `LLMProvider` (et décider ce qui peut être envoyé à un modèle, le Context Engine promettant aujourd'hui que rien n'y part), le Permission System derrière `PermissionManager` (dans la file d'approbations de l'île), relier `AgentActivity` et les événements au personnage et à l'île, puis les outils qui écrivent, une fois le Permission System en place.
