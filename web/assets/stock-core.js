// Noyau partagé des modules stock (GESTION = comptable, SAISIE = client).
// Reproduit les formules du classeur Drive GESTION_stock_v4 (ARTICLES, STOCK, POINTS, ACCUEIL).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const SUPABASE_URL = "https://ewcxndlelagtrlshadlj.supabase.co";
export const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV3Y3huZGxlbGFndHJsc2hhZGxqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyMjU4NzYsImV4cCI6MjEwMjgwMTg3Nn0.56ORPMKuu-RcbcqVTLuKC3gylOw5jQmXgIb1adXbjCg";
export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { db: { schema: "gfe" } });

export const $ = (id) => document.getElementById(id);
export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
export const F = (n) => (n === null || n === undefined || n === "" || isNaN(Number(n))) ? "" : Math.round(Number(n)).toLocaleString("fr-FR").replace(/\u202f|\u00a0/g, " ");
export const Q = (n) => (n === null || n === undefined || isNaN(Number(n))) ? "" : Number(n).toLocaleString("fr-FR", { maximumFractionDigits: 3 }).replace(/\u202f|\u00a0/g, " ");
export const num = (v) => (v === "" || v === null || v === undefined) ? null : Number(v);
export const txt = (v) => { const t = String(v ?? "").trim(); return t === "" ? null : t; };

export function aujourdhui() { const d = new Date(); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10); }

export async function rpc(nom, args) {
  const { data, error } = await sb.rpc(nom, args);
  if (error) throw new Error(error.message);
  return data;
}

// Lecture complète : PostgREST limite à 1 000 lignes par requête
export async function lireTout(table, { select = "*", filtre = null, ordre = null } = {}) {
  const lignes = [];
  for (let debut = 0; ; debut += 1000) {
    let q = sb.from(table).select(select).range(debut, debut + 999);
    if (filtre) q = filtre(q);
    if (ordre) q = q.order(ordre, { ascending: true });
    const { data, error } = await q;
    if (error) throw new Error(table + " : " + error.message);
    lignes.push(...(data || []));
    if (!data || data.length < 1000) break;
  }
  return lignes;
}

export async function session() { const { data } = await sb.auth.getSession(); return data.session; }

// Charge tout ce qui est nécessaire à une entreprise (droits RLS appliqués par Supabase)
export async function chargerEntreprise(eid) {
  const [ent] = await lireTout("entreprises", { filtre: (q) => q.eq("id", eid) });
  if (!ent) throw new Error("Entreprise introuvable ou sans droit d'accès");
  const [sites, coms, familles, articles, nomen, prods, achats, ventes, autres, vart] = await Promise.all([
    lireTout("sites", { filtre: (q) => q.eq("entreprise_id", eid), ordre: "nom" }),
    lireTout("commerciaux", { filtre: (q) => q.eq("entreprise_id", eid), ordre: "nom" }),
    lireTout("familles", { filtre: (q) => q.eq("entreprise_id", eid), ordre: "nom" }),
    rpc("articles_gestion", { p_entreprise: eid }),   // coûts et seuils : comptable uniquement
    lireTout("nomenclature", { filtre: (q) => q.eq("entreprise_id", eid) }),
    lireTout("saisies_production", { select: "*, saisies_production_matieres(*)", filtre: (q) => q.eq("entreprise_id", eid), ordre: "date_saisie" }),
    lireTout("saisies_achat", { filtre: (q) => q.eq("entreprise_id", eid), ordre: "date_saisie" }),
    lireTout("saisies_vente", { filtre: (q) => q.eq("entreprise_id", eid), ordre: "date_saisie" }),
    lireTout("saisies_autres", { filtre: (q) => q.eq("entreprise_id", eid), ordre: "date_saisie" }),
    lireTout("v_articles_saisie", { filtre: (q) => q.eq("entreprise_id", eid) }),
  ]);
  return { ent, sites, coms, familles, articles, nomen, prods, achats, ventes, autres, vart };
}

// Mouvements (stock) : réservés au comptable par RLS
export async function chargerMouvements(eid) {
  return lireTout("mouvements_stock", { filtre: (q) => q.eq("entreprise_id", eid) });
}

