"""Annulation avec motif depuis SAISIE (client FKS) :
- une vente créée puis annulée : la ligne reste visible, barrée, avec son motif ;
- un motif vide n'annule rien ;
- l'annulation d'un achat qui ferait passer le stock sous zéro est refusée (GFE01) et la ligne reste active.
Remet ensuite FKS à son jeu d'essai (tests/seed_stock_fks.py).
Lancer : GFE_TEST_PWD=... BASE_URL=http://127.0.0.1:8090 python3 tests/test_annulation_interface.py
"""
import os, re, time, subprocess, sys
from playwright.sync_api import sync_playwright

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8090")
PWD = os.environ["GFE_TEST_PWD"]
RES = []
def verifier(nom, ok, detail=""):
    RES.append(ok); print(("OK    " if ok else "ECHEC ") + nom + ("" if ok else " - " + detail))

def choisir(page, sel, texte_option):
    page.evaluate("""([s,t]) => { const el=document.querySelector(s); const o=[...el.options].find(x=>x.text.startsWith(t)); el.value=o.value; el.dispatchEvent(new Event('change')); }""", [sel, texte_option])

def annuler(page, ligne, motif):
    """Clique « Annuler » sur la ligne, saisit le motif (ou rien) et valide la fenêtre."""
    ligne.locator("button.danger").click()
    page.wait_for_selector("dialog[open] #dl-motif")
    if motif: page.fill("#dl-motif", motif)
    page.click("dialog[open] button[value=ok]")
    time.sleep(3)

with sync_playwright() as p:
    nav = p.chromium.launch(); page = nav.new_context().new_page()
    page.goto(BASE + "/saisie.html"); page.wait_for_load_state("networkidle")
    page.fill("#cx-email", "nabildorego+fks@gmail.com"); page.fill("#cx-mdp", PWD); page.click("#cx-go")
    page.wait_for_selector("nav.onglets", timeout=30000); time.sleep(1.5)

    # 1) Vente de 7,5 cafés moulus 250 g au PV Abidjan, puis annulation motivée
    page.click("nav.onglets button[data-o=VENTE]"); time.sleep(1)
    choisir(page, "#v-pv", "PV Abidjan"); choisir(page, "#v-com", "Kouamé Serge"); choisir(page, "#v-art", "Café moulu 250 g")
    page.fill("#v-qte", "7.5"); page.click("#v-ok"); time.sleep(3)
    verifier("Vente de test enregistrée (OK)", "Ligne enregistrée : OK" in page.inner_text("#contenu"), page.inner_text("#contenu")[:200])

    ligne_test = page.locator("#contenu tbody tr", has_text="Café moulu 250 g").filter(has_text=re.compile(r"7[,.]5"))
    verifier("Ligne de test présente", ligne_test.count() >= 1, "aucune ligne 7,5")

    # 1a) motif vide : rien ne change
    annuler(page, ligne_test.first, "")
    verifier("Motif vide : la ligne n'est pas annulée", page.locator("#contenu tr.annule", has_text="Café moulu 250 g").filter(has_text=re.compile(r"7[,.]5")).count() == 0)

    # 1b) motif renseigné : annulée, barrée, motif affiché
    annuler(page, page.locator("#contenu tbody tr", has_text="Café moulu 250 g").filter(has_text=re.compile(r"7[,.]5")).first, "Erreur de saisie (test)")
    txt = page.inner_text("#contenu")
    barree = page.locator("#contenu tr.annule", has_text="Café moulu 250 g").filter(has_text=re.compile(r"7[,.]5"))
    verifier("Vente annulée : ligne barrée et visible", barree.count() == 1, txt[:200])
    verifier("Motif d'annulation affiché", "Annulée : Erreur de saisie (test)" in txt, txt[:200])
    verifier("Message de confirmation", "Ligne annulée" in txt)

    # 2) Annulation d'un achat qui ferait passer le stock sous zéro : refusée (GFE01)
    page.click("nav.onglets button[data-o=ACHAT]"); time.sleep(1)
    achat = page.locator("#contenu tbody tr", has_text="FAC-F-55").first
    verifier("Achat FAC-F-55 présent", achat.count() == 1)
    annuler(page, achat, "Test de refus (négatif)")
    txt = page.inner_text("#contenu")
    verifier("Annulation refusée : stock négatif signalé", "Annulation refusée" in txt and "négatif" in txt, txt[:300])
    verifier("Achat refusé : toujours actif (non barré)", page.locator("#contenu tr.annule", has_text="FAC-F-55").count() == 0)
    nav.close()

# Remise à l'état d'essai
subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "seed_stock_fks.py")], check=False, capture_output=True, timeout=600)
print(f"\nRÉSULTAT : {sum(RES)}/{len(RES)} contrôles réussis")
