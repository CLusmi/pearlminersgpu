# pearlminersgpu

Image Docker pour miner sur GPU NVIDIA (vast.ai, Clore.ai…) avec deux mineurs au choix :
**SRBMiner-MULTI** et **BzMiner**. Le mineur, la crypto, la pool, le wallet et le worker se
règlent par variables d'environnement dans le template.

Image publiée : `clusmi/pearlminersgpu` (tag `latest`), publique.

## Comment l'image est construite

Le workflow GitHub (`.github/workflows/build.yml`) :

1. cherche la **dernière version stable** de chaque mineur sur sa page GitHub officielle
   (`doktor83/SRBMiner-Multi`, `bzminer/bzminer`) ;
2. télécharge l'archive Linux et **vérifie son empreinte SHA-256** (celle que GitHub a
   enregistrée quand l'auteur a publié le fichier) : si elle ne correspond pas, la
   construction échoue ;
3. construit l'image et l'envoie sur Docker Hub en `clusmi/pearlminersgpu:latest`.

Les versions incluses s'affichent dans le résumé du workflow et au démarrage du conteneur.

## Mise en place (une seule fois)

1. **Docker Hub** : crée le dépôt `pearlminersgpu`, puis un token d'accès
   (Account settings → Personal access tokens → *Read & Write*).
2. **GitHub** : envoie les fichiers **à la racine** du dépôt, dossiers `.github` et `scripts`
   compris (pas dans un sous-dossier).
3. Dans le dépôt GitHub : *Settings → Secrets and variables → Actions → New repository secret*
   - `DOCKERHUB_USERNAME` : ton identifiant Docker Hub (`clusmi`)
   - `DOCKERHUB_TOKEN` : le token créé à l'étape 1
4. Onglet **Actions** → *Construire et publier l'image* → **Run workflow**.

Pour récupérer de nouvelles versions des mineurs, relance simplement le workflow.

## Variables d'environnement

| Variable | Obligatoire | Défaut | Rôle |
|---|---|---|---|
| `MINER` | non | `srbminer` | `srbminer` ou `bzminer` |
| `COIN` | non | `pearl` | `pearl`, `quantus`, ou tout autre nom d'algorithme (passé tel quel) |
| `POOL` | **oui** | | adresse:port de la pool, ex. `prl.kryptex.network:7048` |
| `WALLET` | **oui** | | ton adresse de wallet |
| `WORKER` | non | | nom du worker affiché par la pool |
| `PASS` | non | | mot de passe pool (rarement utile) |
| `EXTRA_ARGS` | non | | options en plus, passées telles quelles au mineur |
| `RESTART_DELAY` | non | `10` | secondes avant relance si le mineur s'arrête |
| `DRY_RUN` | non | | `1` : affiche la commande sans miner (pour vérifier) |

`ALGO` est accepté à la place de `COIN` (`ALGO=pearlhash` fonctionne), pour garder les
anciens templates.

Nom de l'algorithme envoyé à chaque mineur :

| `COIN` | SRBMiner | BzMiner |
|---|---|---|
| `pearl` | `--algorithm pearlhash` | `-a pearl` |
| `quantus` | `--algorithm quantus` | `-a quantus` |

Réglages fixes : minage CPU désactivé (SRBMiner `--disable-cpu`, BzMiner `--nvidia`),
journal en texte simple (BzMiner `-o log`). SRBMiner n'affiche rien hors d'un terminal :
son journal (`--log-file`) est recopié dans les logs du conteneur.

## Template vast.ai

- **Image Path:Tag** : `clusmi/pearlminersgpu`, version `latest`
- **Launch mode** : **Docker ENTRYPOINT** (pas Jupyter ni SSH, sinon le mineur ne démarre pas)
- **Champ des arguments** (affiché en mode ENTRYPOINT) : **vide**
- **Environment Variables** : `MINER`, `POOL`, `WALLET`, `WORKER` (et `COIN` si autre que Pearl)

Pour changer de mineur : modifie `MINER` dans le template et crée une nouvelle instance.

## Dépannage

- **Le log affiche `POOL est obligatoire` / `WALLET est obligatoire`** : variable manquante
  dans le template.
- **Le worker n'apparaît pas sur la pool** : certaines pools attendent le worker collé au
  wallet. Mets `WALLET=adresse.worker` et laisse `WORKER` vide.
- **Test sans miner** : ajoute `DRY_RUN=1`, le log montre la commande exacte puis s'arrête.
- **En local** : `docker run --rm --gpus all -e MINER=bzminer -e POOL=... -e WALLET=... clusmi/pearlminersgpu`
- **Aide d'un mineur** : `docker run --rm -e MINER=bzminer clusmi/pearlminersgpu --help`

## Frais des mineurs

Chaque mineur prélève des frais de développeur fixés par son auteur (quelques % du temps de
minage), déjà pris en compte dans le hashrate vu par la pool. Compare les mineurs sur ce
hashrate-là, pas sur celui affiché par le mineur.
