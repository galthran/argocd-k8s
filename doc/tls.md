what does tls: {} do ?

tls: {} makes the route handle HTTPS traffic instead of plain HTTP. The braces are empty because there are no options to set, so Traefik uses its defaults.

Without a tls key, the router only matches plain HTTP. On the websecure entrypoint (port 443), clients send TLS, so the route never matches and you get a 404.

With tls: {}, Traefik does the following:
1. Handles the TLS handshake itself, which is called TLS termination.
2. Picks a certificate from its default TLS store. You haven't configured one, so Traefik serves its built-in self-signed TRAEFIK DEFAULT CERT.
3. Sends the decrypted request to nginx:80 over plain HTTP inside the cluster.

The same tls block takes options when you want more control:

tls:
secretName: nginx-tls        # use a cert from this k8s Secret instead of the default
certResolver: letsencrypt    # or let Traefik obtain a cert via ACME
options:
name: modern-tls           # reference a TLSOption (min TLS version, ciphers)
domains:
- main: nginx.stonehold.local

For a lab domain like stonehold.local, tls: {} is enough as long as you accept the browser warning. To get rid of the warning, the usual approach is a
secretName pointing at a certificate from a local CA. You can generate that certificate with cert-manager or mkcert.

✻ Worked for 4s · done 19:52

❯ I've generate certificate and sign it using local CA, how can I use it for nginx app ?

Ran 1 shell command

You need two steps: put the certificate into a Kubernetes TLS Secret, then point the IngressRoute at that Secret.

1. Create the Secret in the nginx namespace

kubectl -n nginx create secret tls nginx-tls \
--cert=path/to/nginx.stonehold.local.crt \
--key=path/to/nginx.stonehold.local.key

- The certificate's SAN must include nginx.stonehold.local. Browsers ignore the CN.
- If you signed it with an intermediate CA, append the intermediate to the .crt file, below the server certificate.
- Don't commit the key to git. This cluster has no Sealed Secrets, SOPS or External Secrets installed, so creating the Secret by hand is the simplest option
  for now. ArgoCD won't delete it, because it isn't part of the app's manifests.

2. Reference the Secret in apps/nginx/overlays/learning/nginx-ir.yaml

tls:
secretName: nginx-tls

The Secret has to be in the same namespace as the IngressRoute, which here is nginx.

3. Trust your CA on the machines you browse from

On Ubuntu, that means copying the CA certificate to /usr/local/share/ca-certificates/ and running update-ca-certificates. Firefox keeps its own trust store,
so import the CA there separately.

Check it works:

curl -v --cacert path/to/ca.crt https://nginx.stonehold.local

If the connection still shows TRAEFIK DEFAULT CERT, Traefik couldn't read the Secret. The usual causes are a wrong namespace or a typo in the name, and the
Traefik logs will say which.

If you tell me where the certificate files are, I can create the Secret and update the IngressRoute for you.

✻ Baked for 11s · done 19:59

❯ can I create this cert for more then one app, for instance for nginx and adminer?

Yes. One certificate can cover several hostnames in two ways:

- List each hostname in the SAN: DNS:nginx.stonehold.local, DNS:adminer.stonehold.local. You re-issue the certificate whenever you add an app.
- Use a wildcard: DNS:*.stonehold.local. This covers every app under stonehold.local. I'd recommend it for a lab. A wildcard only matches one level, so it
  covers nginx.stonehold.local but not a.b.stonehold.local.

A Secret can only be used by IngressRoutes in its own namespace, and nginx and adminer live in different namespaces. That leaves two ways to share the
certificate.

Option A (recommended): make it Traefik's default certificate

Create the Secret once, in the namespace where Traefik runs:

kubectl -n traefik create secret tls wildcard-stonehold-tls \
--cert=wildcard.crt --key=wildcard.key

Then add this to apps/traefik/base/values.yaml:

tlsStore:
default:
defaultCertificate:
secretName: wildcard-stonehold-tls

Every IngressRoute with tls: {} then gets your certificate automatically. Nginx already has tls: {}, adminer only needs that line added, and future apps need
nothing extra.

Option B: copy the Secret into each app's namespace

Create the same Secret in both nginx and adminer, and set tls.secretName on each IngressRoute. This works too, but every new app means another copy, and every
renewal means updating all of them.

If you go with Option A, I can add the tlsStore block to the Traefik values and tls: {} to adminer's IngressRoute. You'd only need to create the one Secret,
or tell me where the certificate files are and I'll create it.

