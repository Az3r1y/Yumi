# Backlog

Idées classées P3 (expérimental) et P4 (futur), rangées ici pour ne pas interrompre le chantier en cours. Chacune devra être justifiée par le cœur agent, la fiabilité, la sécurité, l'UX ou un besoin réel avant d'être commencée.

| Classe | Idée | Condition préalable |
|---|---|---|
| P3 | Browser agent (ouvrir, lire, chercher, cliquer, remplir) avec actions sensibles protégées. | Boucle observer puis planifier stable ; balisage du contenu externe dans les sorties d'outils. |
| P3 | MCP comme transport d'outils, toujours derrière Tool Registry et `PermissionManager`. | Browser stabilisé. |
| P3 | Interrupteurs de contexte par type (app, fenêtre, fichiers, presse-papiers, navigateur, calendrier, git). | Nouveaux types de contexte réellement utilisés par le planificateur. |
| P3 | Mémoire disponible pour le planificateur (préférences, projets), lecture seule, jamais de secrets. | Besoin observé dans les retours. |
| P3 | Routeur de modèles (complexité, latence, vie privée, coût) ; Apple Foundation Models en local. | Mesures de latence et de coût du planificateur actuel. |
| P3 | App Intents et Raccourcis pour lancer une mission. | Missions fiables. |
| P4 | Skills (objectif, instructions, outils, contraintes, permissions, vérification). | Outils stabilisés. |
| P4 | Missions longues et planifiées (événements, état persistant, pas de boucle). | Historique persistant des exécutions. |
| P4 | Objective engine (« accomplis cet objectif »). | Skills et missions longues. |
| P4 | Analytics minimaux, documentés, désactivables, sans contenu privé. | Retours qualitatifs insuffisants. |
| P4 | Nettoyage des pollers hérités de Coucou (Resend, n8n, Vercel, Stripe, Cal.com, Notion). | Décision produit. |
