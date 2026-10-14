# Handoff : reprendre la coordination de Yumi

À lire en premier par toute nouvelle session de coordination. Court exprès : le reste est dans le dépôt.

## Le projet en une phrase

Yumi, compagnon macOS dans la notch (Swift 6, SwiftUI, AppKit, aucune dépendance). Alpha publique gratuite. Voir README.md pour les fonctions, docs/journal.md pour les décisions, docs/archive/post-alpha-status.md et docs/backlog.md pour la suite.

## État au 14 octobre 2026

- `main` : version 0.1.0-alpha.10, 1016 tests, CI verte. Le tag v0.1.0-alpha.10 a été déplacé une fois (correctif Mail ajouté après publication) : la release est repassée en brouillon, à republier par l'utilisateur si ce n'est pas fait.
- Alpha 10 : Yumi marche sans rien configurer. Moteur choisi tout seul : celui de la personne, sinon le modèle d'Apple (FoundationModels, macOS 26), sinon le mode simple (AgentRuntime/SimpleMode, déterministe, sans réseau). Premier lancement sans question sur les modèles.
- Mail (app Mail d'Apple) : ne jamais filtrer la boîte avec `whose` (40 000 mails : Mail figé plus de 2 min). Le texte d'un mail se lit à sa place (`MailAppPlace`). Même ainsi, chaque Apple Event peut prendre plusieurs secondes sur une grosse boîte Gmail.
- Non testé en réel : le modèle d'Apple (pas encore téléchargé sur le Mac de l'utilisateur), le correctif Mail, l'alpha 10 sur un Mac sans Apple Intelligence (MacBook Air M1 d'une personne non développeuse), liste et cochage Notion, moteurs OpenAI et Ollama, Mac sans notch.

## Règles

- Répondre en français, sans tirets longs (ni en incise, ni en séparateur).
- Dépôt : /Users/thewise/yumi, remote git@github.com:estebanbaigts/Yumi.git. Commits avec `user.email = 91676362+estebanbaigts@users.noreply.github.com`, terminés par la ligne Co-Authored-By demandée par le harnais.
- Ne jamais reprendre de nom, personnage, icônes ou sons d'un autre projet. LICENSE et ATTRIBUTION.md doivent rester (licence MIT du code d'origine).
- Les onglets travaillent chacun sur une branche, dans un worktree neuf créé depuis /Users/thewise/yumi, poussent, et ne fusionnent jamais. La coordination vérifie, teste et fusionne.
- Xcode reformate parfois les fichiers `Localization/*.xcstrings` pendant une compilation : `git checkout -- Yumi/Sources/App/Localization/` avant toute fusion si ce sont les seuls changements.
- Ajouter une traduction : insérer l'entrée dans Localizable.xcstrings sans reformater le fichier (json.dumps avec indent=2, ensure_ascii=False, ordre conservé). Un test échoue s'il manque l'anglais d'une clé.

## Builds et release

- Tests : `cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug test CODE_SIGNING_ALLOWED=NO`. La CI les lance à chaque push : inutile de les relancer en local à chaque fusion, sauf avant une release.
- Build locale pour l'utilisateur : Release avec `CODE_SIGNING_ALLOWED=NO`, copiée dans /Users/thewise/yumi/build/Yumi.app, puis signée avec le certificat local « Yumi Local » (`codesign --force --deep --options runtime --entitlements Yumi/Resources/Yumi.entitlements -s "Yumi Local"`). Sans signature, macOS oublie les autorisations. L'utilisateur peut aussi utiliser /Applications/Yumi.app (une release installée) : ne pas la remplacer sans accord.
- Release : monter `YumiDisplayVersion` et `CFBundleVersion` dans Yumi/project.yml, pousser, puis pousser un tag `v<version>`. Le workflow .github/workflows/release.yml teste, compile avec le Xcode le plus récent du runner, signe avec Yumi Local (secrets YUMI_LOCAL_P12 et YUMI_LOCAL_P12_PASSWORD), zippe avec release/LISEZ-MOI.txt et release/README.txt, publie SHA256SUMS.txt et une attestation, et crée un brouillon. L'utilisateur colle les notes (bilingues, format des alphas précédentes) et publie.
- Le runner a un Xcode plus ancien que le Mac : le compilateur y est plus strict sur la concurrence. Si la CI échoue au Test en moins de 2 minutes, c'est une erreur de compilation : lire le journal du job dans Chrome (l'API publique ne donne pas les journaux).
- Copier du texte accentué dans le presse-papiers : `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pbcopy`.

## Pas de budget pour l'instant

Pas de compte Apple Developer (99 €) : pas de notarisation ni d'App Store. Distribution par les releases GitHub.

## Sessions de travail (groupe « Yumi » de la barre latérale)

- **Product direction** : cœur (agent, permissions, outils, moteurs, Notion).
- **Île interface redesign** : île, réglages, modules (dont GitHub et Claude Code).
- **Personnage multi-moteurs** : le personnage (BotEngine, Character/).
- **Montage Remotion** : vidéos (motion/), site (site/).
Pour économiser l'usage : ouvrir une session neuve par chantier plutôt que réutiliser une longue, un chantier à la fois, Sonnet pour les tâches simples.

## Retours et personnes

- Retours : formulaire Tally https://tally.so/r/Me9lvA (champ caché `version`) et issues GitHub.
- Laurent a relu le code (contexte de fenêtre, chaîne de release, risque des écritures hors du Mac). Paul a testé sur un 13 pouces (menu clic droit, triple Maj, Notion). Les créditer dans les notes quand leurs retours sont traités.

## Prochaines étapes probables

1. Faire tester l'alpha 10 sur le MacBook Air M1, sans aide : noter où ça bloque.
2. Vérifier le correctif Mail en réel ; si Mail se fige encore, faire passer le brouillon avant la relecture de la boîte et relire moins souvent.
3. Essayer le modèle d'Apple une fois téléchargé (choix des outils sur des demandes simples).
4. « Lire puis agir » : prépare ma journée, avec un aperçu du plan (docs/archive/post-alpha-status.md).
5. Spécification des modules externes (déclarés dans un fichier, derrière la même porte d'accord), à valider par l'utilisateur avant de coder.
6. Commits GitHub dépliables, Mac sans notch.
