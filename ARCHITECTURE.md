# Architecture de Coucou (base du fork Yumi)

> Ce document décrit Coucou, le projet d'origine, tel qu'il était avant l'import dans ce dépôt. Les chemins `NotchBuddy/...` correspondent ici à `Yumi/...`. Les icônes, sons, médias, prototypes et le portage Windows cités plus bas n'ont pas été importés. Les décisions propres à Yumi sont dans `YUMI.md`.

Document d'analyse du dépôt `Louis-CFM/coucou` au commit `5ae7bd9`, rédigé avant toute modification de code. Objectif : comprendre chaque système pour créer l'application macOS **Yumi** sans changer le comportement existant.

Périmètre : l'application macOS native (`NotchBuddy/`). Le portage Windows (`windows/`, Tauri 2 + Rust + TypeScript) est décrit seulement là où il a un impact sur le fork.

Méthode : lecture statique de l'ensemble des sources Swift (26 fichiers, 11 403 lignes), de la configuration de build, des scripts et de la documentation. Aucun build ni exécution n'a été lancé pour cette analyse.

## Sommaire

1. [Vue d'ensemble](#vue-densemble)
2. [Les 18 systèmes](#les-18-systèmes)
3. [Écarts entre la documentation et le code](#écarts-entre-la-documentation-et-le-code)
4. [Inventaire des identifiants à renommer](#inventaire-des-identifiants-à-renommer)
5. [Plan de migration vers Yumi](#plan-de-migration-vers-yumi)

## Vue d'ensemble

```
Claude Code (VS Code)                         Services tiers (HTTPS)
      │ hook "command"                         Stripe, n8n, GitHub, Vercel,
      ▼                                        Resend, Notion, Cal.com, Anthropic
 nb-hook (script Python)                               ▲
      │ JSON + "\n" sur socket Unix                    │ URLSession
      ▼                                                │
 HookServer ───────────────┐                   7 Pollers + ClaudeService
 (threads POSIX)           │                           │
                           ▼                           ▼
                    AppState.shared  (ObservableObject, @MainActor, singleton)
                           ▲                           │ @Published
   NotificationCenter      │                           ▼
 ┌─────────────────────────┴───────────┐      IslandRootView (SwiftUI)
 │ IslandWindowController              │        ├ IslandShape (forme noire)
 │  ├ IslandPanel (NSPanel 720×320)    │        ├ IslandContentView (17 vues)
 │  ├ IslandStateMachine (4 états)     │        ├ BotPlacement → BotCanvasView → BotEngine
 │  ├ boucle 60 Hz (souris, hover)     │        ├ GreetingCanvasView
 │  └ moniteurs NSEvent (clic, drag)   │        └ UploadCanvasView ← UploadSequenceEngine
 └─────────────────────────────────────┘
              SoundEngine (28 WAV, AVAudioPlayer)      KeychainStore (cache mémoire)
```

Trois traits structurants :

- **Un état global unique.** `AppState.shared` est lu et écrit directement par presque tous les fichiers. Il n'y a pas d'injection de dépendances.
- **Un bus d'événements par `NotificationCenter`.** 16 notifications préfixées `notchBuddy.` relient le contrôleur de fenêtre, le moteur du personnage, les vues et le serveur de hooks.
- **Aucun test automatisé.** Toute vérification de non-régression est manuelle.

## Les 18 systèmes

### 1. Architecture des fichiers

```
coucou/
├── NotchBuddy/                    application macOS
│   ├── project.yml                source de vérité XcodeGen
│   ├── NotchBuddy.xcodeproj/      généré, mais versionné
│   ├── Assets.xcassets/           AppIcon (10 PNG), MenuBarIcon (3 PNG)
│   ├── Resources/
│   │   ├── Info.plist, InfoAppStore.plist
│   │   ├── Coucou.entitlements, CoucouAppStore.entitlements
│   │   └── sounds/                28 fichiers WAV (3 Mo)
│   └── Sources/App/               26 fichiers Swift, un seul module, pas de sous-dossiers
├── windows/                       portage Tauri 2 (hors périmètre Yumi macOS)
├── docs/                          SPEC.md, INTEGRATIONS.md, site GitHub Pages, médias
├── design/                        prototype HTML, animations de référence, captures
├── scripts/release.sh             build signé, notarisation, release GitHub
├── .github/                       workflows build, release, windows ; modèles d'issues
├── CLAUDE.md, CONTRIBUTING.md, README.md
└── LICENSE, LICENSE-ASSETS.md
```

| Champ | Détail |
|---|---|
| Fichiers | Tout le dépôt. Code applicatif dans `NotchBuddy/Sources/App/`. |
| Responsabilité | Un seul target applicatif, structure plate. Les plus gros fichiers : `IslandViewContent.swift` (2 793 lignes, 56 types de vues), `BotEngine.swift` (1 503), `HookServer.swift` (863), `IslandWindowController.swift` (859). |
| Dépendances | XcodeGen pour régénérer le projet. |
| Entrées | `project.yml`. |
| Sorties | `Coucou.app`. |
| Risques au refactor | Le `.xcodeproj` est versionné alors qu'il est généré : toute modification manuelle est écrasée par `xcodegen`. Le dossier s'appelle `NotchBuddy`, le produit `Coucou`, le personnage `Mochi` : trois noms pour la même chose, répartis partout. Les types déclarés dans des fichiers au nom trompeur (le Keychain vit dans `ClaudeService.swift`, les noms de notifications dans `IslandWindowController.swift`). |

### 2. Point d'entrée de l'application

| Champ | Détail |
|---|---|
| Fichiers | `NotchBuddyApp.swift` (13 lignes), `AppDelegate.swift` (77 lignes). |
| Responsabilité | `@main struct NotchBuddyApp` déclare une scène `Settings` et délègue tout à `AppDelegate` via `@NSApplicationDelegateAdaptor`. `applicationDidFinishLaunching` exécute dans l'ordre : `signal(SIGPIPE, SIG_IGN)`, préchauffage de `KeychainStore.shared`, politique `.accessory`, création de l'icône de barre de menus, création de `IslandWindowController`, `fsm.launch()` (animation d'accueil), démarrage de `HookServer` puis des 7 pollers. |
| Dépendances | AppKit, SwiftUI, tous les singletons. |
| Entrées | Lancement du processus ; notification `.openFullSettings`. |
| Sorties | `NSStatusItem` avec menu (Open Coucou, Settings…, Quit) ; fenêtre de réglages `NSWindow` 480×540 créée à la main. |
| Risques au refactor | L'ordre d'initialisation compte : `SIGPIPE` doit être ignoré avant le serveur de socket, et le Keychain doit être lu sur le thread principal avant le premier poller. `LSUIElement` plus `.accessory` : pas d'icône dans le Dock. La scène `Settings` SwiftUI et la fenêtre manuelle coexistent (deux chemins vers `SettingsView`). Chaînes visibles à renommer : « Open Coucou », le titre de la fenêtre de réglages, la description d'accessibilité « Coucou ». |

### 3. Gestion de la notch

| Champ | Détail |
|---|---|
| Fichiers | `IslandWindowController.swift:754-770` (détection), `IslandTypes.swift:83-90` (constantes), `IslandRootView.swift:172-244` (`IslandShape`). |
| Responsabilité | Trouver l'écran à encoche (`safeAreaInsets.top > 0`), mesurer sa largeur (`frame.width` moins `auxiliaryTopLeftArea` et `auxiliaryTopRightArea`) et sa hauteur (`safeAreaInsets.top`). Valeurs de repli : 184 × 32. Dessiner la forme noire qui prolonge l'encoche. |
| Dépendances | `NSScreen`, `AppState.notchWidth/notchHeight`. |
| Entrées | Géométrie de l'écran, lue une seule fois dans `convenience init()`. |
| Sorties | Dimensions propagées à `IslandPanel` et `AppState` ; fonction libre `islandSize(mode:view:…)` qui donne la taille de l'île : encoche seule (hidden), encoche + 160 (compact), 640 × hauteur de la vue (expanded). |
| Risques au refactor | Aucune réaction aux changements d'écran (`didChangeScreenParametersNotification` n'est pas observé) : brancher ou débrancher un moniteur après le lancement laisse le panneau au mauvais endroit. `BotCanvasView.lookX` utilise `NSScreen.main` et non l'écran à encoche. `GreetingCanvasView` utilise la constante 184 et non la largeur réelle. La hauteur de la vue chat (`min(300, 240 + 40 × messages)`) est recalculée à l'identique dans quatre endroits (`IslandContainer`, `IslandPanel.currentIslandFrame`, `isBotHit`, `BotCanvasView.lookY`) : les modifier ensemble. La branche « oreilles concaves » de `IslandShape` existe mais `islandTopRadius` vaut toujours 0. |

### 4. NSPanel

| Champ | Détail |
|---|---|
| Fichiers | `IslandWindowController.swift` : `IslandPanel` (lignes 779-805), `setupPanel` (70-147), panneaux fantôme et surbrillance (481-601). |
| Responsabilité | Un `NSPanel` transparent de taille fixe 720 × 320 collé en haut au centre de l'écran, `styleMask [.borderless, .nonactivatingPanel]`, niveau `mainMenuWindow + 3`, `collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. `constrainFrameRect` est neutralisé pour pouvoir recouvrir la barre de menus. `canBecomeKey = true` : le panneau devient key uniquement quand la vue chat s'ouvre (abonnement Combine sur `state.$view`). Deux panneaux auxiliaires : le fantôme du personnage pendant le glisser (niveau +4) et le cadre de surbrillance de la fenêtre cible (niveau +2). |
| Dépendances | AppKit, `NSHostingView`, `FileDropNSView`, `AppState`, `IslandStateMachine`. |
| Entrées | Position de la souris échantillonnée à 60 Hz par un `Timer` ; moniteurs `NSEvent` locaux (clic, glisser, relâcher) et globaux (touche, relâcher). |
| Sorties | Bascule de `ignoresMouseEvents` selon que la souris est dans la forme de l'île (marge de 6 pt) ; `AppState.mousePosition` ; événements vers la machine d'état. |
| Risques au refactor | Le clic traversant repose entièrement sur la boucle 60 Hz : la ralentir rend l'île insensible. Cette boucle tourne en permanence, y compris île masquée, ce qui contredit la règle « 0 % CPU » du `CLAUDE.md`. Structure de vues voulue : `NSHostingView` et `FileDropNSView` sont frères dans un conteneur, et la vue de dépôt renvoie `nil` à `hitTest`. Les moniteurs `NSEvent` ne sont jamais retirés. Deux moniteurs globaux `keyDown` (Échap et raccourci) exigent une permission système (voir système 16). |

### 5. Machine d'état

| Champ | Détail |
|---|---|
| Fichiers | `IslandStateMachine.swift` (145 lignes), câblage dans `IslandWindowController.wireFSM` (151-190), `IslandTypes.swift` (énumérations). |
| Responsabilité | Automate pur à 4 états : `hidden`, `petit` (compact), `home` (ouvert), `coucou` (accueil). Entrées : `launch`, `mouseEntered`, `mouseLeft`, `click`, `greetComplete`, `reveal`. Temporisations : `home → petit` 15 s, `petit → hidden` 60 s, fin d'accueil 0,6 s (10 s si survol). |
| Dépendances | Aucune (ni AppKit ni `AppState`). Communique par la closure `onTransition`. |
| Entrées | Appels du contrôleur de fenêtre ; notification `.greetComplete`. |
| Sorties | `onTransition(from, to)` que le contrôleur traduit en `IslandMode` (`hidden`, `compact`, `expanded`) et en `IslandView` (17 vues). |
| Risques au refactor | **Il existe trois niveaux d'état imbriqués** : l'automate (4 états), `AppState.mode` (3 modes) et `AppState.view` (17 vues), plus `BotState` (11 états du personnage). Plusieurs chemins modifient `mode` et `view` sans passer par l'automate : `expand(to:)` via `.hookExpand`, le raccourci clavier, `collapse()`, `AppState.syncMode()`, et les vues elles-mêmes. L'automate peut donc être désynchronisé de l'affichage (par exemple `expand(to: .approval)` alors que l'automate est en `hidden`). Ce comportement est l'existant : ne pas le « corriger » pendant le renommage. Le nom d'état `.coucou` porte la marque. Les délais sont codés en dur ; les réglages `autoCloseInterval`, `absenceInterval` et `greetThreshold` ne les pilotent pas (voir écarts). |

### 6. Personnage

| Champ | Détail |
|---|---|
| Fichiers | `BotEngine.swift` (moteur et dessin), `BotCanvasView.swift` (enveloppes SwiftUI `BotCanvasView` et `MiniBotCanvasView`), `IslandRootView.swift:248-367` (`BotPlacement`, `botPosition`), `IslandWindowController.swift` (`GhostBotView`, test de clic `isBotHit`). |
| Responsabilité | Le personnage est entièrement dessiné en code dans un `Canvas` SwiftUI : corps en superellipse (`mochiPath`) qui peut se transformer en boîte (`morph`), yeux projetés sur une sphère avec 8 formes (`EyeShape`), mains, rougeur, badge d'état, particules. Table `BotStates` : couleur, teinte, yeux, badge, halo pour chacun des 11 états. Comportements : clignement, respiration, regard qui suit la souris (`tanh`), gifle (3 clics rapprochés donnent l'état `dizzy`), avaler un fichier (`gulp`), 7 émotes. Les mini-personnages des pastilles ont leur propre boucle de comportement. |
| Dépendances | SwiftUI `Canvas`, `TimelineView`, `CACurrentMediaTime`, `SoundEngine`, `AppState` (état effectif, souris, tâche en focus). |
| Entrées | `state.effectiveState` (`stateOverride`, sinon état de la tâche en focus) ; notifications `.triggerEmote`, `.triggerSlap`, `.botBlink`, `.botSetTgEs`, `.botGulp`, `.botMorphTo`, `.botGreet`. |
| Sorties | Rendu ; notification `.botDizzy` ; sons `slap`, `annoyed`, `greet`. |
| Risques au refactor | **Le personnage est dessiné trois fois avec trois implémentations indépendantes** : `BotEngine` (GraphicsContext), `GreetingCanvasView` (CGContext, sa propre `mochiPath`) et `UploadCanvasView` (`usBodyPath`). Changer l'apparence de Yumi impose de modifier les trois, sinon le personnage change de tête entre l'accueil, l'usage normal et le dépôt de fichier. Le système de tweens adresse les propriétés par chaîne (`"morph"`, `"oy"`, `"ox"`) via `setProperty`/`getProperty` : renommer une propriété casse l'animation sans erreur de compilation. Le ratio corps/canvas de 0,6 est dupliqué en plusieurs endroits. Le champ `BotStateCfg.sound` n'est jamais lu. Le design du personnage est protégé par `LICENSE-ASSETS.md` (voir système 18). |

### 7. Animations

| Champ | Détail |
|---|---|
| Fichiers | `GreetingCanvasView.swift` (617 lignes), `UploadSequenceEngine.swift` (437), `UploadCanvasView.swift` (582), `BotEngine.swift` (tweens, ressorts), `IslandRootView.swift` (ressorts de l'île), `FileDropView.swift` (chorégraphie du dépôt). Références : `design/animations/*.html`, `design/prototype/notch-buddy.html`. |
| Responsabilité | Quatre familles. (a) Île : ouverture `spring(response: 0.5, dampingFraction: 0.72)`, fermeture courbe de Bézier 0,34 s, via `IslandShape.animatableData`. (b) Accueil : séquence scriptée de 4,6 s, fonction pure du temps (`greetPose(t)`), particules à graine fixe. (c) Dépôt de fichier : simulation à pas fixe de 1/240 s (`USSimState`, ressorts `USSpring`), calée sur une ligne de temps de référence (`USC.T_DROP = 1.95`, etc.). (d) Personnage : tweens à clés et ressorts dans `BotEngine.update(dt:)`. |
| Dépendances | `TimelineView(.animation)`, `AppState`, `SoundEngine`, notifications `.greetingHover`, `.greetingInterrupt`, `.greetComplete`. |
| Entrées | Horloge murale, position du curseur pendant le glisser, `uploadStartTime`, `uploadDuration`. |
| Sorties | Rendu ; `.greetComplete` vers l'automate ; `state.view = .choose` en fin de séquence de dépôt. |
| Risques au refactor | Les constantes de temps sont des portages ligne à ligne des prototypes HTML : les sons et les changements de vue sont synchronisés dessus par des `Task.sleep` et `asyncAfter` dans `FileDropHandler.handle` (1,30 s + durée + 1 s). Modifier une constante désynchronise son et image. `UploadSequenceEngine.shared.isActive` est lu dans le `body` de `IslandContainer` sans être `@Published` : le rafraîchissement dépend d'un autre changement d'état publié au même moment (`enterZone` doit être appelé avant `.hookExpand`, commentaire ligne 102). Seul `BotCanvasView` met son `TimelineView` en pause quand l'île est masquée ; les mini-personnages non. |

### 8. Sons

| Champ | Détail |
|---|---|
| Fichiers | `SoundEngine.swift` (50 lignes), `NotchBuddy/Resources/sounds/*.wav` (28 fichiers). |
| Responsabilité | Précharger 3 `AVAudioPlayer` par son pour permettre les recouvrements, jouer par nom. Volume par défaut 0,12, plage 0 à 0,2. |
| Dépendances | AVFoundation, `Bundle.main` (sous-dossier `sounds`), `AppState.soundEnabled`. |
| Entrées | `SoundEngine.shared.play("nom")` appelé depuis 9 fichiers ; `AppState.soundVolume`. |
| Sorties | Audio. |
| Risques au refactor | Les sons sont identifiés par chaîne, sans énumération : une faute de frappe ou un fichier manquant échoue en silence. La liste des 28 noms est codée en dur dans `preload()`. `project.yml` copie `Resources/sounds` comme dossier (`type: folder`) : le chemin `subdirectory: "sounds"` en dépend. **Les 28 WAV sont exclus de la licence MIT** : Yumi doit fournir ses propres sons. Garder exactement les mêmes noms de fichiers permet de ne toucher à aucun code. |

### 9. Hooks Claude Code

| Champ | Détail |
|---|---|
| Fichiers | `HookServer.swift` : installation du script (455-469), fusion dans `settings.json` (498-584), variante App Store (588-675), scripts Python embarqués (686-863). Interface dans `SettingsView.swift` (67-137, 463-492). Détection dans `IslandViewContent.swift:961` et `:2686`. |
| Responsabilité | (a) Écrire `nb-hook`, un script Python 3, dans `~/Library/Application Support/NotchBuddy/nb-hook` à chaque lancement (mode 755). (b) Sur demande de l'utilisateur, fusionner 12 événements dans `~/.claude/settings.json` : `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest` (timeout 120 s), `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop` (timeout 10 s). Flux : aperçu du JSON, confirmation, sauvegarde `settings.json.bak-AAAAMMJJ-HHMM`, écriture atomique. (c) Désinstaller. (d) Détecter un timeout obsolète (`hooksNeedUpdate`). |
| Dépendances | Foundation, `python3` présent dans le `PATH` de l'utilisateur, format des hooks de Claude Code. |
| Entrées | `~/.claude/settings.json` existant ; côté script : JSON du hook sur stdin, variables `TERM_PROGRAM`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `__CFBundleIdentifier`. |
| Sorties | `settings.json` modifié et sa sauvegarde ; côté script : pour `PermissionRequest`, un JSON `hookSpecificOutput.decision.behavior` (`allow`, `allow` avec `updatedPermissions`, ou `deny` avec le message « Denied from Coucou ») ; rien pour les autres événements. |
| Risques au refactor | **Point le plus sensible de la migration.** Les hooks de l'application sont reconnus par sous-chaîne : la commande doit contenir `NotchBuddy` ou `coucou`. Ce test apparaît 10 fois : 8 dans `HookServer.swift` (installation, désinstallation, détection, variantes App Store) et 2 dans `IslandViewContent.swift`. Si le dossier de support devient `Yumi`, la commande ne contient plus aucun des deux marqueurs : chaque réinstallation ajoute un doublon, la désinstallation ne retire rien, et l'interface affiche « non configuré ». Le chemin du socket est écrit en dur dans le script Python, indépendamment de `HookServer.socketPath` : les deux doivent changer ensemble. Le script App Store contient en dur `~/Library/Containers/fr.louisraille.Coucou/...`. Les deux scripts Python sont dupliqués à l'identique sauf le chemin. Le script est réécrit à chaque lancement, donc une mise à jour de l'app met à jour le script, mais pas `settings.json`. |

### 10. Socket Unix

| Champ | Détail |
|---|---|
| Fichiers | `HookServer.swift:47-107` (serveur), `:441-451` (`sendLine`), scripts Python (client). |
| Responsabilité | Socket `AF_UNIX` / `SOCK_STREAM` sur `~/Library/Application Support/NotchBuddy/nb.sock`. Un thread d'acceptation, un thread par client. Protocole : un objet JSON terminé par `\n`. Réponse `{"ok":true}` puis fermeture pour tous les événements, sauf `PermissionRequest` dont le descripteur reste ouvert jusqu'à la décision (`{"permissionDecision":"allow|always|deny|ask"}`). |
| Dépendances | Darwin (appels POSIX directs), `Thread`, `AppState` via `Task { @MainActor }`. |
| Entrées | Connexions de `nb-hook`. |
| Sorties | Lignes JSON de réponse ; mutations de `AppState`. |
| Risques au refactor | Le fichier de socket est supprimé puis recréé au démarrage : deux instances (ou Coucou et Yumi avec le même chemin) se volent le socket. Aucun `chmod` ni contrôle du pair : tout processus de l'utilisateur peut envoyer des événements. Pas de nettoyage à la sortie. `sun_path` est limité à 104 octets : un nom de dossier plus long ou un conteneur sandbox peut dépasser. Côté client, les événements ordinaires ont un timeout de 0,3 s et ne lisent pas la réponse (d'où le `SIGPIPE` ignoré dans `AppDelegate`). `HookServer` est `@unchecked Sendable` et `pendingApprovalFD` est écrit depuis le MainActor et lu ailleurs : fragile sous `-strict-concurrency=complete`. |

### 11. Gestion des sessions

| Champ | Détail |
|---|---|
| Fichiers | `HookServer.swift:115-374` (`processEvent`, `processPermissionRequest`, `sendApprovalDecision`), `AppState.swift` (`tasks`, `focusId`, `pendingApproval`), `IslandTypes.swift` (`AgentTask`, `ApprovalInfo`, `PillBadge`). |
| Responsabilité | Traduire les événements de hook en état du personnage : `UserPromptSubmit` donne `thinking`, `PreToolUse` donne `working` avec une ligne de défilement (libellés en français : « Exécute », « Lit », « Modifie »…), `Stop` donne `finished` pendant 5,2 s, `StopFailure` donne `error`, `Notification` contenant « rate limit » donne `ratelimit`. Les approbations ouvrent l'île de force, épinglent la vue, et expirent en `ask` après 115 s. |
| Dépendances | `AppState`, `SoundEngine`, notifications `.hookExpand` et `.hookReveal`. |
| Entrées | Charges JSON des hooks : `hook_event_name`, `session_id`, `cwd`, `tool_name`, `tool_input`, `prompt`, `message`, `permission_suggestions`, `term_program`, `bundle_id`. |
| Sorties | Mise à jour de la tâche `integration_claude` (nom du projet, `sessionCwd`, 20 dernières étapes), badges de pastille, sons, ouverture de l'île. Journal `~/Library/Logs/NotchBuddy/nb.log`. |
| Risques au refactor | **Il n'y a pas de gestion multi-session.** Tous les événements sont aplatis sur une tâche unique d'identifiant `integration_claude` ; `activeSessionId` est écrit mais jamais utilisé pour router. Deux sessions simultanées écrasent mutuellement nom, étapes et état. Une seule approbation en attente : une nouvelle demande renvoie `ask` à la précédente. **Seules les sessions VS Code sont traitées** : si ni `term_program` ni `bundle_id` ne contient `vscode`, l'événement est ignoré et une demande de permission reçoit `ask`. L'identifiant `integration_claude` est une chaîne magique qui apparaît 42 fois dans les sources. `aliasProjectName` et `IslandConst.projectColors` contiennent les projets personnels de l'auteur. Le fichier de log grossit sans rotation. |

### 12. Keychain

| Champ | Détail |
|---|---|
| Fichiers | `ClaudeService.swift:1-101` (`enum Keychain`, `final class KeychainStore`). |
| Responsabilité | `Keychain` : enveloppe de `SecItemAdd/CopyMatching/Delete` pour des mots de passe génériques, service `fr.louisraille.NotchBuddy`, accessibilité `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, non synchronisé. `KeychainStore` : cache en mémoire protégé par `NSLock`, qui lit les 10 clés une seule fois au lancement. |
| Dépendances | Security.framework. |
| Entrées | `set` et `remove` depuis `SettingsView`. |
| Sorties | `get` depuis les pollers, `ClaudeService`, les vues. Clés : `anthropic-api-key`, `resend-api-key`, `resend-from`, `n8n-url`, `n8n-api-key`, `vercel-token`, `github-token`, `stripe-api-key`, `calcom-api-key`, `notion-api-key`. |
| Risques au refactor | La chaîne de service est codée en dur et **n'est pas dérivée de l'identifiant de bundle** : le target App Store (`fr.louisraille.Coucou`) utilise le même nom de service. Changer cette chaîne rend toutes les clés enregistrées invisibles. Changer l'identité de signature ou l'identifiant de bundle provoque une demande d'accès macOS pour les éléments créés par l'ancienne app. Les erreurs `SecItem*` sont ignorées. La liste `allKeys` est une seconde source de vérité : une clé absente de cette liste n'est jamais préchargée. Deux valeurs non secrètes (`resend-from`, `n8n-url`) sont stockées dans le Keychain. |

### 13. Intégrations

| Champ | Détail |
|---|---|
| Fichiers | `StripePoller.swift`, `N8nPoller.swift`, `GithubPoller.swift`, `VercelPoller.swift`, `ResendPoller.swift`, `NotionPoller.swift`, `CalcomPoller.swift`, `ClaudeService.swift:103-358`, `WindowContextCapture.swift`, cartes dans `IslandViewContent.swift:951-2051`, envoi de mail `:581-707`. |
| Responsabilité | Sept pollers identiques dans leur forme : singleton, `DispatchSourceTimer` sur file globale, lecture de la clé, requête `URLSession`, analyse `JSONSerialization`, écriture dans `AppState` sur le thread principal. `ClaudeService` : chat multi-tours et recherche structurée via l'API Messages, outil `web_search_20250305`, modèle `claude-sonnet-4-6`, pièces jointes PDF/image/texte en base64. `WindowContextCapture` : titre de la fenêtre active (API d'accessibilité) et URL du navigateur (AppleScript). Envoi de mail : Resend si configuré, sinon Mail.app par AppleScript. |
| Dépendances | Foundation, `KeychainStore`, `AppState`, `SoundEngine`. |
| Entrées | Voir tableau ci-dessous. |
| Sorties | Champs `@Published` de `AppState`, état et badge de la pastille correspondante, sons `finish` ou `error`. |
| Risques au refactor | Les pollers tournent dès le lancement et ne s'arrêtent jamais (contrairement à ce qu'annonce le README) ; ils sortent tôt si la clé manque. Limite de 4 intégrations actives, VS Code toujours présent. Toutes les pastilles d'intégration ont `source: .n8n`, y compris Stripe ou GitHub. Le prompt système contient « You are Mochi, Louis's personal AI assistant » : à réécrire pour Yumi. L'identifiant de modèle est codé en dur. Les identifiants `integration_*` sont persistés dans `UserDefaults` (`activeIntegrations`) : les renommer casse la préférence enregistrée. Les fichiers déposés sont copiés dans `Application Support/NotchBuddy/inbox` sans jamais être purgés. |

| Intégration | Point d'accès | Période | Authentification |
|---|---|---|---|
| Stripe | `api.stripe.com/v1/balance`, `/v1/charges?limit=3` | 30 s | Basic (clé secrète) |
| n8n | `{url}/api/v1/executions` avec repli `/rest/` | 15 s | En-tête `X-N8N-API-KEY` |
| Vercel | `api.vercel.com/v6/deployments?limit=5` | 30 s | Bearer |
| Resend | `api.resend.com/emails?limit=100` | 60 s | Bearer |
| GitHub | `api.github.com/user`, `/user/repos` | 300 s | Bearer |
| Notion | `api.notion.com/v1/search` | 300 s | Bearer, `Notion-Version: 2022-06-28` |
| Cal.com | `api.cal.com/v2/bookings` | 300 s | Bearer, `cal-api-version: 2024-08-13` |
| Anthropic | `api.anthropic.com/v1/messages` | à la demande | `x-api-key`, `anthropic-version: 2023-06-01` |

### 14. Settings

| Champ | Détail |
|---|---|
| Fichiers | `SettingsView.swift` (fenêtre complète), `SettingsIslandView` dans `IslandViewContent.swift:2681-2765` (réglages rapides dans l'île), persistance dans `AppState.swift:72-204`. |
| Responsabilité | Fenêtre de réglages : clé Anthropic, installation des hooks avec aperçu, clés des 7 intégrations, filtres Vercel et n8n, son et volume, délais, choix des pastilles actives, raccourci global, lancement au démarrage (`SMAppService.mainApp`). |
| Dépendances | SwiftUI, ServiceManagement, `KeychainStore`, `HookServer`, `AppState`. |
| Entrées | Saisie utilisateur. |
| Sorties | `UserDefaults.standard` (domaine = identifiant de bundle) : `soundEnabled`, `soundVolume`, `autoCloseInterval`, `absenceInterval`, `greetThreshold`, `hotkeyEnabled`, `hotkeyFlags`, `hotkeyCode`, `vercelProjectFilter`, `n8nWorkflowFilter`, `activeIntegrations`, `claudeDirectoryBookmark` (App Store). Keychain. `~/.claude/settings.json`. Élément de connexion. |
| Risques au refactor | Les clés `UserDefaults` sont des chaînes dupliquées entre le `didSet` et l'`init` de `AppState`. Les `didSet` s'exécutent aussi pendant le chargement initial, ce qui réécrit la valeur lue. Changer l'identifiant de bundle crée un nouveau domaine de préférences et un nouvel élément de connexion : les réglages existants ne suivent pas. Les champs de clés sont initialisés une fois (`@State`) : ils ne reflètent pas un changement fait ailleurs. Trois réglages n'ont pas d'effet réel (voir écarts). |

### 15. Build system

| Champ | Détail |
|---|---|
| Fichiers | `NotchBuddy/project.yml`, `NotchBuddy/NotchBuddy.xcodeproj/` (généré), `scripts/release.sh`, `.github/workflows/build.yml`, `release.yml`, `windows.yml`. |
| Responsabilité | XcodeGen génère le projet. Deux targets partagent les mêmes sources : `NotchBuddy` (distribution directe, bundle `fr.louisraille.NotchBuddy`, version 0.1.1, non sandboxé, hardened runtime, signature Developer ID manuelle) et `CoucouAppStore` (bundle `fr.louisraille.Coucou`, version 1.0, sandboxé, condition de compilation `APPSTORE`). Swift 6, `-strict-concurrency=complete`, macOS 15.0 minimum. `release.sh` : build Release, zip, `notarytool` avec le profil `coucou-notary`, agrafage, tag git, `gh release create` sur `Louis-CFM/coucou`. L'intégration continue ne fait que compiler sans signer. |
| Dépendances | Xcode 16 ou plus, XcodeGen, `gh`, un certificat Developer ID, un profil de notarisation. |
| Entrées | `project.yml`, sources, ressources. |
| Sorties | `Coucou.app`, `Coucou.zip`. |
| Risques au refactor | `DEVELOPMENT_TEAM: 256AUJ9555` est l'équipe de l'auteur : un build Release échoue sans la remplacer. Le build Debug n'est pas signé (`CODE_SIGNING_ALLOWED: NO`), ce qui a deux effets : les permissions TCC sont redemandées à chaque recompilation, et l'accès Keychain peut demander confirmation. `xcodegen` régénère les `Info.plist` à partir de `project.yml` : c'est l'origine des deux fichiers modifiés non commités dans le clone actuel (numéros de version). Le nom du schéma `NotchBuddy` est référencé dans `CLAUDE.md`, `release.sh` et les deux workflows. `release.sh` pousse un tag et publie : ne pas l'exécuter tel quel depuis le fork. Les 17 blocs `#if APPSTORE` doublent les chemins à tester. |

### 16. Permissions macOS

| Champ | Détail |
|---|---|
| Fichiers | `Resources/Info.plist`, `Resources/Coucou.entitlements`, `Resources/CoucouAppStore.entitlements`, `WindowContextCapture.swift`, `IslandWindowController.swift`, `IslandViewContent.swift:647-697`, `SettingsView.swift:361-412`. |
| Responsabilité | Voir tableau ci-dessous. |
| Dépendances | TCC (base de consentement de macOS), liée à l'identifiant de bundle et à la signature. |
| Entrées | Consentements de l'utilisateur. |
| Sorties | Fonctions disponibles ou silencieusement inactives. |
| Risques au refactor | Le code ne vérifie jamais l'état des permissions (aucun appel à `AXIsProcessTrusted`) et n'affiche aucune demande : sans consentement, la capture de fenêtre renvoie un titre vide, et la touche Échap comme le raccourci global ne font rien, sans message. **Changer l'identifiant de bundle remet tous les consentements à zéro.** La clé `NSAccessibilityUsageDescription` n'est pas une clé reconnue par macOS (le consentement d'accessibilité passe par Réglages Système, sans texte personnalisé). Les textes de justification sont en français alors que le reste de l'interface est en anglais. |

| Permission | Usage | Où | Target |
|---|---|---|---|
| Accessibilité | Titre de la fenêtre active (`AXUIElement`) ; réception des touches par les moniteurs globaux `keyDown` (Échap, raccourci) | `WindowContextCapture`, `IslandWindowController:347,454` | Distribution directe |
| Automatisation (Apple Events) | URL de l'onglet actif (Safari, Chrome, Arc, Firefox, Edge) ; envoi par Mail.app | `WindowContextCapture`, `MailView` ; entitlement `com.apple.security.automation.apple-events` ; `NSAppleEventsUsageDescription` | Distribution directe |
| Liste des fenêtres | `CGWindowListCopyWindowInfo` pour les cadres et PID (ne nécessite pas l'enregistrement d'écran tant que les titres ne sont pas lus) | `IslandWindowController:603-656` | Distribution directe |
| Élément de connexion | `SMAppService.mainApp` | `SettingsView` | Les deux |
| Réseau sortant | Appels API | entitlement `network.client` | App Store (sandbox) |
| Fichiers choisis par l'utilisateur, signets | Accès à `~/.claude` via `NSOpenPanel` et signet à portée de sécurité | `SettingsView`, `HookServer` | App Store (sandbox) |
| Hardened runtime | Requis pour la notarisation | `project.yml` | Distribution directe |

### 17. Dépendances

| Champ | Détail |
|---|---|
| Fichiers | Imports des sources ; `project.yml` (aucune section `packages`). |
| Responsabilité | **Aucune dépendance tierce** côté macOS. Frameworks Apple : Foundation, SwiftUI, AppKit, Combine, CoreGraphics, AVFoundation, Security, ServiceManagement, ApplicationServices, Darwin. |
| Dépendances | Dépendances d'exécution implicites : `python3` sur la machine de l'utilisateur (pour `nb-hook`), Claude Code et son format de hooks, les API des 8 services. Dépendances de développement : XcodeGen, `gh`. |
| Entrées | Sans objet. |
| Sorties | Sans objet. |
| Risques au refactor | macOS ne fournit plus Python par défaut : `/usr/bin/env python3` déclenche l'installation des outils en ligne de commande sur une machine vierge, et tant que Python manque, le hook échoue (sans bloquer Claude Code). Le format de sortie de `PermissionRequest` et l'outil `web_search_20250305` suivent des versions d'API externes qui peuvent évoluer. Le portage Windows a ses propres dépendances (Rust, Tauri 2, Node 20) sans lien avec le target macOS. |

### 18. Licence et fichiers concernés

| Champ | Détail |
|---|---|
| Fichiers | `LICENSE`, `LICENSE-ASSETS.md`, `README.md` (section License). |
| Responsabilité | Double régime. **Code source : MIT**, copyright 2026 Louis Raillé. **Marque et créations : tous droits réservés.** |
| Dépendances | Sans objet. |
| Entrées | Sans objet. |
| Sorties | Obligations pour le fork. |
| Risques au refactor | Voir détail ci-dessous. |

Ce que la licence MIT impose : conserver l'avis de copyright et le texte de la licence dans toute copie ou partie substantielle du logiciel. Yumi doit donc garder `LICENSE` avec la mention de Louis Raillé (on peut ajouter sa propre ligne de copyright pour les modifications).

Ce que `LICENSE-ASSETS.md` réserve, et qu'il est interdit de distribuer sans autorisation écrite :

| Élément réservé | Fichiers concernés | Action pour Yumi |
|---|---|---|
| Noms « Coucou » et « Mochi » | Chaînes dans le code, `project.yml`, plists, docs | Renommer partout |
| Icône d'application et de barre de menus | `NotchBuddy/Assets.xcassets/AppIcon.appiconset/` (10 PNG), `MenuBarIcon.imageset/` (3 PNG) | Remplacer par des créations originales |
| Sons | `NotchBuddy/Resources/sounds/` (28 WAV) | Remplacer par des créations originales |
| Images, GIF, vidéos | `docs/media/`, `design/` (captures, prototype, animations) | Retirer du fork distribué |
| Le personnage Mochi : « its design, look, expressions and animations as a character » | Rendu produit par `BotEngine.swift`, `GreetingCanvasView.swift`, `UploadCanvasView.swift`, `windows/src/mochi/` | Concevoir un personnage distinct |

Point d'attention : le personnage n'est pas un fichier image, il est produit par du code sous licence MIT. Le code est réutilisable, mais le dessin qu'il produit (silhouette, yeux, expressions, chorégraphies) est revendiqué comme création protégée. Renommer « Mochi » en « Yumi » sans changer l'apparence ne satisfait pas `LICENSE-ASSETS.md`. Le README le dit explicitement : « Shipping your own fork? Give it your own name and character. » Usage personnel sans distribution : autorisé tel quel. Pour une distribution, il faut soit un nouveau design, soit une autorisation écrite de l'auteur (contact indiqué dans `LICENSE-ASSETS.md`). Cette lecture n'est pas un avis juridique.

## Écarts entre la documentation et le code

Constats faits pendant la lecture. Ils décrivent le comportement réel à préserver, et les endroits où la documentation ne peut pas servir de référence.

| Sujet | Ce que dit la doc | Ce que fait le code |
|---|---|---|
| Terminaux pris en charge | README : toutes les sessions, « jump to the right terminal » | `HookServer.swift:125-130` ignore tout événement qui ne vient pas de VS Code. Le saut vers Terminal, iTerm, kitty ou Ghostty (`IslandViewContent.swift:149`) est du code mort pour les sessions Claude. |
| Sessions multiples | README : « see every session » | Une seule tâche `integration_claude`, écrasée par la dernière session active. |
| Pollers | README : « paused when nothing is watching » | Les 7 minuteries tournent en continu. |
| CPU à l'arrêt | `CLAUDE.md` : « 0 % CPU when the island is hidden » | Le `Timer` à 60 Hz de `IslandWindowController` ne s'arrête jamais. |
| Délai de fermeture | Réglage « Close after N s » | `autoCloseInterval` ne pilote que la barre de décompte ; la fermeture réelle est fixée à 15 s dans `IslandStateMachine`. |
| Absence | Réglage « Hide after N min » | `absenceInterval` est enregistré mais jamais lu ; `isPresent` vaut toujours `true`. |
| Seuil d'accueil | `greetThreshold` persisté | Jamais lu. |
| Script de hook | `docs/INTEGRATIONS.md` : exécutable Swift dans `bin/nb-hook` | Script Python à la racine du dossier de support. |
| Notarisation | README : « This build isn't notarized by Apple yet » | `release.sh` notarise et agrafe. |
| Dimensions | `docs/SPEC.md` : mode `peek`, compact = encoche + 104, hauteurs de vues variables | Pas de mode `peek`, compact = encoche + 160, hauteur 160 pour la plupart des vues. |
| Notifications inutilisées | Sans objet | `.botGreet` est écoutée mais jamais émise ; `.islandAction` n'est ni émise ni écoutée. |
| Couleur de repli | Commentaire : « stable fallback » | `abs(name.hashValue)` change à chaque lancement (graine de hachage aléatoire de Swift). |

## Inventaire des identifiants à renommer

Chaque ligne indique si le changement est purement cosmétique ou s'il touche des données persistées chez l'utilisateur.

| Identifiant actuel | Emplacements | Nature | Effet d'un changement |
|---|---|---|---|
| `fr.louisraille.NotchBuddy` (bundle) | `project.yml`, `Info.plist`, `CLAUDE.md` | Persisté | Nouveau domaine `UserDefaults`, consentements TCC perdus, nouvel élément de connexion |
| `fr.louisraille.Coucou` (bundle App Store) | `project.yml`, `InfoAppStore.plist`, script Python App Store | Persisté | Chemin du conteneur sandbox, donc chemin du socket |
| `fr.louisraille.NotchBuddy` (service Keychain) | `ClaudeService.swift:7` | Persisté | Clés existantes invisibles |
| `Application Support/NotchBuddy/` | `HookServer.swift:15`, 2 scripts Python, `FileDropView.swift:62` | Persisté | Socket, script de hook, boîte de dépôt |
| `nb.sock`, `nb-hook` | `HookServer.swift`, scripts Python, `SettingsView.swift` | Persisté | Commande enregistrée dans `~/.claude/settings.json` |
| `~/.claude/coucou/nb-hook` | `HookServer.swift:22,604` | Persisté | Variante App Store |
| Marqueurs `"NotchBuddy"` et `"coucou"` | `HookServer.swift` (8 fois), `IslandViewContent.swift:961,2686` | Logique | Reconnaissance des hooks installés |
| `Logs/NotchBuddy/` (`nb.log`, `n8n.log`) | `HookServer.swift:423`, `N8nPoller.swift:260` | Persisté | Cosmétique |
| `notchBuddy.*` (16 noms de notifications) | `IslandWindowController.swift:827-844`, `HookServer.swift:681` | Interne | Aucun effet externe |
| Produit `Coucou`, target et schéma `NotchBuddy`, `CoucouAppStore` | `project.yml`, `release.sh`, workflows, `CLAUDE.md` | Build | Chemins de sortie, commandes de build |
| `Coucou.entitlements`, `CoucouAppStore.entitlements` | `Resources/`, `project.yml` | Build | Référence dans `project.yml` |
| `NotchBuddyApp`, `MochiConst`, `mochiPath`, `drawMochi`, état `.coucou` | Sources Swift | Interne | Aucun effet externe |
| « Open Coucou », titre de la fenêtre de réglages, « Denied from Coucou », textes d'aide | `AppDelegate.swift`, `SettingsView.swift`, scripts Python | Visible | Cosmétique |
| Prompt « You are Mochi, Louis's personal AI assistant » | `ClaudeService.swift:122` | Visible par le modèle | Ton des réponses du chat |
| `projectColors`, `aliasProjectName` | `IslandTypes.swift:113`, `HookServer.swift:378` | Données personnelles de l'auteur | Couleurs des projets |
| `DEVELOPMENT_TEAM: 256AUJ9555`, profil `coucou-notary`, dépôt `Louis-CFM/coucou` | `project.yml`, `release.sh`, README, site | Build et diffusion | Signature et publication |

## Plan de migration vers Yumi

Principe : séparer strictement les étapes qui ne changent aucun octet de comportement de celles qui changent une identité persistée. Un commit par étape, build Debug vérifié à chaque fois.

### Décisions à prendre avant de commencer

1. **Identifiant de bundle et identité de signature** de Yumi (par exemple un domaine inversé qui vous appartient), et équipe Apple Developer.
2. **Design du personnage Yumi** : nouveau dessin, ou demande d'autorisation à l'auteur. Tant que ce point n'est pas réglé, Yumi peut être construit et utilisé en privé, pas distribué.
3. **Target App Store** : le conserver double tous les chemins liés aux hooks. Le retirer simplifie fortement, mais c'est une suppression de fonctionnalité à décider.
4. **Portage Windows** (`windows/`) : le retirer du fork ou le laisser de côté. Il n'a aucun lien de compilation avec le target macOS.
5. **Cohabitation avec Coucou** sur la même machine : si elle doit être possible, Yumi ne doit jamais toucher aux hooks de Coucou.

### Étape 0 : état de référence

- Créer une branche de travail. Commiter ou écarter les deux `Info.plist` modifiés localement et les schémas non suivis (ils viennent d'un `xcodegen` déjà exécuté).
- Compiler en Debug avec la commande du `CLAUDE.md` et confirmer que le build passe sans avertissement nouveau.
- Comme il n'y a aucun test, dérouler à la main et noter le résultat de cette liste, qui servira de recette après chaque étape : accueil au lancement ; survol de l'encoche ; clic pour ouvrir ; repli après 15 s puis masquage après 60 s ; installation des hooks avec aperçu et sauvegarde ; session Claude Code dans VS Code (étapes, fin, erreur) ; approbation Allow, Deny, Always ; dépôt d'un fichier puis question et envoi par mail ; glisser du personnage sur une fenêtre ; chat ; trois clics rapides ; au moins une intégration ; sons ; raccourci global ; lancement au démarrage.

### Étape 1 : centraliser l'identité, valeurs inchangées

Refactor pur. Créer un fichier unique, par exemple `AppIdentity.swift`, qui expose : nom d'affichage, nom du personnage, service Keychain, nom du dossier de support, noms du socket et du script, dossier de logs, liste des marqueurs de hooks, préfixe des notifications. Remplacer chaque littéral par une référence à ces constantes, **en gardant exactement les valeurs actuelles**.

- Générer les deux scripts Python à partir d'un seul gabarit paramétré par le chemin du socket, pour supprimer la duplication et le chemin écrit en dur.
- Regrouper les 10 tests de marqueur en une seule fonction.
- Critère de réussite : le script `nb-hook` généré et le JSON de hooks produit sont identiques octet pour octet à ceux d'avant. La recette de l'étape 0 passe.

### Étape 2 : remplacer les créations protégées

- Icône d'application et icône de barre de menus : nouveaux fichiers aux mêmes noms et dimensions dans `Assets.xcassets` (aucun changement de code ni de `project.yml`).
- Sons : 28 nouveaux WAV portant exactement les mêmes noms. `SoundEngine` reste intact.
- Personnage : adapter le dessin dans les **trois** moteurs de rendu (`BotEngine`, `GreetingCanvasView`, `UploadCanvasView`) pour que Yumi soit cohérent entre l'accueil, l'usage normal et le dépôt. Garder l'interface publique de `BotEngine` (`setState`, `triggerEmote`, `slap`, `gulp`, `anim`) pour ne rien casser autour.
- Retirer `docs/media/` et `design/` du fork distribué, ou les remplacer par les vôtres. Attention : `CLAUDE.md` désigne `design/` comme référence visuelle ; mettre cette règle à jour.

### Étape 3 : basculer l'identité persistée

C'est la seule étape qui change ce qui est stocké chez l'utilisateur. Comme Yumi est une nouvelle application, la voie la plus sûre est de partir d'un état vierge plutôt que de migrer les données de Coucou.

- Dans `AppIdentity` : nouveau service Keychain, nouveau dossier de support (`Application Support/Yumi`), nouveaux noms de socket et de script, nouveau dossier de logs.
- **Reconnaissance des hooks** : ne pas se contenter de remplacer le marqueur par `yumi` avec un test `contains`, qui correspondrait à n'importe quel chemin contenant ce mot (un utilisateur nommé `yumi` par exemple). Comparer plutôt à la commande exacte générée par l'application.
- Cohabitation : Yumi ne retire que ses propres hooks. Si au contraire Yumi doit remplacer Coucou, garder temporairement les anciens marqueurs dans la liste de nettoyage et l'annoncer dans l'aperçu avant écriture.
- Socket distinct de celui de Coucou, pour que les deux applications ne se le disputent pas.
- Vérifier la longueur du chemin du socket (limite de 104 octets), surtout si le target sandboxé est conservé.
- Conséquences attendues et normales : clés d'API à ressaisir, consentements Accessibilité et Automatisation à redonner, hooks à réinstaller, élément de connexion à réactiver.

### Étape 4 : build et projet

- `project.yml` : nom du projet, des targets et des schémas, `PRODUCT_NAME`, `CFBundleName`, `CFBundleDisplayName`, identifiants de bundle, `DEVELOPMENT_TEAM`, noms des fichiers d'entitlements, versions. Renommer le dossier `NotchBuddy/` et régénérer avec `xcodegen`. Ne jamais éditer le `.xcodeproj` à la main.
- Décider si le `.xcodeproj` reste versionné ; si non, l'ajouter au `.gitignore`.
- `scripts/release.sh` : nom de l'app et du zip, profil de notarisation, dépôt GitHub cible, texte de la release. Ne pas l'exécuter avant d'avoir tout remplacé : il pousse un tag et publie.
- `.github/workflows/build.yml` et `release.yml` : chemins et nom du schéma. `windows.yml` : supprimer si le portage Windows est retiré.

### Étape 5 : textes visibles et données personnelles de l'auteur

- Menu, titre de la fenêtre de réglages, messages d'aide, message de refus renvoyé à Claude Code.
- Prompt système du chat dans `ClaudeService` (nom du personnage et prénom de l'auteur).
- `IslandConst.projectColors` et `aliasProjectName` : vider ou remplacer par vos projets.
- Textes de justification des permissions dans `project.yml`.
- Renommages internes sans effet externe, à faire en dernier et séparément : `NotchBuddyApp`, `MochiConst`, `drawMochi`, l'état `.coucou`, le préfixe `notchBuddy.` des notifications.

### Étape 6 : documentation et licence

- Conserver `LICENSE` avec l'avis de copyright d'origine ; ajouter votre ligne de copyright.
- Remplacer `LICENSE-ASSETS.md` par un texte qui couvre les créations de Yumi, ou le supprimer. Mentionner dans le README que Yumi est un fork de Coucou.
- Réécrire `README.md`, `CONTRIBUTING.md`, `CLAUDE.md` (dont la règle « Keep the bundle identifier `fr.louisraille.NotchBuddy` », devenue fausse), `docs/*.html` (site, confidentialité, conditions, mentions légales au nom de l'auteur), modèles d'issues.
- Corriger ou retirer `docs/SPEC.md` et `docs/INTEGRATIONS.md`, qui décrivent un état antérieur du code.

### Étape 7 : recette finale

Sur un compte utilisateur sans Coucou installé, puis avec Coucou installé si la cohabitation est voulue : rejouer la liste de l'étape 0, et vérifier en plus que `~/.claude/settings.json` ne contient qu'une entrée Yumi par événement après deux installations successives, que la désinstallation la retire, que le Keychain contient un service Yumi et aucun élément Coucou nouveau, et que `grep -ri "coucou\|mochi\|notchbuddy\|louis"` sur le dépôt ne renvoie plus que l'avis de copyright et la mention du fork.

### Hors périmètre de la migration

À traiter après, car ce sont des changements de comportement : prise en charge des terminaux autres que VS Code, vraies sessions multiples, arrêt de la boucle 60 Hz et des pollers quand l'île est masquée, raccordement des réglages sans effet, réaction aux changements d'écran, vérification et demande des permissions, rotation des logs, purge de la boîte de dépôt, découpage de `IslandViewContent.swift`, ajout de tests sur `IslandStateMachine` (seul composant sans dépendance, donc testable immédiatement).