// ---- Calculs (formules Drive) ----
// CMP = somme des montants / somme des quantités des achats valides (ARTICLES I)
export function coutMoyenAchats(achats) {
  const m = new Map();
  for (const a of achats) {
    if (!a.valide) continue;
    const c = m.get(a.article_id) || { montant: 0, qte: 0 };
    c.montant += Number(a.montant || 0); c.qte += Number(a.quantite || 0);
    m.set(a.article_id, c);
  }
  const out = new Map();
  for (const [id, c] of m) if (c.qte) out.set(id, c.montant / c.qte);
  return out;
}

// Coût retenu (ARTICLES J et K) : produit fini = somme des matières de la nomenclature
export function couts(ent, articles, achats, nomen) {
  const cmp = coutMoyenAchats(achats);
  const base = new Map();
  for (const a of articles) {
    const c = ent.methode_cout === "cmp" && cmp.has(a.id) ? cmp.get(a.id) : Number(a.prix_achat_ref || 0);
    base.set(a.id, c);
  }
  const retenu = new Map();
  for (const a of articles) {
    if (a.nature === "Produit fini") {
      const somme = nomen.filter((n) => n.produit_id === a.id)
        .reduce((s, n) => s + Number(n.quantite) * (base.get(n.matiere_id) || 0), 0);
      retenu.set(a.id, somme);
    } else retenu.set(a.id, base.get(a.id));
  }
  return { base, retenu, cmp };
}

// Stock par article et site (STOCK F..O) : achats + production - matières consommées... = somme des mouvements
export function stockParArticleSite(mvts) {
  const m = new Map();
  for (const x of mvts) {
    const k = x.article_id + "|" + x.site_id;
    m.set(k, (m.get(k) || 0) + Number(x.qte));
  }
  return m;
}

// État (STOCK R) : Négatif, Rupture, Sous seuil, OK
export function etatStock(total, seuil) {
  if (total < 0) return "Négatif";
  if (total === 0) return "Rupture";
  if (seuil > 0 && total <= seuil) return "Sous seuil";
  return "OK";
}

// Contrôle ARTICLES L
export function controleArticles(articles) {
  const compte = new Map();
  for (const a of articles) compte.set(a.designation, (compte.get(a.designation) || 0) + 1);
  return new Map(articles.map((a) => [a.id, compte.get(a.designation) > 1 ? "Désignation en double" : (!a.nature ? "Nature manquante" : "OK")]));
}

