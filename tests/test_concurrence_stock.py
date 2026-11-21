"""Concurrence sur le stock : 6 ventes d'une unité lancées en parallèle sur un stock de 2.
Attendu : exactement 2 ventes acceptées, 4 refusées (stock négatif), stock final 0, jamais négatif.
Le verrou (pg_advisory_xact_lock dans gfe.saisir_vente) doit sérialiser les écritures.
Remet ensuite KOUYATE à son jeu de démonstration (tests/seed_demo_kouyate_rotsen.py).
Lancer : SB_TOKEN=... GFE_TEST_PWD=... python3 tests/test_concurrence_stock.py
"""
import json, os, sys, subprocess, threading
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, "/home/user/.gfe_tools")
from seed_common import login, rpc, select, admin_sql  # noqa: E402

EMAIL = "nabildorego+kouyate@gmail.com"
ids = json.load(open("/home/user/.gfe_tools/ids.json"))
EID = ids["KOUYATE shop"]
RES = []
def verifier(nom, ok, detail=""):
    RES.append(ok); print(("OK    " if ok else "ECHEC ") + nom + ("" if ok else " - " + str(detail)))

tok, _ = login(EMAIL)
boutique = select(tok, "sites", f"entreprise_id=eq.{EID}&nom=eq.Boutique%20Abidjan&select=id")[0]["id"]
savon = select(tok, "v_articles_saisie", f"entreprise_id=eq.{EID}&designation=eq.Savon%20artisanal&select=id")[0]["id"]
com = select(tok, "commerciaux", f"entreprise_id=eq.{EID}&select=id")[0]["id"]

disponible = int(float(json.loads(admin_sql(f"select coalesce(sum(solde),0) s from gfe.v_stock where entreprise_id='{EID}' and article_id='{savon}' and site_id='{boutique}';"))[0]["s"]))

def vendre(i):
    try:
        r = rpc(tok, "saisir_vente", {"p_entreprise": EID, "p_date": "2026-11-05", "p_point": boutique, "p_commercial": com,
                                      "p_article": savon, "p_quantite": 1, "p_prix": None, "p_piece": f"CONC-{i}", "p_saisi_par": None})
        return bool(r.get("valide"))
    except Exception as e:
        return False

with ThreadPoolExecutor(max_workers=6) as ex:
    resultats = list(ex.map(vendre, range(6)))
acceptees = sum(resultats)
verifier(f"Stock disponible avant test = {disponible}", disponible == 2, disponible)
verifier(f"Exactement {min(6, disponible)} ventes acceptées sur 6 (obtenu {acceptees})", acceptees == min(6, disponible), resultats)
fin = int(float(json.loads(admin_sql(f"select coalesce(sum(solde),0) s from gfe.v_stock where entreprise_id='{EID}' and article_id='{savon}' and site_id='{boutique}';"))[0]["s"]))
verifier(f"Stock final = {disponible - acceptees} (obtenu {fin})", fin == disponible - acceptees, fin)
neg = int(json.loads(admin_sql(f"select count(*) c from gfe.v_stock where entreprise_id='{EID}' and solde < 0;"))[0]["c"])
verifier("Aucun stock négatif", neg == 0, neg)

subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "seed_demo_kouyate_rotsen.py")],
               env={**os.environ}, capture_output=True, timeout=600)
print(f"\nRÉSULTAT : {sum(RES)}/{len(RES)} contrôles réussis")
