# Vidéo de présentation de Yumi

Plan de tournage pour un Reel Instagram, un TikTok et une série de stories. Brouillon du 2 octobre 2026.

## Le principe

Format vertical 9:16, 20 à 25 secondes, compréhensible sans le son. Une seule idée : **ton Mac a un nouveau colocataire**. On montre Yumi vivre, pas une liste de fonctions.

## Le problème à résoudre : la notch est minuscule et horizontale

L'île fait quelques centimètres en haut d'un écran large, et la vidéo est verticale. Trois façons de la filmer, à combiner :

1. **Capture d'écran recadrée** : on enregistre l'écran, on recadre serré sur la notch, et on place cette bande dans le tiers haut de l'image verticale, avec le texte en dessous.
2. **Plan filmé au téléphone** du haut du MacBook, de près : c'est ce qui prouve que c'est réel, et c'est ce qui marche le mieux sur ces plateformes.
3. **Yumi en grand, hors de l'écran** : son personnage seul sur fond noir, pour l'accroche et la fin.

## Le Reel et le TikTok (22 secondes)

| Temps | Image | Texte à l'écran |
|---|---|---|
| 0 à 2 s | Noir. Deux yeux s'ouvrent, regardent à gauche, à droite | « Il vit dans ton Mac. » |
| 2 à 5 s | La lumière s'allume, Yumi apparaît et salue (le lancement réel, filmé au téléphone) | « Voici Yumi. » |
| 5 à 9 s | Claude Code demande une permission, un clic sur le bouton vert, Yumi fête ça | « Il surveille tes agents. » |
| 9 à 12 s | La musique démarre, il met son casque et bat la mesure | « Il écoute avec toi. » |
| 12 à 15 s | On lui écrit, la réponse s'écrit en direct, un fichier se crée | « Tu lui parles, il agit. » |
| 15 à 18 s | Île repliée, il dit de lui-même « Deux heures d'affilée. Une pause ? » | « Il pense à toi. » |
| 18 à 20 s | Enchaînement rapide de ses humeurs : café, nuage, lunettes, dodo | « Et il a son caractère. » |
| 20 à 22 s | Yumi en grand, clin d'œil, sa lumière | « Yumi. Bientôt. » |

Variante d'accroche pour TikTok, plus directe : commencer par le plan le plus surprenant (il se réveille dans la notch) avec « POV : ton Mac a un colocataire ».

## Les stories (cinq écrans)

1. Les yeux dans le noir. « Devine qui arrive. »
2. Le lancement complet, sans texte.
3. Une seule fonction en gros plan : la permission autorisée d'un clic.
4. Ses humeurs, avec un sondage : « Laquelle te ressemble le lundi ? »
5. Yumi qui salue. « Sortie bientôt. Active les notifications. »

## Ce qu'il faut pour tourner

- **Un mode tournage dans l'app** : des données d'exemple propres (aucun vrai rendez-vous, aucune vraie session), et chaque scène déclenchée par une touche, pour refaire une prise à volonté. Les démonstrations internes existent déjà ; il faut les rendre pilotables.
- **Un fond d'écran sobre et sombre**, barre de menus vidée, Dock masqué.
- **Le téléphone sur trépied** pour les plans filmés, écran du Mac à luminosité maximale, pièce sombre.
- **Une musique libre de droits** ou un son tendance de la plateforme. Les sons de l'app sont provisoires : on ne s'appuie pas dessus.

## Tourner

Le mode tournage rejoue chaque plan sur une touche, avec des données d'exemple (prénom « Alex », projet « Atelier », aucun vrai rendez-vous, morceau ou message). Il coupe les sons, le repli automatique et les réactions à la souris, et remplace la cigarette par le café.

**Lancer**

```
cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug build
YUMI_STUDIO=1 YUMI_STUDIO_SCALE=2 /chemin/vers/Yumi.app/Contents/MacOS/Yumi
```

`YUMI_STUDIO_SCALE` agrandit l'île (1,5 ou 2) pour qu'elle reste nette une fois recadrée ; sans lui, elle garde sa taille normale. Le mode marche aussi avec un build Release. `YUMI_STUDIO_SHOTS=/un/dossier` joue tous les plans à la suite et enregistre une image deux fois par seconde, pour vérifier sans filmer.

**Les touches**

| Touche | Plan |
|---|---|
| 1 | Le lancement complet |
| 2 | La permission, le clic sur le vert, la célébration |
| 3 | La musique et le casque |
| 4 | Le chat qui s'écrit, puis le fichier créé |
| 5 | « Deux heures d'affilée. Une pause ? », île repliée |
| 6 | Les humeurs : café, nuage, lunettes, dodo |
| 7 | Yumi seul dans sa lumière, clin d'œil |
| 8 | Les scènes GitHub : étoile, fork, fusion |
| 9 | Le départ |
| Espace | Rejoue le dernier plan |
| Échap | Remet Yumi au repos, île repliée |
| R | Replie l'île |

Les clics des plans sont joués par le mode : le curseur n'a pas à apparaître. Les touches répondent même quand une autre application est au premier plan, à condition que Yumi ait l'autorisation Accessibilité (Réglages Système, Confidentialité et sécurité) ; sinon, clique une fois sur l'île pour lui donner le clavier.

**Enregistrer en recadrant sur la notch**

1. Fond d'écran sombre, Dock masqué, barre de menus masquée automatiquement.
2. Cmd + Maj + 5, « Enregistrer la partie sélectionnée », et trace un cadre vertical 9:16 centré sur la notch, le haut du cadre collé au bord de l'écran. Dans les options, décoche « Afficher les clics de souris ».
3. Lance l'enregistrement, pose le curseur hors du cadre, joue les plans au clavier.
4. Au montage, place cette bande dans le tiers haut de l'image verticale. À l'échelle 2, l'île ouverte fait environ 1 320 points de large : un cadre de 1 400 points de large la contient avec un peu d'air.

Sur un écran à encoche, l'encoche physique n'apparaît pas dans une capture d'écran : l'île y est entière. Pour le plan filmé au téléphone, garde l'échelle normale, sinon l'île dépasse de l'encoche réelle.

## À ne pas montrer

- **Ce qui n'existe pas encore** : Notion, n8n, Make, ChatGPT, le catalogue de quarante modules.
- **La cigarette.** Instagram et TikTok restreignent les contenus qui montrent du tabac, et la portée de la vidéo peut en souffrir. On montre le café à la place.
- **De vraies données personnelles** : agenda, noms de fichiers, messages.

## Avant de publier

- Vérifier que le nom « Yumi » est libre pour une app.
- Décider de ce qu'on promet : « bientôt », sans date tant que la signature Apple n'est pas réglée.
- Prévoir où envoyer les gens : un compte dédié ou une liste d'attente, pour ne pas perdre l'intérêt suscité.
