# Le site de Yumi

Une seule page statique, servie par GitHub Pages à l'adresse https://estebanbaigts.github.io/Yumi/. Rien à installer pour la servir : HTML, CSS, un fichier JavaScript déjà construit, des images et la vidéo.

## Prévisualiser

```console
cd site
python3 -m http.server 8000
```

Puis ouvrir http://localhost:8000. Tous les chemins sont relatifs : la page marche de la même façon sous `/Yumi/` sur GitHub Pages.

## Le Yumi vivant

Le personnage du haut de la page est dessiné par le moteur et le rendu du film (`motion/src/yumi`), avec Preact à la place de React. `assets/yumi.js` est le résultat, commité. Après une modification de `src/main.tsx` ou du moteur :

```console
cd site
npm install
npm run build
```

Il se réveille à l'ouverture, respire, cligne, suit le pointeur et rebondit quand on le touche. Avec « réduire les animations », il reste immobile, éveillé.

## Ce que la page charge

Uniquement des fichiers de ce dossier, plus une requête vers l'API de GitHub pour trouver la dernière release (une pre-release n'est pas « latest » pour GitHub) ; sans réponse, le bouton reste sur la page des releases. Pas de cookie, pas de suivi, pas de police ni de script venus d'ailleurs. La politique de sécurité de la page (balise `Content-Security-Policy`) l'impose.

## Publier

Le workflow `.github/workflows/pages.yml` publie ce dossier à chaque push sur `main` qui le touche. Tant que GitHub Pages n'est pas activé, il le dit et ne fait rien. Pour l'activer, une seule fois : Settings > Pages > Build and deployment > Source : **GitHub Actions**.

## Les médias

`media/yumi-masterclass.mp4` est la masterclass du film (`motion/`, composition `Masterclass-16x9`) réencodée pour le web en 1080p, 30 images par seconde. Les images de `media/` en sont tirées. Le nom Yumi, le personnage et le film restent réservés : voir `LICENSE-ASSETS.md` à la racine.
