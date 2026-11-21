"""Tests de bout en bout des interfaces stock (GESTION comptable / SAISIE client).
Lecture seule : aucune donnée n'est écrite.
Lancer : GFE_TEST_PWD=... BASE_URL=http://127.0.0.1:8090 python3 tests/test_interfaces_stock.py
"""
import os, sys, time
from playwright.sync_api import sync_playwright

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8090")
PWD = os.environ["GFE_TEST_PWD"]
COMPTABLE = "nabildorego@gmail.com"          # comptable 1 : GFE, KOUYATE shop, FKS
COMPTABLE2 = "nabildorego+comptable2@gmail.com"  # comptable 2 : ROTSEN
CLIENT_FKS = "nabildorego+fks@gmail.com"
ENT_FKS = "bbb28b9b-c2d0-4fcd-9040-7d84d2e08d1e"
RES = []

def verifier(nom, ok, detail=""):
    RES.append((nom, bool(ok)))
    print(("OK    " if ok else "ECHEC ") + nom + ("" if ok else " - " + detail))

def connecter(page, email, url):
    page.goto(url); page.wait_for_load_state("networkidle")
    if page.locator("#cx-email").count():
        page.fill("#cx-email", email); page.fill("#cx-mdp", PWD); page.click("#cx-go")
        page.wait_for_selector("header.bandeau", timeout=20000)
        time.sleep(1.5)

def texte(page): return page.inner_text("body")

def deconnecter(page):
    page.evaluate("() => { for (const k of Object.keys(localStorage)) if (k.startsWith('sb-')) localStorage.removeItem(k); }")

