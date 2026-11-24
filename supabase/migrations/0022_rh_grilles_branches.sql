-- 0022 : grilles des minima des autres branches (relevé AfricaPaieRH de l'arrêté 0050/MEPS/CAB du 19/05/2023).
-- Source : relevé AfricaPaieRH. Les lignes existantes sont mises à jour si besoin.
insert into gfe.rh_categories (branche, categorie, ordre, libelle, famille, minimum_conventionnel, source, explication) values
  ('btp', '1', 1, 'Manœuvre', 'Ouvrier', 75000, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '2', 2, 'OS1', 'Ouvrier', 79532, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '3A', 3, 'OS2', 'Ouvrier', 79931, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '3B', 4, 'OQ1', 'Ouvrier', 82323, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '4A', 5, 'OQ2', 'Ouvrier', 82522, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '4B', 6, 'OQ3', 'Ouvrier', 85512, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '5A', 7, 'Chef d''équipe 1', 'Ouvrier', 86908, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '5B', 8, 'Chef d''équipe 2', 'Ouvrier', 89100, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '6A', 9, 'Ouvrier hautement qualifié', 'Ouvrier', 90894, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '6B', 10, 'Maître ouvrier', 'Ouvrier', 101459, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('btp', '7', 11, 'Technicien BTP', 'Maîtrise', 138335, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Bâtiment, travaux publics et activités connexes (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('industrie', '1', 1, 'Manœuvre', 'Ouvrier', 75000, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Industrie mécanique, alimentaire, corps gras, chimique et transport (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('industrie', '2', 2, 'Catégorie 2', 'Employé', 86319, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Industrie mécanique, alimentaire, corps gras, chimique et transport (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('industrie', '3', 3, 'Catégorie 3', 'Employé', 86924, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Industrie mécanique, alimentaire, corps gras, chimique et transport (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('industrie', '4', 4, 'Catégorie 4', 'Employé', 92367, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Industrie mécanique, alimentaire, corps gras, chimique et transport (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('industrie', '5', 5, 'Catégorie 5', 'Employé', 110185, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Industrie mécanique, alimentaire, corps gras, chimique et transport (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('industrie', '6', 6, 'Catégorie 6', 'Employé', 124878, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Industrie mécanique, alimentaire, corps gras, chimique et transport (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('industrie', 'MNP', 7, 'Maîtrise débutant', 'Maîtrise', 118365, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Industrie mécanique, alimentaire, corps gras, chimique et transport (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('transit', '1', 1, 'Manœuvre', 'Ouvrier', 75000, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Auxiliaires du transport et transit (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('transit', '2', 2, 'Catégorie 2', 'Employé', 83634, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Auxiliaires du transport et transit (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('transit', '3', 3, 'Catégorie 3', 'Employé', 84220, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Auxiliaires du transport et transit (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('transit', '4', 4, 'Catégorie 4', 'Employé', 89493, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Auxiliaires du transport et transit (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('transit', '5', 5, 'Catégorie 5', 'Employé', 106757, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Auxiliaires du transport et transit (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('transit', '6', 6, 'Catégorie 6', 'Employé', 120993, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Auxiliaires du transport et transit (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('transit', 'MNP', 7, 'Maîtrise débutant', 'Maîtrise', 114682, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Auxiliaires du transport et transit (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('securite', '1', 1, 'Agent d''entretien', 'Employé', 75000, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Sécurité privée (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('securite', '2', 2, 'Vigile / agent de sécurité', 'Employé', 78000, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Sécurité privée (relevé AfricaPaieRH, état au 1er oct. 2026)', ''),
  ('securite', '3', 3, 'Vigile confirmé / maître-chien', 'Employé', 82200, 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille Sécurité privée (relevé AfricaPaieRH, état au 1er oct. 2026)', '')
on conflict (branche, categorie) do update set
  libelle = excluded.libelle, famille = excluded.famille, minimum_conventionnel = excluded.minimum_conventionnel,
  source = excluded.source, ordre = excluded.ordre;
