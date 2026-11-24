# Paie et RH : règles à valider (GFE, Côte d'Ivoire)

Ce document liste les règles utilisées pour la paie et la gestion RH, avec leur source.
Rien ici n'est encore codé comme définitif : chaque point doit être confirmé par le cabinet
(ou un expert en droit social et fiscalité ivoiriens) avant mise en production.

Aucune donnée personnelle dans ce document.

---

## 1. Paie : taux repris du modèle `GFE - COMPTABLE` (feuille PARAM, lignes 37 à 62)

| Rubrique | Valeur | Cellule | Base |
|---|---|---|---|
| CNPS retraite, part salarié | 6,3 % | B38 | Brut plafonné |
| CNPS retraite, part employeur | 7,7 % | B39 | Brut plafonné |
| Plafond CNPS retraite | 3 375 000 F/mois | B40 | |
| Prestations familiales, employeur | 5 % | B41 | Brut plafonné à 70 000 |
| Accidents du travail, employeur | 3 % | B42 | Brut plafonné à 70 000 |
| Maternité, employeur | 0,75 % | B43 | Brut plafonné à 70 000 |
| Plafond prestations familiales, AT, maternité | 70 000 F/mois | B44 | |
| CMU, montant par personne couverte | 1 000 F/mois | B45 | |
| CMU, part salarié et part employeur | 50 % chacune | B46 | |
| FDFP | 1,6 % du brut | B47 | |
| ITS employeur | 1,2 % du brut | B48 | |
| RICF : réduction par demi-part | 5 500 F/mois | B49 | |
| RICF : nombre maximal de parts | 5 | B50 | |

**Barème ITS mensuel** (sur le brut, marginal, sans abattement) :

| Tranche | De | À | Taux |
|---|---|---|---|
| 1 | 0 | 75 000 | 0 % |
| 2 | 75 000 | 240 000 | 16 % |
| 3 | 240 000 | 800 000 | 21 % |
| 4 | 800 000 | 2 400 000 | 24 % |
| 5 | 2 400 000 | 8 000 000 | 28 % |
| 6 | 8 000 000 | | 32 % |

Cellules B53 à B62. Le modèle n'applique pas de tranche entre 0 et 75 000 au-dessus de 0 % : à confirmer.

**Calcul d'une paie (modèle, PAIE_SAISIE) :**
- Brut imposable = salaire de base + autres éléments imposables.
- CNPS salarié = 6,3 % du brut plafonné à 3 375 000.
- CMU salarié = 1 000 × 50 % × nombre de personnes couvertes.
- ITS brut = barème ci-dessus sur le brut imposable.
- RICF = 5 500 × (parts − 1) × 2, parts = 1 (célibataire) ou 2 (marié), +0,5 par enfant, plafonnées à 5.
- ITS salarié net = ITS brut − RICF (non négatif).
- Net à payer = brut + transport retenu + autres non imposables − CNPS salarié − CMU salarié − ITS salarié net.
- Coût employeur = brut + transport + CNPS patronale + prestations familiales/AT/maternité + CMU employeur + ITS employeur + FDFP.

**Écritures (MOTEUR_PAIE) :** 9 lignes par bulletin. Comptes : 66100000 salaires, 66340000, 66410000, 64130000, 64140000 (charges), 42200000 personnel, 43100000 CNPS à payer, 44700000 ITS à payer.

## 2. Paie : à confirmer

1. **Transport** : hors brut, exonéré d'ITS, ajouté après les retenues. Abidjan 30 000 F (arrêté 2020, à confirmer pour 2026).
2. **CMU** : 1 000 F par personne et par mois, réparti moitié salarié, moitié employeur. Vérifier le montant et la répartition actuels.
3. **Abattement ITS** : le modèle n'en applique pas. Vérifier s'il existe pour les salaires concernés.
4. **Tranche 0 %** : confirmer le seuil de 75 000 F (le SMIG est de 75 000 F).
5. **SMIG** : 75 000 F brut par mois (décret 2022-986, confirmé par les sources de 2026). Vérifier que chaque salaire est au moins égal.

