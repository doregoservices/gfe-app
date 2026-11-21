"""Jeu de démonstration pour KOUYATE shop et ROTSEN, saisi par leurs clients (RPC, comme SAISIE).
Remet à zéro leurs saisies, puis saisit : stock initial, achats, fabrication, ventes, casse, inventaire.
Une ligne refusée est volontairement absente : tout doit passer les contrôles.
Lancer : SB_TOKEN=... GFE_TEST_PWD=... python3 tests/seed_demo_kouyate_rotsen.py
"""
import json, os, sys
sys.path.insert(0, "/home/user/.gfe_tools")
from seed_common import login, rpc, admin_sql  # noqa: E402  (outils de la session)

ids = json.load(open("/home/user/.gfe_tools/ids.json"))
ENTS = {
    "KOUYATE shop": ("nabildorego+kouyate@gmail.com", ids["KOUYATE shop"]),
    "ROTSEN": ("nabildorego+rotsen@gmail.com", ids["ROTSEN"]),
}
# Remise à zéro des saisies de ces deux entreprises (mouvements compris)
for nom, (_, eid) in ENTS.items():
    admin_sql(f"delete from gfe.mouvements_stock where entreprise_id='{eid}';"
              f"delete from gfe.saisies_production where entreprise_id='{eid}';"
              f"delete from gfe.saisies_vente where entreprise_id='{eid}';"
              f"delete from gfe.saisies_achat where entreprise_id='{eid}';"
              f"delete from gfe.saisies_autres where entreprise_id='{eid}';")

def ref(tok, eid):
    """Identifiants des sites, articles et commerciaux, lus avec le compte client."""
    from seed_common import select
    sites = {s["nom"]: s["id"] for s in select(tok, "sites", f"entreprise_id=eq.{eid}&select=id,nom")}
    arts = {a["designation"]: a["id"] for a in select(tok, "v_articles_saisie", f"entreprise_id=eq.{eid}&select=id,designation")}
    coms = {c["nom"]: c["id"] for c in select(tok, "commerciaux", f"entreprise_id=eq.{eid}&select=id,nom")}
    return sites, arts, coms

def go(nom, r):
    ok = bool(r.get("valide")) if isinstance(r, dict) else True
    print(("OK    " if ok else "ERREUR ") + nom + ("" if ok else " -> " + str(r)))
    return ok

tout_ok = True
# ---- KOUYATE shop (mixte, CMP) ----
tok, _ = login(ENTS["KOUYATE shop"][0]); eid = ENTS["KOUYATE shop"][1]
S, A, C = ref(tok, eid)
tout_ok &= go("KOUYATE stock initial savon 10 au Boutique Abidjan", rpc(tok, "saisir_autres", {
    "p_entreprise": eid, "p_date": "2026-11-01", "p_site": S["Boutique Abidjan"], "p_type": "Stock initial",
    "p_article": A["Savon artisanal"], "p_quantite": 10, "p_destination": None, "p_lot": None, "p_peremption": None,
    "p_motif": "Reprise du stock de départ", "p_remarque": None, "p_saisi_par": None}))
tout_ok &= go("KOUYATE achat huile de palme 40 kg", rpc(tok, "saisir_achat", {
    "p_entreprise": eid, "p_date": "2026-11-01", "p_site": S["Atelier Bingerville"], "p_article": A["Huile de palme"],
    "p_quantite": 40, "p_prix": 900, "p_lot": None, "p_peremption": None, "p_piece": "BL-K1", "p_saisi_par": None}))
tout_ok &= go("KOUYATE achat bidons 5 L x50", rpc(tok, "saisir_achat", {
    "p_entreprise": eid, "p_date": "2026-11-01", "p_site": S["Atelier Bingerville"], "p_article": A["Bidon 5 L"],
    "p_quantite": 50, "p_prix": 300, "p_lot": None, "p_peremption": None, "p_piece": "BL-K1", "p_saisi_par": None}))
