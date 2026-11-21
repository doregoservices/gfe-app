"""Tests de bout en bout : rôles (comptable / entreprise). Le stock : voir test_interfaces_stock.py.
Lancer : python3 tests/test_e2e_roles_stock.py   (site servi sur BASE_URL)
Les mots de passe de test sont lus dans les variables d'environnement GFE_TEST_PWD.
"""
import os, sys, time, datetime
from playwright.sync_api import sync_playwright

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8090")
PWD = os.environ["GFE_TEST_PWD"]
COMPTABLE = "nabildorego@gmail.com"
CLIENT = "nabildorego+client@gmail.com"  # client du cabinet GFE
COMPTABLE2 = "nabildorego+comptable2@gmail.com"
ENT_GFE = "4f20f10b-4dde-4f38-a75b-abf56d6c0c6b"      # GFE (cabinet)
ENT_KOUYATE = "330fd10f-d27f-46f9-9515-ad5ab84d53fb"  # KOUYATE shop
RESULTATS = []

def verifier(nom, ok, detail=""):
    RESULTATS.append((nom, bool(ok), detail))
    print(("OK   " if ok else "ECHEC"), nom, ("- " + detail) if detail and not ok else "")

def connexion(page, email, url):
    page.goto(url)
    time.sleep(1.5)
    if page.locator("#cx-email").count():   # écrans GESTION / SAISIE
        page.fill("#cx-email", email); page.fill("#cx-mdp", PWD); page.click("#cx-go")
    else:                                   # accueil (espace client)
        page.fill("#email", email); page.fill("#mdp", PWD); page.click("#bouton")
    time.sleep(3)

def deconnexion(page):
    try:
        page.evaluate("localStorage.clear()")
    except Exception:
        pass

with sync_playwright() as p:
    nav = p.chromium.launch()
    ctx = nav.new_context()
    page = ctx.new_page()

    # --- 1. Comptable : espace et liste
    connexion(page, COMPTABLE, BASE + "/index.html")
    verifier("comptable voit le rôle comptable", "Compte comptable" in page.text_content("#role"))
    liste=page.inner_text("#liste")
    verifier("comptable 1 voit GFE, KOUYATE shop et FKS", all(x in liste for x in ["GFE","KOUYATE shop","FKS"]), liste)
    verifier("comptable 1 ne voit pas ROTSEN", "ROTSEN" not in liste)
    verifier("comptable peut créer une entreprise", page.is_visible("#btnCreer"))
    page.locator("#liste li").filter(has_text="GFE — Gestion").get_by_text("Gérer les clients").click()
    time.sleep(1.5)
    verifier("comptable voit ses clients", CLIENT in page.inner_text("#clients"))
    verifier("comptable voit la réattribution", page.is_visible("#btnReattr"))
    page.screenshot(path="/tmp/capture_comptable.png", full_page=True)

    # --- 2. Entreprise (client) : pas de gestion
    deconnexion(page); page.goto(BASE + "/index.html"); time.sleep(1)
    page.evaluate("async () => {}")
    ctx.clear_cookies(); deconnexion(page)
    page2 = ctx.new_page()
    connexion(page2, CLIENT, BASE + "/index.html")
    verifier("client voit le rôle entreprise", "Compte entreprise" in page2.text_content("#role"))
    verifier("client GFE voit GFE", "GFE" in page2.inner_text("#liste"))
    verifier("client ne voit pas la gestion des clients", not page2.get_by_text("Gérer les clients").count())
    verifier("client GFE ne voit pas KOUYATE shop", "KOUYATE" not in page2.inner_text("#liste"))
    page2.close()

    # --- 3. Second comptable : seulement KOUYATE
    ctx.clear_cookies(); deconnexion(page)
    page3 = ctx.new_page()
    connexion(page3, COMPTABLE2, BASE + "/index.html")
    verifier("comptable 2 voit ROTSEN", "ROTSEN" in page3.inner_text("#liste"))
    verifier("comptable 2 ne voit pas KOUYATE ni GFE", "KOUYATE" not in page3.inner_text("#liste") and "GFE" not in page3.inner_text("#liste"))
    page3.close()

    # Le stock est couvert par tests/test_interfaces_stock.py et tests/test_saisie_ecriture.py

    nav.close()

echos = sum(1 for _, ok, _ in RESULTATS if ok)
print(f"\nRÉSULTAT : {echos}/{len(RESULTATS)} contrôles réussis")
sys.exit(0 if echos == len(RESULTATS) else 1)
