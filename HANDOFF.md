# Handoff : reprendre la coordination de Yumi

À lire en premier par toute nouvelle session de coordination. Court exprès : le reste est dans le dépôt.

## Le projet en une phrase

Yumi, compagnon macOS dans la notch (Swift 6, SwiftUI, AppKit, aucune dépendance). Alpha publique gratuite. Voir README.md pour les fonctions, YUMI.md pour les décisions, docs/POST_ALPHA_STATUS.md et docs/BACKLOG.md pour la suite.

## État au 8 octobre 2026

- `main` : version 0.1.0-alpha.6, 837 tests, CI verte. Alpha 6 construite par la CI (brouillon de release à publier par l'utilisateur si ce n'est pas fait).
- Sur `main` mais pas encore dans une release : la grille de contributions GitHub en un seul Canvas (64ec4e8, correctif CPU).
- Non testé en réel : contributions GitHub, liste et cochage Notion, moteurs OpenAI et Ollama, Mac sans notch.

## Règles

- Répondre en français, sans tirets longs (ni en incise, ni en séparateur).
- Dépôt : /Users/thewise/yumi, remote git@github.com:estebanbaigts/Yumi.git. Commits avec `user.email = 91676362+estebanbaigts@users.noreply.github.com`, terminés par la ligne Co-Authored-By demandée par le harnais.
- /Users/thewise/coucou est en lecture seule. Ne jamais reprendre le nom, le personnage, les icônes ou les sons de Coucou. LICENSE et ATTRIBUTION.md doivent rester (MIT).
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

1. Publier l'alpha 6, la tester en vrai (GitHub contributions, Notion).
2. « Lire puis agir » : prépare ma journée, avec un aperçu du plan (docs/POST_ALPHA_STATUS.md).
3. Spécification des modules externes (déclarés dans un fichier, derrière la même porte d'accord), à valider par l'utilisateur avant de coder.
4. Commits GitHub dépliables, Mac sans notch.
