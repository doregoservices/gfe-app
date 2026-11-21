"""Jeu d'essai FKS (repris de GESTION/SAISIE_stock_v4_TEST) saisi par le client FKS, dans l'ordre chronologique.
Usage : SB_TOKEN=... python3 seed_stock_fks.py   (purge d'abord les saisies FKS, puis rejoue tout)
Attendu : 26 lignes, 20 valides, 6 erreurs volontaires (production site non usine, vente sans commercial,
achat produit fini, 2 transferts refusés, article manquant)."""
import sys, json, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '.gfe_tools'))
sys.path.insert(0, '/home/user/.gfe_tools')
from seed_common import *
ids = json.load(open('/home/user/.gfe_tools/ids.json')); ref = json.load(open('/home/user/.gfe_tools/ref.json'))
F = ref["FKS"]; S = F["sites"]; A = F["arts"]; e = ids["FKS"]
print(admin_sql(f"""
delete from gfe.saisies_production_matieres where production_id in (select id from gfe.saisies_production where entreprise_id='{e}');
delete from gfe.saisies_production where entreprise_id='{e}';
delete from gfe.saisies_vente where entreprise_id='{e}';
delete from gfe.saisies_achat where entreprise_id='{e}';
delete from gfe.saisies_autres where entreprise_id='{e}';
delete from gfe.mouvements_stock where entreprise_id='{e}';"""))
CF, _ = login("nabildorego+fks@gmail.com")
COM = {c["nom"]: c["id"] for c in select(CF, "commerciaux", "select=id,nom")}
out = []
def rec(typ, lab, r, err=False): out.append((typ, lab, r["valide"], r["controle"], err))
def D(d): return f"2026-11-{d:02d}"
def rp(name, args): return rpc(CF, name, args)
def achat(d, site, art, q, p, piece, lab, err=False):
    rec("ACHAT", lab, rp("saisir_achat", {"p_entreprise": e, "p_date": D(d), "p_site": S[site], "p_article": A[art] if art else None, "p_quantite": q, "p_prix": p, "p_lot": None, "p_peremption": None, "p_piece": piece, "p_saisi_par": None}), err)
def autre(d, site, typ, art, q, dest=None, motif=None, rem=None, lab="", err=False):
    rec("AUTRES", lab, rp("saisir_autres", {"p_entreprise": e, "p_date": D(d), "p_site": S[site], "p_type": typ, "p_article": A[art] if art else None, "p_quantite": q,
        "p_destination": S[dest] if dest else None, "p_lot": None, "p_peremption": None, "p_motif": motif, "p_remarque": rem, "p_saisi_par": None}), err)
def prod(d, site, pf, q, mats, lab, err=False):
    rec("PRODUCTION", lab, rp("saisir_production", {"p_entreprise": e, "p_date": D(d), "p_site": S[site], "p_produit": A[pf], "p_quantite": q, "p_lot": None, "p_peremption": None, "p_remarque": None, "p_saisi_par": None,
        "p_matieres": [{"article": A[m[0]], "lot": m[1], "quantite": m[2]} for m in mats]}), err)
def vente(d, pv, com, art, q, prix, piece, lab, err=False):
    rec("VENTE", lab, rp("saisir_vente", {"p_entreprise": e, "p_date": D(d), "p_point": S[pv], "p_commercial": COM.get(com) if com else None, "p_article": A[art], "p_quantite": q, "p_prix": prix, "p_piece": piece, "p_saisi_par": None}), err)

# ---- 01/11 : stock initial, achats, transfert simulé par sortie/entrée, fabrications, ventes
for lab, site, art, q in [("Stock initial café vert", "Usine FKS", "Café vert", 100), ("Stock initial café 250 g", "PV Abidjan", "Café moulu 250 g", 200), ("Stock initial café 1 kg", "PV Grand-Bassam", "Café moulu 1 kg", 20)]:
    autre(1, site, "Stock initial", art, q, motif="Reprise du stock de départ", lab=lab)
