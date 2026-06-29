# Automatisation de l'injection des secrets COS Vault vers Domino

## 1. Objectif

### Contexte

Les projets Domino utilisent des variables d'environnement contenant les identifiants COS (Object Storage).

Jusqu'à présent, ces variables étaient créées manuellement dans Domino :

* connexion à Vault
* récupération des secrets
* copie des valeurs
* création des variables Domino

Cette procédure est :

* chronophage ;
* source d'erreurs humaines ;
* difficilement traçable.

### Objectif de la solution

Automatiser la récupération des secrets COS depuis HashiCorp Vault et leur création dans Domino via l'API REST.

Le pipeline garantit également qu'aucune variable existante ne soit écrasée automatiquement.

---

# 2. Architecture

```text
                  GitLab Pipeline
                         │
                         ▼
               Saisie des paramètres
                         │
                         ▼
                 Stage 1 : Validate
                         │
        ┌────────────────┴────────────────┐
        │                                 │
        ▼                                 ▼
 Vérification Vault                 Vérification Domino
        │                                 │
        └────────────────┬────────────────┘
                         │
                         ▼
                  Stage 2 : Fetch
                         │
                         ▼
            Lecture des secrets Vault
                         │
                         ▼
                Génération secrets.env
                         │
                         ▼
                 Stage 3 : Inject
                         │
                         ▼
         Création des variables Domino
```

---

# 3. Fonctionnement

Le pipeline comporte trois étapes.

## Stage 1 — Validate

Cette étape réalise toutes les vérifications nécessaires avant toute modification.

Contrôles effectués :

* validation des paramètres saisis ;
* sélection du bon environnement Vault ;
* récupération du Project ID Domino ;
* vérification de l'existence du secret Vault ;
* vérification de la présence des deux clés COS ;
* vérification que les variables Domino n'existent pas déjà.

Si une variable est déjà présente dans Domino, le pipeline s'arrête volontairement.

Aucune modification n'est effectuée.

---

## Stage 2 — Fetch

Lecture des secrets dans Vault.

Chemin utilisé :

```
objsto/data/<VAULT_COS_NAME>
```

Exemple :

```
objsto/data/co002i006891
```

Secrets récupérés :

```
cos_hmac_keys_access_key_id_reader

cos_hmac_keys_secret_access_key_reader
```

Les deux valeurs sont stockées temporairement dans :

```
secrets.env
```

Cet artefact est conservé uniquement pendant l'exécution du pipeline.

---

## Stage 3 — Inject

Création des variables Domino via l'API REST.

Variables créées :

```
COS_API_ID_KEY_READER_<AP_CODE>

COS_API_SECRET_KEY_READER_<AP_CODE>
```

Exemple :

```
AP_CODE = AP90225

↓

COS_API_ID_KEY_READER_AP90225

COS_API_SECRET_KEY_READER_AP90225
```

---

# 4. Paramètres du pipeline

Lors du lancement du pipeline, les informations suivantes doivent être renseignées.

| Paramètre           | Description          | Exemple                    |
| ------------------- | -------------------- | -------------------------- |
| DOMINO_PROJECT_NAME | Nom du projet Domino | appli-sample-dev           |
| VAULT_COS_NAME      | Nom du secret COS    | co002i006891               |
| AP_CODE             | Code application     | AP90225                    |
| VAULT_NAMESPACE     | Namespace Vault      | UPM_FRB/RESFR/EC002I003013 |
| VAULT_ENV           | Environnement Vault  | HPROD-A                    |

---

# 5. Environnements Vault

Le pipeline sélectionne automatiquement la bonne URL et le bon token Vault.

| VAULT_ENV | URL utilisée  | Token GitLab        |
| --------- | ------------- | ------------------- |
| HPROD-A   | Vault HPROD A | VAULT_TOKEN_HPROD_A |
| HPROD-B   | Vault HPROD B | VAULT_TOKEN_HPROD_B |
| PROD-A    | Vault PROD A  | VAULT_TOKEN_PROD_A  |
| PROD-B    | Vault PROD B  | VAULT_TOKEN_PROD_B  |

Aucun token n'est demandé lors du lancement du pipeline.

---

# 6. Variables GitLab requises

Les variables suivantes doivent être configurées dans les variables CI/CD du projet GitLab.

## Domino

```
DOMINO_URL

DOMINO_PROJECT_KEY
```

## Vault

```
VAULT_URL_HPROD_A
VAULT_URL_HPROD_B
VAULT_URL_PROD_A
VAULT_URL_PROD_B

VAULT_TOKEN_HPROD_A
VAULT_TOKEN_HPROD_B
VAULT_TOKEN_PROD_A
VAULT_TOKEN_PROD_B
```

Toutes les variables sensibles doivent être :

* Protected
* Masked

---

# 7. Sécurité

Le pipeline applique plusieurs mécanismes de sécurité.

## Pas d'écrasement

Si une variable existe déjà dans Domino :

```
Le pipeline s'arrête.

Aucune mise à jour n'est effectuée.
```

La suppression doit être réalisée manuellement depuis Domino.

Cette approche évite toute perte accidentelle d'un secret en production.

---

## Secrets Vault

Les secrets :

* ne sont jamais affichés dans les logs ;
* ne sont jamais stockés dans Git ;
* sont uniquement transmis à Domino via HTTPS.

---

## Traçabilité

Chaque exécution est historisée dans GitLab.

Les opérations sont entièrement auditables.

---

# 8. Exemple d'exécution

Entrées :

```
DOMINO_PROJECT_NAME = appli-sample-dev

VAULT_COS_NAME = co002i006891

AP_CODE = AP90225

VAULT_NAMESPACE = UPM_FRB/RESFR/EC002I003013

VAULT_ENV = HPROD-A
```

Secrets Vault :

```
cos_hmac_keys_access_key_id_reader

cos_hmac_keys_secret_access_key_reader
```

Variables Domino créées :

```
COS_API_ID_KEY_READER_AP90225

COS_API_SECRET_KEY_READER_AP90225
```

---

# 9. Gestion des erreurs

Le pipeline peut s'arrêter dans les cas suivants :

* Projet Domino introuvable
* Namespace Vault invalide
* Secret Vault inexistant
* Clé COS absente
* Variable Domino déjà existante
* URL Vault non configurée
* Token Vault absent

Chaque erreur est explicite afin de faciliter le diagnostic.

---

# 10. Bénéfices

* automatisation complète ;
* suppression des manipulations manuelles ;
* réduction du risque d'erreur ;
* sécurité renforcée ;
* audit GitLab ;
* pipeline réutilisable pour tous les projets Domino ;
* support de plusieurs environnements Vault.
