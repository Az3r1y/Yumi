# Posts LinkedIn de Yumi

Textes prêts à coller. Sur LinkedIn, c'est Esteban qui parle (le créateur), pas Yumi : première personne, ton de quelqu'un qui construit, phrases courtes, sans emoji ni fausse excitation. Rien n'annonce de date ni de fonction qui n'existe pas encore.

Les courtes vidéos sont au format 4:5 (1080 × 1350), celui que le fil LinkedIn affiche le plus grand. La masterclass existe en 16:9 et en 9:16. Elles se rendent avec :

```console
npx remotion render Masterclass-16x9 out/linkedin/masterclass-16x9.mp4
npx remotion render Masterclass-9x16 out/linkedin/masterclass-9x16.mp4
npx remotion render LinkedIn-Film out/linkedin/linkedin-film.mp4
npx remotion render LinkedIn-Permission out/linkedin/linkedin-permission.mp4
npx remotion render LinkedIn-Lancement out/linkedin/linkedin-lancement.mp4
```

Ordre conseillé : un post par semaine, du plus large au plus technique. Le lien GitHub va dans le premier commentaire plutôt que dans le texte : LinkedIn montre moins les posts qui renvoient ailleurs.


## La masterclass : l'alpha est sortie

Vidéo : `out/linkedin/masterclass-16x9.mp4` (1 min 58), ou `masterclass-9x16.mp4` pour le téléphone. Sous-titrée dans l'image : elle se comprend sans le son.

> La première alpha de Yumi est sortie.
>
> Yumi est un petit compagnon qui vit dans la notch du Mac. Il suit mes sessions Claude Code et me laisse approuver leurs demandes sans changer de fenêtre. Je lui parle, il agit : un fichier, un rappel, un créneau dans l'agenda, un focus, le résumé de ma journée. Toujours après mon accord, et il vérifie ensuite que c'est bien fait.
>
> Pas de compte, pas de télémétrie. Ce qu'il retient reste dans un fichier texte sur le Mac.
>
> La vidéo montre ce qu'il fait, puis l'installation pas à pas. Une étape surprend : cette alpha n'est pas encore notarisée par Apple, donc macOS la bloque une première fois. Réglages Système, Confidentialité et sécurité, « Ouvrir quand même », et c'est réglé.
>
> Il faut macOS 15 ou plus récent, et Claude Code pour le chat et les actions (chaque demande compte dans votre forfait Claude Code).
>
> Si vous l'essayez, dites-moi ce qui coince : il y a un bouton « Envoyer un retour » dans ses réglages.
>
> #macOS #ClaudeCode #OpenSource #IndieDev #Swift

**Premier commentaire**

> L'alpha est ici : https://github.com/estebanbaigts/Yumi/releases/tag/v0.1.0-alpha
> Le code : https://github.com/estebanbaigts/Yumi
> Yumi part du code open source de Coucou, de Louis Raillé, sous licence MIT. Merci à lui.

**Texte alternatif**

> Une vidéo de deux minutes. Un petit personnage noir en forme de goutte, avec deux grands yeux et un contour lumineux, s'allume dans la notch d'un MacBook. On le voit montrer une demande de permission de Claude Code, écrire un fichier, afficher la musique et GitHub, rappeler de faire une pause. Suivent les promesses de confidentialité, puis les cinq étapes d'installation : télécharger le zip, le glisser dans Applications, l'ouvrir quand même depuis les Réglages Système, le voir apparaître dans la notch, installer les hooks Claude Code.


## Post 1 : la présentation

Vidéo : `out/linkedin/linkedin-film.mp4` (27,6 s).

> Il y a un trou noir en haut de mon MacBook. J'ai décidé d'y mettre quelqu'un.
>
> Il s'appelle Yumi. C'est un petit compagnon qui vit dans la notch du Mac.
>
> Il suit mes sessions Claude Code pendant que je fais autre chose. Il me montre la musique en cours, mon prochain rendez-vous, mes rappels du jour. Je lui parle, il agit, et il me demande toujours avant de toucher à quoi que ce soit. Et au bout de deux heures sans pause, c'est lui qui me le fait remarquer.
>
> C'est une app macOS native, en Swift 6, sans aucune dépendance. Le personnage est dessiné en code, image par image. Pas de télémétrie : rien ne quitte le Mac, sauf vers les services qu'on branche soi-même.
>
> Le projet est open source, et une première alpha s'installe en quelques clics depuis la page des releases.
>
> Qu'est-ce que vous lui feriez faire, vous ?
>
> #macOS #Swift #ClaudeCode #OpenSource #IndieDev

**Premier commentaire**

> Le code est ici : https://github.com/estebanbaigts/Yumi
> Yumi part du code open source de Coucou, de Louis Raillé, sous licence MIT. Merci à lui.


## Post 2 : les permissions depuis la notch

Vidéo : `out/linkedin/linkedin-permission.mp4` (4,25 s, elle boucle).