// Période POINTS (B3 jour/semaine/mois, B4 date)
export function periode(type, dateStr) {
  const d = new Date(dateStr + "T00:00:00");
  if (type === "Jour") return [dateStr, dateStr];
  if (type === "Semaine") {
    const jour = (d.getDay() + 6) % 7; // lundi = 0
    const debut = new Date(d); debut.setDate(d.getDate() - jour);
    const fin = new Date(debut); fin.setDate(debut.getDate() + 6);
    return [debut.toISOString().slice(0, 10), fin.toISOString().slice(0, 10)];
  }
  const debut = new Date(d.getFullYear(), d.getMonth(), 1);
  const fin = new Date(d.getFullYear(), d.getMonth() + 1, 0);
  const iso = (x) => new Date(x.getTime() - x.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
  return [iso(debut), iso(fin)];
}

export function nomSite(sites, id) { const s = sites.find((x) => x.id === id); return s ? s.nom : ""; }
export function nomArticle(articles, id) { const a = articles.find((x) => x.id === id); return a ? a.designation : ""; }

// Connexion commune
export function formulaireConnexion(conteneur, surOk) {
  conteneur.innerHTML = `
    <div class="carte-connexion">
      <h2>Connexion</h2>
      <label>E-mail</label><input id="cx-email" type="email" autocomplete="username">
      <label>Mot de passe</label><input id="cx-mdp" type="password" autocomplete="current-password">
      <button id="cx-go">Se connecter</button>
      <div class="erreur" id="cx-err"></div>
    </div>`;
  $("cx-go").onclick = async () => {
    $("cx-err").textContent = "";
    const { error } = await sb.auth.signInWithPassword({ email: $("cx-email").value.trim(), password: $("cx-mdp").value });
    if (error) { $("cx-err").textContent = "Connexion refusée : " + error.message; return; }
    surOk();
  };
}

export const STYLE = `
  :root{--nuit:#1B1A3C;--rouge:#DC2529;--gris:#f3f3f7;--ok:#1e7b34;--ko:#b3261e;--avert:#8a5a00}
  *{box-sizing:border-box} body{margin:0;font-family:Arial,Calibri,sans-serif;color:#111;background:#fff}
  header.bandeau{background:var(--nuit);color:#fff;padding:12px 20px;display:flex;align-items:center;gap:16px;flex-wrap:wrap}
  header.bandeau img{height:44px} header.bandeau .titre{font-family:Georgia,serif;font-size:20px;font-weight:700}
  header.bandeau .droite{margin-left:auto;display:flex;gap:10px;align-items:center;font-size:13px}
  header.bandeau button,header.bandeau a.bouton{background:transparent;color:#fff;border:1px solid #fff;border-radius:4px;padding:6px 10px;font-size:13px;cursor:pointer;text-decoration:none}
  nav.onglets{display:flex;gap:4px;flex-wrap:wrap;background:var(--gris);padding:8px 12px;border-bottom:1px solid #d6d6e0}
  nav.onglets button{border:0;background:#fff;padding:8px 12px;border-radius:4px 4px 0 0;cursor:pointer;font-size:14px;color:var(--nuit)}
  nav.onglets button.actif{background:var(--nuit);color:#fff}
  main{padding:16px 20px}
  h2{font-family:Georgia,serif;color:var(--nuit);margin:8px 0 12px}
  h3{color:var(--nuit);margin:18px 0 8px;font-size:16px}
  table{border-collapse:collapse;width:100%;font-size:13px;margin:6px 0 14px}
  th,td{border:1px solid #d6d6e0;padding:5px 7px;text-align:left;vertical-align:middle}
  th{background:var(--nuit);color:#fff;font-weight:bold;position:sticky;top:0}
  td.num,th.num{text-align:right} tr.ko td{background:#fdecea} tr.ok td.ctl{color:var(--ok);font-weight:bold}
  td.ctl{font-weight:bold} td.ctl.ko{color:var(--ko)}
  td.etat-neg,td.etat-rup{color:var(--ko);font-weight:bold} td.etat-seuil{color:var(--avert);font-weight:bold} td.etat-ok{color:var(--ok)}
  input,select,textarea{padding:6px 8px;border:1px solid #bfc0cc;border-radius:4px;font-size:14px;font-family:inherit;background:#fffef5}
  input[readonly]{background:#eee} label{font-size:12px;color:var(--nuit);font-weight:bold;display:block;margin-top:8px}
  .grille{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px 12px;align-items:end}
  button.principal{background:var(--nuit);color:#fff;border:0;border-radius:4px;padding:8px 14px;font-size:14px;font-weight:bold;cursor:pointer;margin-top:8px}
  button.secondaire{background:#fff;color:var(--nuit);border:1px solid var(--nuit);border-radius:4px;padding:6px 10px;font-size:13px;cursor:pointer}
  button.danger{background:#fff;color:var(--ko);border:1px solid var(--ko);border-radius:4px;padding:4px 8px;font-size:12px;cursor:pointer}
  .msg{padding:8px 10px;border-radius:4px;margin:8px 0;font-size:14px} .msg.ok{background:#e7f5ea;color:var(--ok)} .msg.ko{background:#fdecea;color:var(--ko)}
  .erreur{color:var(--ko);font-size:13px;min-height:16px;margin-top:6px}
  .petit{font-size:12px;color:#555} .kpi{display:inline-block;background:var(--gris);border-radius:6px;padding:10px 14px;margin:4px 8px 8px 0;min-width:150px}
  .kpi b{display:block;font-size:20px;color:var(--nuit)} .kpi span{font-size:12px;color:#444}
  .carte-connexion{max-width:360px;margin:60px auto;border-top:4px solid var(--nuit);box-shadow:0 2px 14px rgba(27,26,60,.12);padding:28px}
  .carte-connexion input{width:100%} .carte-connexion button{width:100%;margin-top:14px}
  .ligne-matiere{display:grid;grid-template-columns:2fr 1fr 1fr;gap:6px;margin-bottom:6px}
  .cache{display:none !important} .wrap{overflow-x:auto}
  .bandeau-cible{background:#fff4d6;border:1px solid #e0b64a;padding:6px 12px;font-size:13px;margin:0 0 10px}
  @media print{header.bandeau,nav.onglets,.noprint{display:none}}
`;

export function injecterStyle() {
  const s = document.createElement("style"); s.textContent = STYLE; document.head.appendChild(s);
}
