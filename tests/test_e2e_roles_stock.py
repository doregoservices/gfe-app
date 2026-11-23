"""Tests de bout en bout des rôles, à partir de la page unique (web/index.html).
Structure : cabinet GFE = deux comptables ; trois entreprises (FKS et KOUYATE shop pour le comptable 1,
ROTSEN pour le comptable 2) ; un compte client par entreprise.
Lancer : GFE_TEST_PWD=... BASE_URL=http://127.0.0.1:8090 python3 (ou https://doregoservices.github.io/gfe-app/web) tests/test_e2e_roles_stock.py
Le stock est couvert par test_interfaces_stock.py, test_saisie_ecriture.py et test_annulation_interface.py.
"""
import os, sys, time
from playwright.sync_api import sync_playwright

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8090")
PWD = os.environ["GFE_TEST_PWD"]
COMPTABLE1 = "nabildorego@gmail.com"            # cabinet GFE : FKS, KOUYATE shop
COMPTABLE2 = "nabildorego+comptable2@gmail.com"  # cabinet GFE : ROTSEN
CLIENT_FKS = "nabildorego+fks@gmail.com"
RESULTATS = []

def verifier(nom, ok, detail=""):
    RESULTATS.append((nom, bool(ok)))
    print(("OK   " if ok else "ECHEC"), nom, ("- " + str(detail)) if detail and not ok else "")

def connexion(page, email):
    """Ouvre la page unique et se connecte."""
    page.goto(BASE + "/index.html"); page.wait_for_load_state("networkidle")
    page.fill("#email", email); page.fill("#mdp", PWD); page.click("#bouton")
    time.sleep(3)

def deconnexion(page):
    page.goto(BASE + "/index.html"); page.wait_for_load_state("networkidle")
    if page.locator("#deconnexion").is_visible():
        page.click("#deconnexion"); time.sleep(1)

with sync_playwright() as p:
    nav = p.chromium.launch()
    ctx = nav.new_context()

    # --- 1. Comptable 1 : ses entreprises, les liens Gestion et Saisie, la gestion des clients
    page = ctx.new_page()
    connexion(page, COMPTABLE1)
    liste = page.inner_text("#liste")
    verifier("comptable 1 : rôle cabinet GFE", "Cabinet GFE" in page.text_content("#role"))
    verifier("comptable 1 voit FKS et KOUYATE shop", "FKS" in liste and "KOUYATE shop" in liste, liste)
    verifier("comptable 1 ne voit pas ROTSEN", "ROTSEN" not in liste)
    verifier("comptable 1 n'a pas d'entreprise « GFE » (le cabinet n'est pas un client)", "GFE — Gestion" not in liste and "\nGFE\n" not in ("\n" + liste + "\n"), liste)
    verifier("comptable 1 a un lien Gestion et un lien Saisie",
             page.locator("#liste a", has_text="Gestion").count() >= 2 and page.locator("#liste a", has_text="Saisie").count() >= 2)
    page.locator("#liste li").filter(has_text="FKS").get_by_text("Gérer les clients").click(); time.sleep(1.5)
    verifier("comptable 1 voit le client de FKS", CLIENT_FKS in page.inner_text("#clients"), page.inner_text("#clients")[:200])
    verifier("comptable 1 voit la réattribution", page.is_visible("#btnReattr"))

    # Le comptable ouvre l'interface client de son entreprise
    page.locator("#liste li").filter(has_text="FKS").locator("a", has_text="Saisie").click(); page.wait_for_load_state("networkidle")
    page.wait_for_load_state("networkidle"); time.sleep(2)
    verifier("comptable accède à la SAISIE de FKS (vue client)", "FKS" in page.inner_text("#titre") and page.is_visible("nav.onglets"))
    verifier("la SAISIE du comptable affiche le retour vers GESTION", page.is_visible("#retour"))
    page.close()

    # --- 2. Client FKS : saisie seulement, aucun accès à la gestion
    ctx.close(); ctx = nav.new_context()   # session neuve (la session est dans le stockage local)
    page = ctx.new_page()
    connexion(page, CLIENT_FKS)
    liste = page.inner_text("#liste")
    verifier("client : rôle compte client", "Compte client" in page.text_content("#role"))
    verifier("client voit FKS", "FKS" in liste, liste)
    verifier("client ne voit pas KOUYATE shop", "KOUYATE" not in liste)
    verifier("client n'a aucun lien vers la gestion", page.locator("#liste a", has_text="Gestion").count() == 0)
    verifier("client ne voit pas la gestion des clients", page.get_by_text("Gérer les clients").count() == 0)
    page.locator("#liste a", has_text="Saisie").first.click(); page.wait_for_load_state("networkidle"); time.sleep(2)
    verifier("client ouvre la SAISIE de FKS", "FKS" in page.inner_text("#titre") and page.is_visible("nav.onglets"))
    verifier("client n'a pas de retour vers GESTION", not page.is_visible("#retour"))
    page.goto(BASE + "/gestion.html?e=bbb28b9b-c2d0-4fcd-9040-7d84d2e08d1e"); page.wait_for_load_state("networkidle"); time.sleep(2)
    verifier("client bloqué sur l'URL de GESTION", page.locator("nav.onglets").count() == 0 and "réservée au comptable" in page.inner_text("#principal"), page.inner_text("#principal")[:200])
    page.close()

    # --- 3. Comptable 2 : seulement ROTSEN
    ctx.close(); ctx = nav.new_context()   # session neuve (la session est dans le stockage local)
    page = ctx.new_page()
    connexion(page, COMPTABLE2)
    liste = page.inner_text("#liste")
    verifier("comptable 2 voit ROTSEN", "ROTSEN" in liste, liste)
    verifier("comptable 2 ne voit ni FKS ni KOUYATE shop", "FKS" not in liste and "KOUYATE" not in liste)
    page.close()

    nav.close()

echos = sum(1 for _, ok in RESULTATS if ok)
print(f"\nRÉSULTAT : {echos}/{len(RESULTATS)} contrôles réussis")
sys.exit(0 if echos == len(RESULTATS) else 1)
