# GFE — Maquette statique GitHub Pages

**Démonstration uniquement. Aucune donnée réelle.** Cette version statique fonctionne sans serveur : les opérations restent dans `localStorage`, dans le navigateur de l'appareil. La sélection de rôle et d'entreprise est simulée ; il n'y a ni authentification ni sécurité multi-entreprises. Le journal d'audit local est modifiable. Ce n'est pas un outil comptable de production. Les comptes et les opérations sont simplifiés et ne couvrent pas encore la totalité des modèles ; le module stock et la paie/RH ne sont pas construits.

## Installation dans le dépôt gfe-app

Déposer `index.html`, `style.css` et `app.js` à la racine de la branche `main`. Dans GitHub : **Settings → Pages → Build and deployment → Deploy from a branch → main / (root) → Save**. L'adresse sera `https://doregoservices.github.io/gfe-app/` si GitHub Pages est activé avec ces réglages. Aucun domaine n'est nécessaire.

Ouvrir `index.html` directement dans un navigateur ou servir le dossier avec `python -m http.server 8001`. Pour remettre les données fictives à zéro : Paramètres → Réinitialiser la maquette. Un export JSON des données de démo est proposé dans Paramètres ; les données locales ne se synchronisent pas entre appareils et peuvent disparaître si le stockage navigateur est effacé.

## Suite pour la vraie application

Construire une API et une base de données sécurisées, avec authentification, autorisations contrôlées côté serveur, isolation des entreprises, journal d'audit, sauvegardes, migrations, protection des données et validation comptable / paie. GitHub Pages n'exécute ni Python ni base de données. Une future migration de serveur exige une sauvegarde vérifiée, une procédure de transfert et des tests avant toute suppression de l'ancien serveur. Cette maquette n'établit pas automatiquement un chemin de migration des données locales vers la future base.
