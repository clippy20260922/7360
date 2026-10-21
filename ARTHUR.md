# Arthur — règles et suivi (équipe 7360)

## Règles de travail

- On travaille **uniquement** sur `arthur` et ses sous-branches `arthur-<sujet>`
  (ex. `arthur-zone`, `arthur-paiement`) : un ticket = une sous-branche, fusionnée ensuite dans `arthur`.
- `master-dev` est la **branche commune** : c'est dans `master-dev` qu'on fusionnera `arthur` plus tard.
- Les branches des autres (`chiara-backend`, `visualisation3D`, `yacine`, `master`...) : **on n'y touche jamais**.
- On ne modifie jamais ce que les autres ont fait : on ne fait qu'**ajouter** (nouveaux fichiers, nouvelles pages).
- On ne fait **que du développement de fonctionnalités** : des tickets concrets (« ajouter une page qui... »)
  pour avoir zéro conflit. Pas de correction ni de réorganisation du code des autres.
- Avant de proposer `arthur` pour `master-dev` : récupérer d'abord `master-dev` dans `arthur`
  (`git fetch` puis `git merge origin/master-dev`).

## Jira

- **Actuel** : <https://7360.atlassian.net/jira/software/projects/SCRUM/boards/1/backlog> (projet SCRUM)
- Ancien, ne plus utiliser : `essiee2627.atlassian.net`, projet YO7360 (ses tickets ont été importés dans SCRUM)

## Drive de l'équipe

- <https://drive.google.com/drive/u/2/folders/1Zznjjepasd1Pk4-ETQ0Kb6NIXFCTXcHe> (« Chaire CapGemini - 7360 » : tableur principal, Sprint 0, infos équipe)

## Points

- 1 point = 1 h 30 de travail (doc « Sprint 0 »).
- Sprints de 2 semaines. Sprint 2 : du 09/10 au 23/10, 29 points engagés par l'équipe.
- Prévision de l'équipe (Sprint 0) : 24 points / 2 semaines à 5, soit **≈ 2,4 points par personne et par semaine** (≈ 3 h 30).
- **Mon objectif : 6 points par sprint**, soit **3 points par semaine** (≈ 4 h 30).
- Sprint 2 : 8 points m'étaient assignés, c'est 2 de trop par rapport à l'objectif.

## Tickets faits

| Ticket | Points | Sprint | Branches | Contenu |
|---|---|---|---|---|
| SCRUM-18 — U - Choisir une zone géographique | 5 | Sprint 2 | `arthur-zone`, `arthur-zone-client` | routes `/data/zone` et `/data/free/zone`, tests, doc, page Flutter `zone_page.dart` |
| SCRUM-13 — U - Payer la place | 3 | Sprint 2 | `arthur-paiement`, `arthur-paiement-client` | routes `/data/{id}/prix` et `/data/{id}/payer`, table des paiements, tests, doc, page Flutter `paiement_page.dart` |

**Total : 8 points.** Au 21/10, les deux tickets sont encore « En cours » dans Jira : à passer en revue / terminé.

## État des branches (21/10)

`arthur` contient déjà tout `master-dev` (aucun commit de `master-dev` ne manque dans `arthur`).
