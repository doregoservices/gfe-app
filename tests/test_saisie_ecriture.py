"""Écriture depuis le formulaire SAISIE (client FKS) : une vente acceptée, une refusée (stock négatif).
Remet ensuite FKS à son jeu d'essai (tests/seed_stock_fks.py).
Lancer : GFE_TEST_PWD=... BASE_URL=http://127.0.0.1:8090 SB_TOKEN=... python3 tests/test_saisie_ecriture.py
"""
import os, sys, time, subprocess
from playwright.sync_api import sync_playwright

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8090")
PWD = os.environ["GFE_TEST_PWD"]
RES = []
def verifier(nom, ok, detail=""):
    RES.append(ok); print(("OK    " if ok else "ECHEC ") + nom + ("" if ok else " - " + detail))

def choisir(page, sel, texte_option):
    page.evaluate("""([s,t]) => { const el=document.querySelector(s); const o=[...el.options].find(x=>x.text.startsWith(t)); el.value=o.value; el.dispatchEvent(new Event('change')); }""", [sel, texte_option])

with sync_playwright() as p:
    nav = p.chromium.launch(); page = nav.new_context().new_page()
    page.goto(BASE + "/saisie.html"); page.wait_for_load_state("networkidle")
    page.fill("#cx-email", "nabildorego+fks@gmail.com"); page.fill("#cx-mdp", PWD); page.click("#cx-go")
    page.wait_for_selector("nav.onglets", timeout=30000); time.sleep(1.5)
    page.click("nav.onglets button[data-o=VENTE]"); time.sleep(1)

    # 1) Vente refusée : 1 000 bouteilles d'eau au PV Abidjan (stock 50)
    choisir(page, "#v-pv", "PV Abidjan"); choisir(page, "#v-com", "Kouamé Serge"); choisir(page, "#v-art", "Eau minérale")
    page.fill("#v-qte", "1000"); page.click("#v-ok"); time.sleep(3)
    verifier("Vente excessive refusée avec motif stock négatif", "stock négatif" in page.inner_text("#contenu"), page.inner_text("#contenu")[:300])

    # 2) Vente acceptée : 5 bouteilles
    page.click("nav.onglets button[data-o=VENTE]"); time.sleep(1)
    choisir(page, "#v-pv", "PV Abidjan"); choisir(page, "#v-com", "Kouamé Serge"); choisir(page, "#v-art", "Eau minérale")
    page.fill("#v-qte", "5"); page.click("#v-ok"); time.sleep(3)
    verifier("Vente de 5 acceptée (OK)", "Ligne enregistrée : OK" in page.inner_text("#contenu"), page.inner_text("#contenu")[:300])
    nav.close()

# remise à l'état du jeu d'essai
env = dict(os.environ)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "seed_stock_fks.py")], env=env, capture_output=True, text=True)
verifier("FKS remis au jeu d'essai (26 lignes)", "FKS : 26 lignes" in r.stdout, (r.stdout + r.stderr)[-300:])
print(f"{sum(RES)}/{len(RES)} contrôles OK")
sys.exit(0 if all(RES) else 1)
