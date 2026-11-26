External Secrets Operator (ESO) doesn't store any secrets itself. It copies secrets from an outside secret manager into normal Kubernetes Secrets and keeps them updated. You use two kinds of resources:

1. SecretStore / ClusterSecretStore: says where the secrets live 
(GCP Secret Manager, AWS Secrets Manager, Vault, Bitwarden, Azure Key Vault, 1Password, …) 
and how to log in to it. A SecretStore works in one namespace; a ClusterSecretStore works in every namespace.
2. ExternalSecret: says which keys to fetch and which Kubernetes Secret to create from them. 
It goes in the same namespace as the app that uses the secret.