tout_ok &= go("KOUYATE fabrication 40 savon", rpc(tok, "saisir_production", {
    "p_entreprise": eid, "p_date": "2026-11-02", "p_site": S["Atelier Bingerville"], "p_produit": A["Savon artisanal"],
    "p_quantite": 40, "p_lot": None, "p_peremption": None, "p_remarque": None, "p_saisi_par": None,
    "p_matieres": [{"article": A["Huile de palme"], "lot": None, "quantite": 20},
                   {"article": A["Bidon 5 L"], "lot": None, "quantite": 40}]}))
tout_ok &= go("KOUYATE vente 8 savon au Boutique Abidjan", rpc(tok, "saisir_vente", {
    "p_entreprise": eid, "p_date": "2026-11-03", "p_point": S["Boutique Abidjan"], "p_commercial": C["Kouamé Serge"],
    "p_article": A["Savon artisanal"], "p_quantite": 8, "p_prix": None, "p_piece": "FAC-K1", "p_saisi_par": None}))
tout_ok &= go("KOUYATE casse 2 bidons", rpc(tok, "saisir_autres", {
    "p_entreprise": eid, "p_date": "2026-11-04", "p_site": S["Atelier Bingerville"], "p_type": "Casse ou perte",
    "p_article": A["Bidon 5 L"], "p_quantite": 2, "p_destination": None, "p_lot": None, "p_peremption": None,
    "p_motif": "Casse", "p_remarque": None, "p_saisi_par": None}))

# ---- ROTSEN (usine, CMP) ----
tok, _ = login(ENTS["ROTSEN"][0]); eid = ENTS["ROTSEN"][1]
S, A, C = ref(tok, eid)
tout_ok &= go("ROTSEN achat cuir brut 30", rpc(tok, "saisir_achat", {
    "p_entreprise": eid, "p_date": "2026-11-01", "p_site": S["Atelier Rotsen"], "p_article": A["Cuir brut"],
    "p_quantite": 30, "p_prix": 4000, "p_lot": None, "p_peremption": None, "p_piece": "BL-R1", "p_saisi_par": None}))
tout_ok &= go("ROTSEN achat doublure 20", rpc(tok, "saisir_achat", {
    "p_entreprise": eid, "p_date": "2026-11-01", "p_site": S["Atelier Rotsen"], "p_article": A["Doublure"],
    "p_quantite": 20, "p_prix": 1500, "p_lot": None, "p_peremption": None, "p_piece": "BL-R1", "p_saisi_par": None}))
tout_ok &= go("ROTSEN stock initial 3 sacs au Boutique Plateau", rpc(tok, "saisir_autres", {
    "p_entreprise": eid, "p_date": "2026-11-01", "p_site": S["Boutique Plateau"], "p_type": "Stock initial",
    "p_article": A["Sac en cuir"], "p_quantite": 3, "p_destination": None, "p_lot": None, "p_peremption": None,
    "p_motif": "Reprise du stock de départ", "p_remarque": None, "p_saisi_par": None}))
tout_ok &= go("ROTSEN fabrication 10 sacs", rpc(tok, "saisir_production", {
    "p_entreprise": eid, "p_date": "2026-11-02", "p_site": S["Atelier Rotsen"], "p_produit": A["Sac en cuir"],
    "p_quantite": 10, "p_lot": None, "p_peremption": None, "p_remarque": None, "p_saisi_par": None,
    "p_matieres": [{"article": A["Cuir brut"], "lot": "CUIR-L1", "quantite": 20},
                   {"article": A["Doublure"], "lot": None, "quantite": 10}]}))
tout_ok &= go("ROTSEN vente 2 sacs au Boutique Plateau", rpc(tok, "saisir_vente", {
    "p_entreprise": eid, "p_date": "2026-11-03", "p_point": S["Boutique Plateau"], "p_commercial": C["Diallo Fatou"],
    "p_article": A["Sac en cuir"], "p_quantite": 2, "p_prix": None, "p_piece": "FAC-R1", "p_saisi_par": None}))

print("\nRésultat :", "tout accepté" if tout_ok else "des lignes refusées (voir ci-dessus)")
