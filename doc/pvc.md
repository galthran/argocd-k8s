To find the path yourself next time, for this or any other hostpath PVC:

```bash
PV=$(kubectl get pvc nginx-pvc -n nginx -o jsonpath='{.spec.volumeName}')
kubectl get pv $PV -o jsonpath='{.spec.hostPath.path}{"\n"}'
kubectl get pv $PV -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}'
```

## Serwer NFS na jednej VM-ce (np. node1)
```bash
sudo apt install -y nfs-kernel-server
sudo mkdir -p /srv/nfs/k8s
sudo chown nobody:nogroup /srv/nfs/k8s
echo "/srv/nfs/k8s *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
```

Na wszystkich node'ach: 
```bash
sudo apt install -y nfs-common.
```

### Sterownik CSI NFS przez ArgoCD
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: csi-driver-nfs
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
    chart: csi-driver-nfs
    targetRevision: "*"        # lepiej przypiąć konkretną wersję
    helm:
      values: |
        kubeletDir: /var/snap/microk8s/common/var/lib/kubelet   # ważne w microk8s!
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated: {}
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.56.11      # IP node'a z serwerem NFS
  share: /srv/nfs/k8s
reclaimPolicy: Retain        # po usunięciu PVC dane zostają na dysku
volumeBindingMode: Immediate
mountOptions: [nfsvers=4.1]
```

### Manifest PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-html
  annotations:
    argocd.argoproj.io/sync-options: Prune=false   # ArgoCD nigdy nie skasuje danych
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs
  resources:
    requests:
      storage: 1Gi
```

## Longhorn step by step

1. Najpierw przygotuj każdy węzeł (microk8s01–03), bo bez tego pody Longhorna nie wystartują:
```bash
   sudo apt install -y open-iscsi nfs-common
   sudo systemctl enable --now iscsid
```
nfs-common jest potrzebny tylko do wolumenów RWX.

2. Wypchnij zmiany:
```bash
   git add apps/longhorn bootstrap/cluster-resources/in-cluster/longhorn-system-ns.yaml
   git commit -m "Add Longhorn storage"
   git push
```

3. Sprawdź instalację:
```bash
   kubectl get pods -n longhorn-system
   kubectl get sc
```
   Na liście klas pojawi się longhorn, z RECLAIMPOLICY Retain.

4. Użyj Longhorna w PVC:
```yaml
   spec:
   storageClassName: longhorn
   accessModes:
    - ReadWriteOnce   # albo ReadWriteMany
      resources:
      requests:
      storage: 100Mi
```

Zmiana storageClassName w istniejącym nginx-pvc oznacza, że trzeba go usunąć i utworzyć na nowo. Obecny wolumen ma Delete, więc najpierw skopiuj z niego pliki.