✻ Worked for 10s · done 20:00

❯ content of the stonehold.local.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = stonehold.local

That file won't work for your apps. DNS.1 = stonehold.local only matches the bare stonehold.local, not nginx.stonehold.local or adminer.stonehold.local, so
browsers would still reject the certificate. Add the wildcard and re-sign:

authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = stonehold.local
DNS.2 = *.stonehold.local

What changed:
- DNS.2 = *.stonehold.local is the fix that matters. It covers nginx, adminer and any future app.
- extendedKeyUsage = serverAuth marks the certificate for TLS server use. macOS and iOS require it, and some other clients check it too.
- nonRepudiation and dataEncipherment are removed because a TLS server certificate doesn't need them. Removing them is just cleanup.

Re-sign using your existing key and CSR, adjusting file names to yours:

openssl x509 -req -in stonehold.local.csr \
-CA myCA.pem -CAkey myCA.key -CAcreateserial \
-out stonehold.local.crt -days 825 -sha256 \
-extfile stonehold.local.ext

Confirm both names made it into the certificate:

openssl x509 -in stonehold.local.crt -noout -ext subjectAltName
# expect: DNS:stonehold.local, DNS:*.stonehold.local

Keep -days at 825 or less. Some clients, mainly Apple ones, reject server certificates valid for longer than that, even from a private CA.

Once it's re-signed, create the Secret in the traefik namespace as in Option A, and I'll make the Traefik and adminer changes.

✻ Churned for 7s · done 20:03

❯ check if these steps are ok
1. Generate myCA certificate
   openssl genrsa -des3 -out myCA.key 3072
   openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem
2. Installing myCA certificate in the Ubuntu system
   sudo cp myCA.pem /usr/local/share/ca-certificates/myCA.crt
   sudo update-ca-certificates
3. Test that the certificate has been installed
   awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt | grep Corvus
4. Creating CA-Signed Certificate
   openssl genrsa -out aquila.test.key 2048
5. Creating a CSR request
   openssl req -new -key aquila.test.key -out aquila.test.csr
6. Creating aquila.test.ext file
7. Generating certificate using CSR, the CA private key, the CA certificate, and the config file
   openssl x509 -req -in aquila.test.csr -CA myCA.pem -CAkey myCA.key -CAcreateserial -out aquila.test.crt -days 825 -sha256 -extfile aquila.test.ext

The steps are correct and will work. A few details need attention, mainly browser trust on Linux.

Will cause problems

1. Chrome and Firefox won't trust your CA from step 2. On Linux, Chrome reads its own NSS database (~/.pki/nssdb), and Firefox has its own certificate store.
   Step 2 covers curl, wget, Python and similar tools, but not browsers. For Chrome, add:
   sudo apt install libnss3-tools
   certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "myCA" -i myCA.pem
   For Firefox, go to Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import, and tick "Trust this CA to identify websites".
2. Your file names don't match your domain. Steps 4–7 say aquila.test, but your domain is stonehold.local. The file names themselves don't matter. What
   matters is that the .ext file in step 7 has the SANs from my previous message (stonehold.local and *.stonehold.local). If you use an aquila.test.ext withDNS.1 = aquila.test, the certificate won't be valid for your apps.

Minor

3. -nodes in step 1 does nothing. It only applies when req generates a new key, and you're passing an existing one. You can drop it.
4. Step 5 asks for a CN. Enter stonehold.local. Browsers only check the SANs from the .ext file, but a matching CN keeps things tidy.
5. Step 3 only works if your CA's CN contains Corvus. A more direct test runs after step 7:
   openssl verify -CAfile myCA.pem stonehold.local.crt   # → OK
   openssl x509 -in stonehold.local.crt -noout -ext subjectAltName
6. Protect the keys: run chmod 600 myCA.key stonehold.local.key. myCA.key matters most, because anyone holding it can issue certificates your machine trusts for any domain.

Missing final step

8. Load the certificate into the cluster:
   kubectl -n traefik create secret tls wildcard-stonehold-tls \
   --cert=stonehold.local.crt --key=stonehold.local.key

About the .local domain

.local is reserved for mDNS, and on Ubuntu, Avahi or systemd-resolved can intercept *.local lookups. If name resolution works for you now, for example through /etc/hosts, you can ignore this. If you ever see odd DNS delays, switching to .test or home.arpa avoids the issue.