> Le moment le plus agaçant quand on travaille avec un agent de code : il s'arrête, il attend une autorisation, et on ne le voit pas parce qu'on est dans une autre fenêtre.
>
> Dans Yumi, quand Claude Code demande une permission, l'île de la notch s'ouvre. On voit la commande exacte, on accepte ou on refuse d'un clic, sans changer de fenêtre.
>
> Trois règles que je me suis fixées :
>
> 1. Rien n'est accepté sans un clic explicite.
> 2. Si on ne répond pas, la question repart dans Claude Code comme d'habitude. Yumi ne bloque jamais l'agent.
> 3. Mes réglages Claude Code ne sont jamais écrasés : sauvegarde datée, fusion, et le changement est montré avant d'être écrit.
>
> Ça paraît petit. Sur une journée avec trois ou quatre sessions en parallèle, ça change tout.
>
> #ClaudeCode #AIAgents #DeveloperExperience #macOS

**Premier commentaire**

> Le code des hooks est public : https://github.com/estebanbaigts/Yumi


## Post 3 : un personnage dessiné en code

Vidéo : `out/linkedin/linkedin-lancement.mp4` (5 s).

> Yumi n'a aucune image. Pas un PNG, pas une animation exportée.
>
> Son corps, ses yeux, la lumière sur son contour : tout est dessiné en code, image par image, en SwiftUI. Ses pupilles suivent la souris. La lumière de son contour prend la couleur de ce qui se passe : au repos un dégradé bleu, violet, rose, ambre quand un agent attend une réponse, vert quand c'est fini.
>
> La contrainte qui a tout décidé : l'île de la notch est noire, et Yumi aussi. Un corps noir sur fond noir est invisible. Toute sa silhouette tient donc dans deux choses, ses yeux et ce liseré de lumière, y compris quand il ne fait que vingt points de large.
>
> Même la vidéo est faite comme ça : elle est écrite en React avec Remotion, sans logiciel de montage.
>
> #SwiftUI #MotionDesign #Remotion #macOS #IndieDev

**Premier commentaire**

> Tout est open source : https://github.com/estebanbaigts/Yumi


## Avant de publier

- Regarder chaque vidéo avec et sans le son : sur LinkedIn, la plupart des gens la voient muette, et le texte dans l'image doit suffire.
- Choisir la miniature dans LinkedIn au moment de l'envoi : une image où Yumi a les yeux ouverts.
- Ajouter un texte alternatif. Pour le post 1, celui de `legendes.md` convient.
- Vérifier que le dépôt GitHub est bien public avant de mettre le lien.


## Post 4 : une journée de dev avec Yumi

Vidéo : `out/linkedin/journee-4x5.mp4` (24,8 s, 4:5), ou `journee-9x16.mp4`. Sous-titrée dans l'image, faite pour être vue en entier.

Rendu :

```console
npx remotion render LinkedIn-Journee-4x5 out/linkedin/journee-4x5.mp4
npx remotion render LinkedIn-Journee-9x16 out/linkedin/journee-9x16.mp4
```

Toutes les images de l'île sont de vraies prises : l'app filmée sur l'écran du MacBook dans son mode tournage (scènes 10 à 12 de `Island/IslandStudio.swift`, branche `yumi/tournage`), avec ses données d'exemple, recadrées autour de la notch, jamais redessinées. La phrase du temps libre est celle qu'écrit `get_today`. Le film le dit dans l'image : « Filmé sur mon Mac · mode tournage, données d'exemple ».

Prises : `public/prises/journee-temps-libre.mp4`, `journee-matcha.mp4`, `journee-sessions.mp4`.

Deuxième mise en scène, pour varier : `out/linkedin/journee-edito-4x5.mp4` et `journee-edito-9x16.mp4` (24,8 s). Mêmes prises, mêmes sous-titres, en page de magazine : fond papier, grands titres à l'encre que la prise recouvre en partie, prises décalées qui débordent du cadre, page verte matcha pour le matcha, transitions par masques.

```console
npx remotion render LinkedIn-Journee-Edito-4x5 out/linkedin/journee-edito-4x5.mp4
npx remotion render LinkedIn-Journee-Edito-9x16 out/linkedin/journee-edito-9x16.mp4
```

> Je demande à mon Mac combien de temps libre j'ai demain. Il me répond depuis la notch.
>
> Yumi, le petit compagnon que je construis, lit maintenant l'agenda de n'importe quel jour des deux semaines à venir et trouve les créneaux libres. L'agenda reste sur le Mac : il n'est jamais envoyé au chat.
>
> Pendant qu'un agent Claude Code travaille, il boit son matcha. Et quand une session attend une autorisation, je réponds depuis la notch, sans quitter ce que je fais.
>
> L'alpha est gratuite et open source, pour macOS 15 et plus. Le lien est en commentaire.
>
> Vous lui demanderiez quoi, vous ?
>
> #macOS #ClaudeCode #IndieDev #OpenSource

**Premier commentaire**

> L'alpha : https://github.com/estebanbaigts/Yumi/releases/tag/v0.1.0-alpha