achat(1, "Usine FKS", "Café vert", 500, 2000, "BL-101", "achat 500 kg café vert")
achat(1, "Usine FKS", "Sachet aluminium", 2000, 25, "BL-101", "achat 2000 sachets")
achat(1, "Dépôt central", "Eau minérale 1,5 L", 240, 300, "FAC-F-55", "achat 240 eau au dépôt")
autre(1, "Dépôt central", "Sortie (autre)", "Eau minérale 1,5 L", 150, motif="Autre", rem="Réassort du PV Abidjan", lab="sortie 150 eau du dépôt")
autre(1, "PV Abidjan", "Entrée (autre)", "Eau minérale 1,5 L", 150, motif="Autre", rem="Réassort reçu du dépôt", lab="entrée 150 eau au PV Abidjan")
prod(1, "Usine FKS", "Café moulu 250 g", 400, [("Café vert", "CV-A", 150), ("Sachet aluminium", None, 400)], "fabrication 400 café 250 g (lot CV-A 150 kg)")
vente(1, "PV Abidjan", "Kouamé Serge", "Café moulu 250 g", 150, 1500, "FAC-001", "vente 150 café 250 g")
vente(1, "PV Grand-Bassam", "Aya Mireille", "Café moulu 1 kg", 20, None, "FAC-002", "vente 20 café 1 kg (prix de l'article)")
# ---- 02/11
achat(2, "Usine FKS", "Café vert", 200, 2100, "BL-102", "achat 200 kg café vert")
achat(2, "Usine FKS", "Carton 12 unités", 100, 150, "BL-102", "achat 100 cartons")
achat(2, "Usine FKS", "Café moulu 250 g", 10, 1000, "BL-103", "ERREUR : article non achetable (produit fini)", True)
prod(2, "Usine FKS", "Café moulu 1 kg", 50, [("Café vert", "CV-A", None), ("Sachet aluminium", None, 50)], "fabrication 50 café 1 kg (lot CV-A déjà décompté, quantité vide)")
prod(2, "Usine FKS", "Café moulu 250 g", 300, [("Café vert", "CV-B", 75), ("Sachet aluminium", None, 300)], "fabrication 300 café 250 g (lot CV-B 75 kg)")
prod(2, "PV Abidjan", "Café moulu 250 g", 10, [], "ERREUR : production sur site non usine", True)
vente(2, "PV Abidjan", "Kouamé Serge", "Eau minérale 1,5 L", 100, None, "FAC-003", "vente 100 eau")
vente(2, "Dépôt central", None, "Eau minérale 1,5 L", 50, None, "FAC-004", "ERREUR : commercial manquant", True)
autre(2, "Usine FKS", "Casse ou perte", "Sachet aluminium", 10, motif="Casse", lab="casse 10 sachets")
autre(2, "PV Abidjan", "Inventaire (comptage)", "Café moulu 250 g", 45, motif="Inventaire physique", rem="Comptage du 02/11", lab="inventaire café 250 g : 45 comptés")
autre(2, "Dépôt central", "Inventaire (comptage)", "Eau minérale 1,5 L", 85, motif="Inventaire physique", lab="inventaire eau : 85 comptés")
autre(2, "PV Grand-Bassam", "Entrée (autre)", "Savon", 30, motif="Autre", rem="Don reçu", lab="don reçu : 30 savons")
autre(2, "Usine FKS", "Transfert", "Café moulu 250 g", 30, dest="PV Abidjan", lab="ERREUR : transfert désactivé", err=True)
autre(2, "Usine FKS", "Transfert", "Savon", 5, dest="PV Abidjan", lab="ERREUR : transfert désactivé (2)", err=True)
autre(2, "Usine FKS", "Sortie (autre)", None, 5, lab="ERREUR : article manquant", err=True)
valides = [o for o in out if o[2]]; erreurs = [o for o in out if not o[2]]
print(f"FKS : {len(out)} lignes, {len(valides)} valides, {len(erreurs)} en erreur")
for o in out:
    if o[4] != (not o[2]): print("  ECART", o[0], o[1], "->", o[3])
for o in erreurs: print(f"  {o[0]:10} ERR {o[1]} -> {o[3]}")
json.dump(out, open('/home/user/.gfe_tools/saisies_fks.json', 'w'), ensure_ascii=False)