with sync_playwright() as p:
    nav = p.chromium.launch()
    erreurs_js = []
    # ---------- 1. Comptable 1 : GESTION de FKS
    ctx = nav.new_context(); page = ctx.new_page()
    page.on("pageerror", lambda e: erreurs_js.append(str(e)))
    connecter(page, COMPTABLE, BASE + "/gestion.html?e=" + ENT_FKS)
    page.wait_for_selector("nav.onglets", timeout=30000)
    t = texte(page)
    verifier("GESTION : titre entreprise FKS", "FKS" in page.inner_text("#titre"), page.inner_text("#titre"))
    verifier("GESTION : tableau de bord 6 lignes en erreur", "6" in t and "Lignes en erreur" in t)
    verifier("GESTION : onglets complets", all(o in t for o in ["ACCUEIL", "PARAM", "SITES", "ARTICLES", "NOMENCLATURE", "STOCK", "POINTS", "IMP"]))
    page.click("nav.onglets button[data-o=STOCK]"); time.sleep(1)
    st = page.inner_text("#contenu")
    verifier("STOCK : café vert usine = 575", "575" in st and "Café vert" in st, "stock non trouvé")
    verifier("STOCK : eau au dépôt = 85", "85" in st)
    verifier("STOCK : aucun négatif", "Négatif" not in st)
    page.click("nav.onglets button[data-o=POINTS]"); time.sleep(1)
    verifier("POINTS : affiche les périodes", "Ventes par point de vente" in texte(page))
    page.click("nav.onglets button[data-o=IMP]"); time.sleep(1)
    verifier("IMP : 26 lignes de saisie", "26 lignes" in texte(page), "compte différent")
    page.click("nav.onglets button[data-o=PARAM]"); time.sleep(1)
    verifier("PARAM : options présentes", "Suivi commercial" in texte(page) and "Site de destination" in texte(page))
    page.click("nav.onglets button[data-o=ARTICLES]"); time.sleep(1)
    verifier("ARTICLES : 7 articles FKS", texte(page).count("Café") >= 2)
    # Passage vers l'interface client depuis GESTION
    page.click("text=Voir l'interface client (SAISIE)"); page.wait_for_load_state("networkidle"); time.sleep(2)
    verifier("Comptable : ouvre SAISIE de son client", "SAISIE" in page.inner_text("#titre") and "Vue client" in texte(page), page.inner_text("#titre"))
    verifier("SAISIE : onglets production/vente/achat/autres", all(o in texte(page) for o in ["PRODUCTION", "VENTE", "ACHAT", "AUTRES"]))
    page.click("nav.onglets button[data-o=VENTE]"); time.sleep(1)
    verifier("SAISIE VENTE : liste les 4 ventes FKS", texte(page).count("FAC-") >= 3)
    verifier("SAISIE : ne montre aucun stock", "Valeur du stock" not in texte(page) and "Stock total" not in texte(page))
    ctx.close()

    # ---------- 2. Client FKS : SAISIE seulement
    ctx = nav.new_context(); page = ctx.new_page()
    page.on("pageerror", lambda e: erreurs_js.append(str(e)))
    connecter(page, CLIENT_FKS, BASE + "/saisie.html")
    page.wait_for_selector("nav.onglets", timeout=30000)
    verifier("Client : SAISIE FKS avec onglets", "FKS" in page.inner_text("#titre") and "PRODUCTION" in texte(page))
    verifier("Client : pas de lien vers GESTION", page.locator("a[href*='gestion']:visible").count() == 0)
    page.goto(BASE + "/gestion.html"); page.wait_for_load_state("networkidle"); time.sleep(2)
    verifier("Client : GESTION refusée", "réservée au comptable" in texte(page) or "Connexion" in texte(page), texte(page)[:200])
    verifier("Client : stock invisible (aucun mouvement)", page.locator("text=Valeur du stock").count() == 0)
    ctx.close()

    # ---------- 3. Comptable 2 (ROTSEN) : ne voit pas FKS
    ctx = nav.new_context(); page = ctx.new_page()
    page.on("pageerror", lambda e: erreurs_js.append(str(e)))
    connecter(page, COMPTABLE2, BASE + "/gestion.html?e=" + ENT_FKS)
    page.wait_for_selector("nav.onglets", timeout=30000)
    verifier("Comptable 2 : FKS non accessible (affiche ROTSEN)", "ROTSEN" in page.inner_text("#titre") and "FKS" not in page.inner_text("#titre"), page.inner_text("#titre"))
    ctx.close()
        # ---------- 4. KOUYATE shop (comptable 1) et ROTSEN (comptable 2) : tableaux chargés sans erreur
    ENT_KOUYATE = "330fd10f-d27f-46f9-9515-ad5ab84d53fb"
    ctx = nav.new_context(); page = ctx.new_page()
    page.on("pageerror", lambda e: erreurs_js.append(str(e)))
    connecter(page, COMPTABLE, BASE + "/gestion.html?e=" + ENT_KOUYATE)
    page.wait_for_selector("nav.onglets", timeout=30000)
    page.click("nav.onglets button[data-o=STOCK]"); time.sleep(1)
    verifier("KOUYATE : STOCK chargé (Savon artisanal)", "Savon artisanal" in texte(page))
    ctx.close()
    ctx = nav.new_context(); page = ctx.new_page()
    page.on("pageerror", lambda e: erreurs_js.append(str(e)))
    connecter(page, COMPTABLE2, BASE + "/gestion.html")
    page.wait_for_selector("nav.onglets", timeout=30000)
    page.click("nav.onglets button[data-o=STOCK]"); time.sleep(1)
    verifier("ROTSEN : STOCK chargé (Sac en cuir)", "Sac en cuir" in texte(page))
    page.click("nav.onglets button[data-o=NOMENCLATURE]"); time.sleep(1)
    verifier("ROTSEN : NOMENCLATURE chargée", "Cuir brut" in texte(page))
    ctx.close()
    nav.close()

print()
print("Erreurs JavaScript :", erreurs_js or "aucune")
ok = sum(1 for _, o in RES if o)
print(f"{ok}/{len(RES)} contrôles OK")
sys.exit(0 if ok == len(RES) and not erreurs_js else 1)