## 3. RH : règles de droit du travail (Code du travail, loi 2015-532)

| Sujet | Règle reprise | Source | Statut |
|---|---|---|---|
| Congé payé | 2,2 jours ouvrables par mois de service effectif | Art. 25.1 | Confirmé par le texte |
| Majoration congé | +1 jour après 5 ans, +2 jours après 10 ans | Art. 25.2 | Confirmé (sources secondaires) |
| Congé non pris en fin de contrat | Indemnité compensatrice | Art. 25.8 | Confirmé |
| Préavis | **Appliqué** : décret n° 2026-198 du 15 avril 2026 (texte du décret, reproduit sur loidici.biz). Il remplace le décret 96-200. La passation (8 jours jusqu'à 6 mois, doublé au-delà) était incomplète ; le décret prévoit aussi 15 jours, 1 à 4 mois selon le mode de paie et la catégorie. | Décret 2026-198 (art. 1 à 4) | Appliqué dans `gfe.rh_bareme_preavis` (migration 0020), dix cas testés |
| Indemnité de licenciement | 30 % du salaire moyen par année (5 premières années), 35 % (6e à 10e), 40 % au-delà | **Décret 2017-210, art. 4** (texte vérifié) | Taux et seuils confirmés ; calcul non encore codé |
| Base de l'indemnité | Salaire moyen des 12 derniers mois (salaire global) | Art. 18.16 / décret | À confirmer : inclut-il les primes ? |
| Ancienneté minimale | Un an de service continu | Passation / décret | À confirmer |
| Licenciement abusif | Dommages-intérêts : 1 mois de salaire brut par année d'ancienneté, minimum 3 mois, maximum 20 mois. Le juge constate l'abus. | **Art. 18.15, b)** de la loi 2015-532 (texte vérifié sur plusieurs reproductions de la loi) | **Appliqué** (migration 0021, fonction `gfe.dommages_licenciement_abusif`). Point à confirmer : ancienneté en années complètes (choix retenu). |
| Gratification de fin d'année | Au moins 3/4 du minimum conventionnel mensuel de la catégorie, au prorata du temps de service (embauche, démission, licenciement compris) | **CCI 1977, art. 53** (texte vérifié) | **Appliqué** (migration 0021, `gfe.gratification_minimum`). Minimum de la 1re catégorie = 75 000 F (SMIG). Les minima des autres catégories doivent être saisis depuis la grille officielle : aucune grille à jour n'a été trouvée en ligne. |
| Heures et durée | 40 h par semaine hors agriculture | Art. 21.2 | Confirmé |
| Deux jours de liberté pendant le préavis | 2 jours payés par semaine de préavis | Art. 18.6 | Confirmé |

## 4. Questions à trancher avec le cabinet

1. ~~Préavis~~ : **réglé** par le décret 2026-198 (appliqué).
2. ~~Licenciement abusif~~ : **réglé** par l'art. 18.15 (appliqué). ~~Gratification~~ : **réglée** par l'art. 53 CCI 1977 (appliquée) ; grille des minima à saisir.
2. **Indemnité de licenciement** : les seuils 5 / 10 ans sont-ils corrects ? Les primes entrent-elles dans la base ?
3. **Gratification** : la convention collective s'applique-t-elle ? Sinon, quelle règle retenir ?
4. **Transport** : montant 2026 et régime de l'exonération.
5. **CMU** : montant et répartition actuels.
6. **Licenciement abusif** : confirmer l'échelle de dommages-intérêts.

## 5. Sources consultées (23/11/2026)

- Loi n° 2015-532 du 20 juillet 2015 portant Code du travail (texte intégral, natlex.ilo.org et economie-ivoirienne.ci).
- Guides juridiques (socium.link, juriste-ci.com, blog.uptimise.io) : résumés secondaires, à vérifier contre le texte officiel.
- SMIG : décret 2022-986 (75 000 F brut), repris par des sites d'information de 2026.
- Passation GFE (HANDOVER.md, section 5 et 6) et modèle `GFE - COMPTABLE - MODELE VIERGE` (PARAM, PAIE_SAISIE, EMPLOYES, MOTEUR_PAIE).
