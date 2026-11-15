# Message de passation — application GFE

Bonjour, tu reprends le projet **application GFE** pour le compte de l'utilisateur (Grand-Bassam, Côte d'Ivoire, fuseau Africa/Abidjan, monnaie F CFA).

## 1. Par où commencer

1. Dépôt de travail : **https://github.com/doregoservices/gfe-app** (privé, branche `main`).
2. Lis **HANDOVER.md** à la racine : contexte, décisions, états des volets, règles de calcul, erreurs à ne pas refaire.
3. Les jetons GitHub ne sont **jamais** dans le dépôt ni dans le chat. Demande-les à l'utilisateur à l'instant où tu en as besoin, en variable d'environnement.

## 2. Ce qu'on construit

Une application web **unique**, au nom de GFE, sur un domaine loué à GFE par une autre structure (le serveur existe déjà ; il est probablement chez Hetzner, à confirmer).

Trois volets activables **par client** :
1. **Stock** (existant en Google Sheets / Apps Script, à reprendre).
2. **Comptabilité GFE** (existant en Google Sheets / Apps Script, à reprendre).
3. **Paie et RH** (bulletins existants ; RH à construire : recrutement, contrats, congés, démission, licenciement, calcul des droits).

Chaque entreprise cliente ne voit que ses volets. Le cabinet GFE a un rôle d'administration.

## 3. Règles impératives

- **Ne rien modifier ni supprimer dans les fichiers Google Drive existants** sans accord explicite. Le nouveau projet est séparé.
- **Aucune donnée personnelle réelle** dans le dépôt : pas de noms de salariés, de salaires réels, de NCC réels, de numéros CNPS. Utiliser des données fictives (par exemple NCC `1900000X`).
- Le dépôt reste **privé**.
- Chaque modification comptable ou de paie est tracée dans un journal d'audit.
- Les calculs de paie et de droits RH doivent être **recalculés**, jamais recopiés. Si une donnée manque, laisser la cellule vide et le signaler.
- Avant toute mise en production sur la paie ou le droit du travail, la validation d'un expert-comptable ou d'un juriste est nécessaire.

## 4. Points validés

- Verrouillage GFE : bouton Valider, puis verrouillage après 15 minutes. Déverrouillage uniquement par le comptable. Corrections par contre-passation.
- Période ouverte choisie par le comptable (pas de délai fixe de 24 h).
- Stock : mode LOT ou QUANTITÉ par matière ; méthode de coût globale (CMP ou dernier prix) ; code entreprise saisi une fois.
- Paie : bulletin sur une page, sans rubrique RIB. Transport après les retenues, exonéré d'ITS dans la limite de 30 000 F (Abidjan).

## 5. Points non tranchés (à demander à l'utilisateur)

- Solde de lot en mode LOT.
- Étape intermédiaire sur Google Sheets, ou application web directement.
- Volet à sortir en premier.
- Qui valide les règles RH et paie.
- Premier client pilote, budget, délai.
- Modèle de facturation (par volet, par entreprise ou par utilisateur).
- Reprise automatique des données Sheets existantes.

## 6. Dépôts GitHub à consulter (compte doregoservices)

| Dépôt | Visibilité | Rôle | Pour ce projet |
|---|---|---|---|
| `gfe-app` | privé | Passation et futur code de l'application GFE | **Ici** |
| `compta-connect` | public | « Réseau compta Connect » : plateforme pour un réseau de comptables. Cotisations avec pointage automatique, membres, formations, offres d'emploi, espace membre. Flask + Supabase, paiement mobile money, relais et déploiement Hetzner | **À étudier en priorité** : c'est la base la plus proche d'une application multi-membres. Lire `README.md`, `DEPLOIEMENT.md`, `relais/GUIDE_HETZNER_BASILE.md`, `identite/IDENTITE.md` |
| `reference-comptabilite-ivoirienne` | privé | Référence paie, ITS (réforme 2024), RICF, FDFP, TVA, EDI e-Impôts, SYSCOHADA | **Source de vérité** pour les calculs : lire `01-paie-ivoirienne.md` |
| `dgi-modeles` | privé | Modèles DGI (ITS, TVA) — analyse interne | À consulter pour les formats officiels |
| `outil-journaux-sage` | public | Journaux SYSCOHADA pour Sage 100 | Utile pour l'export vers Sage |
| `fks-industrie` (aussi chez `gfeinfos-hue`) | public | Gestion d'usine de café en PWA : achats, torréfaction, ventes, caisse, paie CI, exports | Référence fonctionnelle |
| `fks-industrie-propre` | privé | Copie figée de FKS (v35.51, 11/09/2026) | **Ne pas modifier** |
| `dorego-backend`, `dorego-frontend` | privé | Backend et frontend Dorego (README absent) | À examiner si on réutilise l'infrastructure |
| `dorego-services-group`, `boostify-*`, `cafepro-evolution`, `miss-kouyate-shop`, `inscription`, `cabinet-gfe.github.io` | divers | Sites et outils annexes (formations GFE, inscriptions, laboratoire) | Hors périmètre sauf demande |
| `dossier-twal` | privé | **Dossier personnel de candidature** (poste de comptable, autre entreprise) | **Hors projet. Ne pas mélanger.** |

## 7. Drive

- Dossier de travail stock : COMPTABLE 1 (`1HwnGKmo912j1ZowKeRW47yNaUR3gCk4R`).
- SAISIE TEST (Google Sheets) : `18Ofl1zAsrtufJ8AxllvxH05N5Bpvf4HVXWDmvVDgxqc`.
- GESTION TEST : version xlsx `1Z2CyK9oIM1lF1DkWkbVdz9xeNRLLYxIi`, à convertir en Google Sheets par l'utilisateur. La liaison doit être autorisée une fois.
- Les fichiers historiques de l'entreprise (« Suivi-STOCK », « STOCK CAFE », etc.) ne doivent pas être touchés.

## 8. Premières actions proposées

1. Lire `HANDOVER.md`, puis `compta-connect/README.md` et `reference-comptabilite-ivoirienne/01-paie-ivoirienne.md`.
2. Demander à l'utilisateur de répondre aux points non tranchés (section 5).
3. Proposer une architecture et un découpage en étapes, avant d'écrire du code.
