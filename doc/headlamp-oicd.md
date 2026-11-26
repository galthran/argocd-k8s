1. Keycloak

In your realm:

- Clients → Create client
    - Client ID: headlamp; Client authentication: On; Standard flow: On
    - Valid redirect URIs: https://headlamp.stonehold.local/oidc-callback
    - Web origins: https://headlamp.stonehold.local
    - Then copy the client secret from the Credentials tab.
- Client scopes → Create groups, then Mappers → By configuration → Group Membership
    - Token claim name: groups; Full group path: Off; Add to ID token: On
    - Add this scope to the headlamp client as a Default scope.
- Groups: create k8s-admins and add your user to it. Make sure the user has an email address and that Email verified is checked.

2. Kubernetes API server (MicroK8s, all 3 nodes)

On each node, add these lines to /var/snap/microk8s/current/args/kube-apiserver:

--oidc-issuer-url=https://keycloak.stonehold.local/realms/homelab
--oidc-client-id=headlamp
--oidc-username-claim=email
--oidc-username-prefix=oidc:
--oidc-groups-claim=groups
--oidc-groups-prefix=oidc:
--oidc-ca-file=/var/snap/microk8s/current/certs/keycloak-ca.crt   # only if Keycloak uses a private/self-signed CA

Then restart the node's Kubernetes services with sudo snap restart microk8s.daemon-kubelite. Restart one node at a time so the cluster stays up.

The API server must be able to reach the issuer URL over HTTPS. Check this from each node with:
curl https://keycloak.stonehold.local/realms/homelab/.well-known/openid-configuration

Most *.stonehold.local certificates come from a private CA, which is why you'd need the --oidc-ca-file line. The Headlamp pod also has to trust that CA (see
the troubleshooting list at the end).

3. RBAC (in git)

This file gives members of the Keycloak group k8s-admins full cluster access. Put it, for example, in
bootstrap/cluster-resources/in-cluster/oidc-admins-crb.yaml:

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
name: oidc-k8s-admins
roleRef:
apiGroup: rbac.authorization.k8s.io
kind: ClusterRole
name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: oidc:k8s-admins

For read-only users, bind another group to the built-in view ClusterRole the same way.

4. Headlamp: client secret via External Secrets

Save the Keycloak client secret in Azure Key Vault, for example as headlamp-oidc-client-secret. Then add this file as
apps/headlamp/overlays/learning/oidc-externalsecret.yaml and list it in that overlay's kustomization.yaml:

apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
name: headlamp-oidc
spec:
refreshInterval: 1h
secretStoreRef:
kind: ClusterSecretStore
name: microk8s-cluster-secret-store
target:
name: headlamp-oidc
template:
data:
OIDC_CLIENT_ID: headlamp
OIDC_ISSUER_URL: https://keycloak.stonehold.local/realms/homelab
OIDC_SCOPES: openid,profile,email,groups
OIDC_CLIENT_SECRET: "{{ .clientSecret }}"
data:
- secretKey: clientSecret
remoteRef:
key: headlamp-oidc-client-secret

In apps/headlamp/base/values.yaml, change the config.oidc section:

config:
oidc:
secret:
create: false          # stop creating the empty "oidc" secret
externalSecret:
enabled: true
name: headlamp-oidc
hasScopes: true
callbackURL: "https://headlamp.stonehold.local/oidc-callback"
usePKCE: true

Push both files. After Argo CD syncs, the Headlamp login page shows a Sign In button that sends you to Keycloak.

Troubleshooting

┌─────────────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                 Problem                 │                                                     Cause                                                     │
├─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Keycloak login works, but Headlamp then │ Step 2 is missing or wrong (issuer URL must match exactly, including /realms/homelab), or the CA isn't        │
│  shows "Unauthorized"                   │ trusted. See journalctl -u snap.microk8s.daemon-kubelite | grep -i oidc on a node.                            │
├─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Logged in, but every page shows         │ RBAC: the group in the token doesn't match oidc:k8s-admins, or the groups claim isn't in the ID token.        │
│ "Forbidden"                             │                                                                                                               │
├─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Keycloak shows "Invalid redirect URI"   │ The redirect URI in Keycloak doesn't match callbackURL exactly.                                               │
├─────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Headlamp logs show x509: certificate    │ The Headlamp pod doesn't trust Keycloak's CA. Mount the CA file and set SSL_CERT_FILE in the Headlamp values. │
│ signed by unknown authority             │                                                                                                               │
└─────────────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

The ServiceAccount token login keeps working alongside OIDC, so you can't lock yourself out.