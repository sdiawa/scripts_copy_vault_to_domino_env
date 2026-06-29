# scripts_copy_vault_to_domino_env

# Domino Secret Sync — Vault COS vers variables d’environnement Domino

## 1. Objectif

Ce projet permet de récupérer automatiquement les secrets COS stockés dans HashiCorp Vault, puis de les injecter dans les variables d’environnement d’un projet Domino spécifique.

Le pipeline GitLab est lancé manuellement avec les informations suivantes :

```text
DOMINO_PROJECT_NAME
VAULT_COS_NAME
AP_CODE
VAULT_NAMESPACE
VAULT_ENV
```

Le script lit les secrets COS depuis Vault et crée les variables d’environnement dans Domino.

Important : le script ne remplace jamais une variable existante dans Domino. Si une variable existe déjà, le pipeline s’arrête. L’utilisateur doit supprimer manuellement la variable dans Domino puis relancer le pipeline.

---

## 2. Schéma global

```text
Utilisateur GitLab
      │
      │ Lance le pipeline avec :
      │ DOMINO_PROJECT_NAME
      │ VAULT_COS_NAME
      │ AP_CODE
      │ VAULT_NAMESPACE
      │ VAULT_ENV
      ▼
GitLab CI/CD
      │
      ├── Stage 1 : validate
      │       ├── Vérifie le projet Domino
      │       ├── Vérifie le path Vault
      │       ├── Vérifie les clés COS dans Vault
      │       └── Vérifie que les variables Domino n’existent pas déjà
      │
      ├── Stage 2 : fetch
      │       ├── Récupère les secrets COS depuis Vault
      │       └── Génère secrets.env
      │
      └── Stage 3 : inject
              ├── Lit secrets.env
              └── Crée les variables dans Domino
```

---

## 3. Mapping Vault vers Domino

Les secrets sont stockés dans Vault avec ces noms :

```text
COS_HMAC_KEYS_ACCESS_KEY_ID_READER
COS_HMAC_KEYS_SECRET_ACCESS_KEY_READER
```

Ils sont injectés dans Domino avec ces noms :

```text
COS_API_ID_KEY_READER_${AP_CODE}
COS_API_SECRET_KEY_READER_${AP_CODE}
```

Exemple avec :

```text
AP_CODE=AP123
```

Résultat dans Domino :

```text
COS_API_ID_KEY_READER_AP123
COS_API_SECRET_KEY_READER_AP123
```

Mapping complet :

```text
Vault:
COS_HMAC_KEYS_ACCESS_KEY_ID_READER
        │
        ▼
Domino:
COS_API_ID_KEY_READER_AP123


Vault:
COS_HMAC_KEYS_SECRET_ACCESS_KEY_READER
        │
        ▼
Domino:
COS_API_SECRET_KEY_READER_AP123
```

---

## 4. Structure Vault

Exemple de commande Vault utilisée manuellement :

```bash
VAULT_ADDR="https://vault-a-prod.com" \
VAULT_NAMESPACE="UPM_FRB/ECO021003014" \
VAULT_TOKEN="$VAULT_TOKEN_PROD_A" \
vault kv list secret/
```

Le secret COS est attendu ici :

```text
secret/objsto/${VAULT_COS_NAME}
```

Exemple :

```text
secret/objsto/co002ixxxx
```

---

## 5. Environnements Vault

Il existe 4 environnements Vault possibles :

```text
HPROD-A
HPROD-B
PROD-A
PROD-B
```

Chaque environnement possède sa propre URL Vault et son propre token.

Mapping :

```text
HPROD-A  -> VAULT_URL_HPROD_A  + VAULT_TOKEN_HPROD_A
HPROD-B  -> VAULT_URL_HPROD_B  + VAULT_TOKEN_HPROD_B
PROD-A   -> VAULT_URL_PROD_A   + VAULT_TOKEN_PROD_A
PROD-B   -> VAULT_URL_PROD_B   + VAULT_TOKEN_PROD_B
```

Exemple :

```text
VAULT_ENV=PROD-A
```

Le script utilisera automatiquement :

```text
VAULT_URL_PROD_A
VAULT_TOKEN_PROD_A
```

---

## 6. Variables à renseigner au lancement du pipeline

Ces variables sont saisies dans le formulaire GitLab au moment du lancement manuel :

```text
DOMINO_PROJECT_NAME=ia-bcef-dev
VAULT_COS_NAME=co002ixxxx
AP_CODE=AP123
VAULT_NAMESPACE=UPM_FRB/ECO021003014
VAULT_ENV=PROD-A
```

Description :

| Variable              | Description                                              | Exemple                |
| --------------------- | -------------------------------------------------------- | ---------------------- |
| `DOMINO_PROJECT_NAME` | Nom du projet Domino cible                               | `ia-bcef-dev`          |
| `VAULT_COS_NAME`      | Nom du COS dans Vault                                    | `co002ixxxx`           |
| `AP_CODE`             | Code applicatif utilisé dans le nom des variables Domino | `AP123`                |
| `VAULT_NAMESPACE`     | Namespace Vault                                          | `UPM_FRB/ECO021003014` |
| `VAULT_ENV`           | Environnement Vault exact                                | `PROD-A`               |

