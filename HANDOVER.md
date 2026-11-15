# Passation : application GFE (stock, comptabilité, paie, RH)

Document de passation pour la nouvelle session dédiée à l'application web.
Il résume ce qui a été décidé, ce qui existe déjà, et ce qu'il reste à faire.
**Ne contient aucun secret** : pas de jeton, pas de mot de passe, pas de données personnelles de salariés.

---

## 1. Contexte

- **GFE** (Global First Engineering) : cabinet qui tient la comptabilité de plusieurs entreprises clientes.
- Le client veut **une application web** regroupant :
  1. Gestion de stock (aujourd'hui en Google Sheets) ;
  2. Comptabilité GFE (saisie, verrouillage, points hebdomadaire et mensuel, audit) ;
  3. Paie et RH (bulletins, recrutement, contrats, congés, démission, licenciement, calcul des droits).
- Trois volets activables **par client**. Chaque entreprise ne voit que ses volets.
- **Hébergement** : serveur déjà disponible. Un domaine va être acheté et loué à GFE, au nom d'une autre structure.
- **Règle absolue** : ne rien modifier ni supprimer dans les fichiers Google Drive existants sans accord explicite. Le nouveau projet est séparé.
- Lieu : Grand-Bassam, Côte d'Ivoire. Fuseau : Africa/Abidjan. Monnaie : F CFA.

---

## 2. Décisions validées

| Sujet | Décision |
|---|---|
| Architecture | Application web, séparée de Drive. Google Sheets reste en place pour l'existant. |
| Volets | Stock, Comptabilité GFE, Paie & RH. Activation par client. |
| Multi-entreprises | Une base séparée par entreprise (ou isolation stricte par identifiant d'entreprise). |
| Rôles | Cabinet (admin), comptable, saisie, dirigeant. |
| Verrouillage des saisies (GFE) | Bouton Valider, puis verrouillage après 15 minutes. Déverrouillage uniquement par le comptable. |
| Période ouverte (GFE) | Choisie par le comptable (saisie du et saisie au). Pas de délai fixe de 24 h. |
| Corrections (GFE) | Par contre-passation, jamais par modification directe. |
| Journal d'audit | Chaque modification est écrite dans un journal (AUDIT). |
| Stock : mode de consommation | Par matière : mode LOT ou mode QUANTITÉ, au choix. |
| Stock : code entreprise | Saisi une seule fois dans GESTION PARAM B16. |
| Stock : méthode de coût | Paramètre global : CMP (coût moyen pondéré) ou dernier prix. |

Points **non tranchés** (à confirmer avec le client) :
- Solde de lot en mode LOT : non tranché.
- « Type de mouvement » désactivé = entrée/sortie seulement (hypothèse).
- Le fichier de saisie GFE appartient au comptable (hypothèse).
- Choix de catégorie A/B/C dans GFE : non tranché, ne pas modifier sans accord.

---

## 3. Volet Stock (existant, à reprendre)

Fonctionnalités déjà conçues et testées (version v4, jeu d'essai) :
- Listes déroulantes partout, désignation des articles (le code se calcule seul).
- Colonnes optionnelles réglées dans PARAM (OUI/NON) : N° de lot, péremption, site de destination, saisi par, type de mouvement, méthode de coût.
- Suivi des commerciaux : ventes du jour, de la semaine, du mois, par commercial et par point de vente.
- Liaison SAISIE → GESTION (IMPORTRANGE dans Google Sheets).
- Tableau de bord (ACCUEIL) : stock restant, point de vente du mois, alertes rouge (sous seuil ou rupture).
- Onglet POINTS : Jour, Semaine, Mois ou Libre (dates de début et de fin), filtres commercial et point de vente, détail des ventes et des productions.
- Type « Stock initial » séparé des entrées.
- Production = usines uniquement. Matières consommées par fabrication : jusqu'à 8 (PARAM B22).
- Analyse de production : deux colonnes libres nommées dans PARAM B25 et B26.

Fichiers de référence (dans le workspace d'origine) :
- `stock-universel/build_stock.py` : génère GESTION et SAISIE (modes vierge, test, verify).
- `stock-universel/test_data.py` : jeu d'essai (usine de café FKS).
- `stock-universel/Code_stock.gs` : code Apps Script à coller dans les deux fichiers.
- `stock-universel/MODE_EMPLOI_stock_v4.md` : mode d'emploi.

Résultats du jeu d'essai (vérifiés) :
- Valeur totale du stock : 1 764 053,57 F.
- Ventes du mois : 360 000 F (point de vente Abidjan 260 000 ; Grand-Bassam 100 000).
- Aucune erreur hors zone de détail.

Limites connues :
- Les formules de détail (FILTER) demandent Google Sheets ou Excel 365.
- Le détail est limité à 400 lignes.
- La liaison réelle SAISIE → GESTION n'a pas été testée dans Google Sheets (seulement dans un classeur de contrôle).

---

## 4. Volet Comptabilité GFE (existant, à reprendre)

Fichiers de référence (dossier `gfe-compta/`) :
- SAISIE : `GFE_SAISIE_operations_modele.xlsx` + `Code_saisie_GFE.gs` (saisie par la personne qui saisit).
- COMPTABLE : `GFE_Comptabilite_TEE_RME_modele_v4.xlsx` + `Code_audit_GFE.gs` (cabinet).
- Onglets POINTS (B4 = date de référence, B5:C6 = périodes) et POINTS_ARCHIVE.
- Déclencheurs : lundi 7 h (hebdomadaire) et 1er du mois 7 h (mensuel).

Indicateurs : soldes caisse et banque, opérations retenues/bloquées/en erreur, ventes et achats, dépenses classes 60 à 67, paie, compte du dirigeant, contrôles. **Les stocks sont hors périmètre** (fichier stock séparé).

Limites signalées au client :
- Apps Script ne bloque pas en temps réel : le retour en arrière intervient après la modification.
- Un collage sur plusieurs cellules ne peut pas être restauré par ce mécanisme.
- Le propriétaire du fichier garde tous ses droits.

Régimes fiscaux (à vérifier auprès de la DGI) :
- TEE : CA TTC de 5 000 001 à 50 000 000 F.
- RME (art. 71 bis CGI) : CA de 50 000 001 à 200 000 000 F.
- Pas de TVA dans ces régimes.

Comptes d'associés SYSCOHADA : 461 → 4611 à 4619 ; 462 → 4621, 4626 ; 4631.

---

## 5. Volet Paie (existant, à reprendre)

Générateurs :
- `jcharno-paie/build_bulletins.py` : bulletins J-CHARNO.INC et Priscille.
- `bulletins/fks/build_fks_octobre.py` : bulletins FKS Industrie, octobre 2026, avec résumé des charges patronales (page 9).
- `bulletins/build_bulletin.py` (docx) et `bulletins/build_pdf_v3.py` (PDF, style Priscille) : bulletin Bamba Saly Asseytou.

Règles de calcul utilisées (à faire valider par un expert avant toute mise en production) :
- ITS, barème 2026 par tranches : 0 % jusqu'à 75 000 ; 16 % ; 21 % ; 24 % ; 28 % ; 32 % au-delà de 8 000 000. Le bulletin FKS applique la tranche 16 %.
- RICF (art. 119 bis et 120 CGI, ordonnance 2023-719) : célibataire 1 part ; marié 2 parts ; +0,5 part par enfant ; plafond 5 parts ; 5 500 F par demi-part au-delà de la première.
- CNPS salarié : 6,3 %, plafond retraite 3 375 000 F.
- CNPS patronale : retraite 7,7 %, prestations familiales 5 %, maternité 0,75 %, accidents du travail 3 %.
- CMU : 500 F salarié et 500 F employeur.
- ITS employeur : 1,2 % du salaire brut.
- FDFP : TA 0,4 % + TFPC 1,2 % (soit 1,6 %).
- Indemnité de transport : Abidjan 30 000 F, exonérée d'ITS (arrêté 2020, à confirmer pour 2026). Elle s'ajoute après les retenues.
- Net à payer = brut − retenues + transport.
- SMIG : 75 000 F brut par mois (décret 2022-986 / arrêté 0009/MEPS/CAB du 10/06/2023).

Présentation des bulletins : une page, bandeau de couleur, sections numérotées (gains, retenues, rubriques non imposables, net à payer), encadré « pour information » des charges patronales, deux zones de signature. Logo FKS Industrie blanc disponible dans `bulletins/fks/logo_fks_blanc.png`.

Règle reçue : **ne pas inclure de rubrique RIB** sur les bulletins.

---

## 6. Volet RH (à construire)

Demandé par le client : recrutement, contrats, congés, démission, licenciement, calcul de tous les droits.

Points de droit déjà relevés (à faire valider) :
- Préavis : 8 jours ouvriers jusqu'à 6 mois de service, doublé au-delà.
- Indemnité de licenciement : 30 % (5 premières années), 35 % (6e à 10e), 40 % (au-delà). Base : salaire moyen des 12 derniers mois. Référence : CCI 1977 art. 39 ; Code du travail art. 16.12.
- Congés : 2 à 2,2 jours par mois de service effectif.
- Gratification de fin d'année : au moins 3/4 du salaire minimum de la catégorie, au prorata (CCI 1977 art. 44). Due au démissionnaire comme au licencié.
- Prime d'ancienneté : CCI 1977 art. 55 (non utilisée pour l'instant).
- Service effectif ≥ 1 an pour l'indemnité.
- Revalorisation sectorielle : arrêté 0050/MEPS/CAB du 18/07/2023 (+9 % à +18 %, sans montants par catégorie).

Ne pas utiliser : sources au contenu incomplet ou non applicables (droit français comme référence seulement).

---

## 7. Sécurité et données

- **Aucun jeton, mot de passe ou clé dans le dépôt.** Utiliser des variables d'environnement ou un gestionnaire de secrets. Si un jeton a été partagé dans une conversation, le révoquer et en créer un nouveau.
- **Données personnelles** (salaires, identités, numéros CNPS) : ne pas les mettre dans le dépôt GitHub. Utiliser des données fictives pour les tests.
- Dépôt à créer en **privé**.
- Journal d'audit obligatoire sur les volets comptables et paie.
- Vérifier les obligations de la loi ivoirienne sur la protection des données personnelles (ARTCI) avant d'héberger les données de clients.

---

## 8. Erreurs à ne pas refaire

- IMPORTRANGE ne fonctionne pas dans Excel : la liaison est prévue pour Google Sheets.
- Ne pas utiliser `node --check` directement sur un fichier `.gs` : passer par une copie `.js`.
- Patch de script : vérifier les ancres avant d'écrire. Une suppression par plage a déjà effacé une fonction.
- Recalcul LibreOffice : créer `/tmp/lo_mode` avant la conversion, sinon elle échoue. Installation : `sudo apt-get install libreoffice-calc-nogui`.
- Bibliothèques Python (reportlab, pymupdf, openpyxl) : réinstaller à chaque nouvelle session avec `python3 -m pip install`.
- Un second import du même fichier dans Sage crée des doublons.
- Google Drive (connecteur) : une même écriture ne peut pas être répétée dans le même échange. Les téléversements se font par session résumable, avec les en-têtes `X-Goog-Upload-Command: upload, finalize`.
- Un fichier xlsx téléversé n'est pas une feuille Google Sheets : il faut la convertir à la main pour que IMPORTRANGE fonctionne.

---

## 9. État des fichiers Drive (à ne pas toucher sans accord)

Dossier COMPTABLE 1 : `1HwnGKmo912j1ZowKeRW47yNaUR3gCk4R`

Stock v4 :
- SAISIE TEST (Google Sheets, convertie par le client) : `18Ofl1zAsrtufJ8AxllvxH05N5Bpvf4HVXWDmvVDgxqc`.
- GESTION TEST : xlsx `1Z2CyK9oIM1lF1DkWkbVdz9xeNRLLYxIi`, à convertir en Google Sheets. La liaison doit être autorisée une fois.
- Versions vierges et versions xlsx : dans `stock-universel/A_UTILISER/` (locales).

Corbeille : anciennes copies v2, v3 et du 05 au 12/11 (récupérables).

À ne pas supprimer : les fichiers historiques de l'entreprise (« Suivi-STOCK », « STOCK CAFE », etc.), les dossiers GFE et COMPTA.

Dossier « ANCIEN DOCS » : trois fichiers ne peuvent pas être supprimés depuis le compte actuel (propriétaire différent).

---

## 10. Questions ouvertes pour le client

1. Étape intermédiaire sur Google Sheets, ou application web directement ?
2. Quel volet sort en premier ?
3. Qui valide les règles RH et paie (juriste, expert-comptable) ?
4. Premier client pilote, budget et délai ?
5. Modèle de facturation : abonnement par volet, par entreprise, ou par utilisateur ?
6. Migration des données existantes (Sheets) : faut-il une reprise automatique ?

---

## 11. Localisation des sources à intégrer

- `stock-universel/`, `gfe-compta/`, `bulletins/`, `jcharno-paie/`, `dgi-github/` : sources locales de l'entreprise.
- Dossier « réseau compta Connect » : **introuvable** sur le disque et sur Drive lors de la rédaction. À fournir par le client.
- FKS Industrie : sources dans `bulletins/fks/` et `dgi-github/` (annexes ITS, bulletins de référence).

---

## 12. Dépôts GitHub existants (compte doregoservices)

Voir `MESSAGE_NOUVELLE_SESSION.md`, section 6, pour le tableau complet.

- **compta-connect** (public) : « réseau compta Connect ». Plateforme de cotisations, membres, formations, offres, espace membre. Base la plus proche de l'application visée.
- **reference-comptabilite-ivoirienne** (privé) : référence paie, ITS, RICF, FDFP, TVA, EDI, SYSCOHADA. Source de vérité pour les calculs.
- **dgi-modeles**, **outil-journaux-sage**, **fks-industrie**, **fks-industrie-propre** (ne pas modifier).
- **dossier-twal** : dossier personnel d'une autre candidature. Hors projet.
