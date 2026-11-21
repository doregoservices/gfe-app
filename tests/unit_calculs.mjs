// Tests unitaires des calculs de stock-core.js (formules du classeur Drive).
// Lancer : node tests/unit_calculs.mjs
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";

// stock-core.js importe le client Supabase depuis un CDN : on le remplace par un stub
// (les fonctions de calcul n'en ont pas besoin).
const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "web", "assets", "stock-core.js"), "utf8")
  .replace(/^import \{ createClient \} from .*$/m, "const createClient = () => ({ rpc: null, auth: null, from: null });");
const tmp = mkdtempSync(join(tmpdir(), "stock-core-"));
const fichier = join(tmp, "stock-core.mjs");
writeFileSync(fichier, src);
const C = await import(pathToFileURL(fichier).href);

let n = 0;
const test = (nom, f) => { try { f(); n++; console.log("OK    " + nom); } catch (e) { console.log("ECHEC " + nom + "\n      " + e.message); process.exitCode = 1; } };

test("CMP : moyenne pondérée des seuls achats valides", () => {
  const achats = [
    { valide: true, article_id: "a", montant: 1000, quantite: 10 },
    { valide: true, article_id: "a", montant: 3000, quantite: 10 },
    { valide: false, article_id: "a", montant: 999999, quantite: 1 },   // en erreur : ignoré
  ];
  assert.equal(C.coutMoyenAchats(achats).get("a"), 200);
});

test("CMP : article sans quantité achetée absent", () => {
  assert.equal(C.coutMoyenAchats([{ valide: true, article_id: "b", montant: 0, quantite: 0 }]).has("b"), false);
});

test("Coût retenu : produit fini = somme des matières de la nomenclature au CMP", () => {
  const ent = { methode_cout: "cmp" };
  const articles = [
    { id: "m1", nature: "Matière première", prix_achat_ref: 100 },
    { id: "m2", nature: "Matière première", prix_achat_ref: 50 },
    { id: "p", nature: "Produit fini", prix_achat_ref: 0 },
  ];
  const achats = [{ valide: true, article_id: "m1", montant: 400, quantite: 4 }]; // CMP m1 = 100
  const nomen = [{ produit_id: "p", matiere_id: "m1", quantite: 2 }, { produit_id: "p", matiere_id: "m2", quantite: 3 }];
  const { retenu } = C.couts(ent, articles, achats, nomen);
  assert.equal(retenu.get("p"), 2 * 100 + 3 * 50);
});

test("Coût retenu : hors CMP, le prix de référence sert", () => {
  const { retenu } = C.couts({ methode_cout: "ref" }, [{ id: "m", nature: "Matière première", prix_achat_ref: 70 }],
    [{ valide: true, article_id: "m", montant: 400, quantite: 4 }], []);
  assert.equal(retenu.get("m"), 70);
});

test("État : négatif, rupture, sous seuil, OK", () => {
  assert.equal(C.etatStock(-1, 10), "Négatif");
  assert.equal(C.etatStock(0, 10), "Rupture");
  assert.equal(C.etatStock(10, 10), "Sous seuil");
  assert.equal(C.etatStock(11, 10), "OK");
  assert.equal(C.etatStock(5, 0), "OK");   // pas de seuil : jamais « sous seuil »
});

test("Stock par site : somme des mouvements", () => {
  const sa = C.stockParArticleSite([
    { article_id: "a", site_id: "s", qte: 100 }, { article_id: "a", site_id: "s", qte: -30 }, { article_id: "a", site_id: "t", qte: 5 },
  ]);
  assert.equal(sa.get("a|s"), 70);
  assert.equal(sa.get("a|t"), 5);
});

test("Période : jour, semaine (lundi à dimanche), mois", () => {
  assert.deepEqual(C.periode("Jour", "2026-11-18"), ["2026-11-18", "2026-11-18"]);
  assert.deepEqual(C.periode("Semaine", "2026-11-18"), ["2026-11-16", "2026-11-22"]); // 18/11/2026 est un mercredi
  assert.deepEqual(C.periode("Mois", "2026-11-18"), ["2026-11-01", "2026-11-30"]);
  assert.deepEqual(C.periode("Mois", "2026-02-10"), ["2026-02-01", "2026-02-28"]);
});

test("Contrôle articles : désignation en double et nature manquante", () => {
  const c = C.controleArticles([
    { id: "1", designation: "X", nature: "Produit fini" }, { id: "2", designation: "X", nature: "Produit fini" },
    { id: "3", designation: "Y", nature: "" },
  ]);
  assert.equal(c.get("1"), "Désignation en double");
  assert.equal(c.get("3"), "Nature manquante");
});

console.log(`\nRÉSULTAT : ${n} tests unitaires réussis${process.exitCode ? " (des échecs ci-dessus)" : ""}`);