---

## 7. Variables protégées GitLab

Ces variables doivent être créées dans GitLab CI/CD Variables, en mode protected/masked si possible :

```text
DOMINO_URL
DOMINO_API_KEY

VAULT_URL_HPROD_A
VAULT_TOKEN_HPROD_A

VAULT_URL_HPROD_B
VAULT_TOKEN_HPROD_B

VAULT_URL_PROD_A
VAULT_TOKEN_PROD_A

VAULT_URL_PROD_B
VAULT_TOKEN_PROD_B
```

---

## 8. Pipeline GitLab

Le pipeline contient 3 stages :

```yaml
stages:
  - validate
  - fetch
  - inject
```

### Stage validate

Ce stage vérifie :

```text
- les variables obligatoires
- l’accès à Domino
- l’existence du projet Domino
- l’accès à Vault
- l’existence du path secret/objsto/${VAULT_COS_NAME}
- l’existence des deux clés COS dans Vault
- l’absence des variables cibles dans Domino
```

Si une variable existe déjà dans Domino, le pipeline s’arrête.

Exemple d’erreur :

```text
ERROR: La variable COS_API_ID_KEY_READER_AP123 existe déjà dans Domino.
Supprime-la manuellement depuis Domino puis relance le job.
```

### Stage fetch

Ce stage récupère les secrets depuis Vault et génère un fichier :

```text
secrets.env
```

Ce fichier est transmis au stage suivant via artifact GitLab.

### Stage inject

Ce stage lit `secrets.env` et crée les variables dans Domino.

Il fait uniquement des créations.

Il ne fait jamais de mise à jour.

---

## 9. Règle de sécurité importante

Le script ne doit jamais écraser une variable existante dans Domino.

Comportement attendu :

```text
Variable absente dans Domino
        │
        ▼
Création de la variable


Variable déjà présente dans Domino
        │
        ▼
Arrêt du pipeline
        │
        ▼
Suppression manuelle requise dans Domino
        │
        ▼
Relance du pipeline
```

Cette règle évite d’écraser un secret déjà utilisé par un projet.

---

## 10. Exemple complet

Entrée utilisateur dans GitLab :

```text
DOMINO_PROJECT_NAME=ia-bcef-dev
VAULT_COS_NAME=co002ixxxx
AP_CODE=AP123
VAULT_NAMESPACE=UPM_FRB/ECO021003014
VAULT_ENV=PROD-A
```

Vault sélectionné :

```text
VAULT_URL_PROD_A
VAULT_TOKEN_PROD_A
```

Path Vault lu :

```text
secret/objsto/co002ixxxx
```

Clés lues dans Vault :

```text
COS_HMAC_KEYS_ACCESS_KEY_ID_READER
COS_HMAC_KEYS_SECRET_ACCESS_KEY_READER
```

Variables créées dans Domino :

```text
COS_API_ID_KEY_READER_AP123
COS_API_SECRET_KEY_READER_AP123
```

---

## 11. Arborescence du projet

```text
domino-secret-sync/
├── .gitlab-ci.yml
└── scripts/
    └── copy_vault_to_domino_env.sh
```

---

## 12. Commande de test locale

Exemple de test local du stage validate :

```bash
export DOMINO_URL="https://domino.example.com"
export DOMINO_API_KEY="xxxx"

export VAULT_URL_PROD_A="https://vault-a-prod.com"
export VAULT_TOKEN_PROD_A="xxxx"

./scripts/copy_vault_to_domino_env.sh \
  validate \
  ia-bcef-dev \
  co002ixxxx \
  AP123 \
  UPM_FRB/ECO021003014 \
  PROD-A
```

---

## 13. Résultat attendu dans Domino

Dans le projet Domino cible, les variables suivantes doivent apparaître comme variables secrètes :

```text
COS_API_ID_KEY_READER_AP123
COS_API_SECRET_KEY_READER_AP123
```

Elles seront utilisables par les Jobs et Apps Domino selon le comportement de l’API Domino utilisée.

---

## 14. Points d’attention

* Vérifier si le moteur Vault `secret/` est en KV v1 ou KV v2.
* Si KV v1 : endpoint API attendu :

  ```text
  /v1/secret/objsto/co002ixxxx
  ```
* Si KV v2 : endpoint API attendu :

  ```text
  /v1/secret/data/objsto/co002ixxxx
  ```
* Le script actuel doit être aligné avec le type KV réel.
* Ne pas stocker les tokens Vault en clair dans le dépôt Git.
* Ne pas afficher les valeurs des secrets dans les logs.
* Protéger et masquer les variables GitLab sensibles.



curl -s \
  -H "X-Vault-Token: ${VAULT_TOKEN_PROD_A}" \
  -H "X-Vault-Namespace: UPM_FRB/ECO021003014" \
  "https://vault-a-prod.com/v1/secret/data/objsto/co002ixxxx" | jq .
