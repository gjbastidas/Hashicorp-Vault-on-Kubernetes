# Vault on Kubernetes
Running Hashicorp Vault on K8s

## Prerequisites
Code has been tested using the following tools:
- Docker  = 20.10.20
- Kind    = v0.17.0
- Kubectl = v1.25.2
- Helm    = v3.8.2
- Jq      = 1.6
- Make    = 3.81

## Objectives
- [x] HA and Raft: https://developer.hashicorp.com/vault/tutorials/raft/raft-storage
- [x] TLS: https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-tls
- [x] Auto unseal: https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-raft

## K8s cluster
Using [Kind](https://kind.sigs.k8s.io/) for Kubernetes.

### Create local kind cluster:
```shell
make kind-create-cluster
```

### Allow a couple of minutes while cluster nodes are in `Running` state:
```shell
kubectl get no
```

## Create TLS certificates
Using [cert-manager](https://cert-manager.io/docs/) for automatic certificate lifecycle management.

### Install cert-manager:
```shell
make helm-install-cert-manager
```

Allow a couple of minutes for successful installation. Run command below to check pod status:
```shell
kubectl -n cert-manager get po
```

You should see `cert-manager`, `cert-manager-cainjector` and `cert-manager-webhook` pods in a Running state.


### Create self-signed Certificate:
```shell
make create-self-signed-certificates
```

### Validate certificate:
```shell
kubectl -n vault get certificate vault-selfsigned
```

## Install Vault

All customization is done in the [values](./helm/vault/values.yaml) file.

```shell
make helm-install-vault
```

Allow a couple of minutes while Vault pods are in `Running` state. Use this command to check pods:
```shell
kubectl -n vault get po
```

### Vault init
```shell
make vault-init
```

### Vault unseal
```shell
make vault-unseal
```

Validate Vault is `Initialized` and `Unsealed`:
```shell
for i in {0..2}; do
  kubectl -n vault exec vault-$i -- vault status -format=json | jq -r '{"Initialized":.initialized, "Sealed":.sealed }'
done
```

### Make sure Vault is OK
```shell
export TOKEN="`kubectl -n vault get secret vault-secrets -o jsonpath=\"{.data.root_token}\" | base64 --decode`" && \
kubectl -n vault exec vault-0 -- vault login $TOKEN && \
kubectl -n vault exec vault-0 -- vault status && \
kubectl -n vault exec vault-0 -- vault operator raft list-peers
```

You now have a 3 node cluster with HA and TLS. You can now play with it by creating secrets, auth backends, etc. Enjoy!!

## Create and read a secret

### Shell at `vault-0` pod
```shell
kubectl -n vault exec -it vault-0 -- /bin/sh
```

### Enable kv-v2 secrets engine
```shell
vault secrets enable -path=secret kv-v2
```

### Create a secret custom path `secret/custom/testuser` with username and password
```shell
vault kv put secret/custom/testuser username="user" password="mysecretpassword"
```

### Validate secret is defined and exit pod
```shell
vault kv get secret/custom/testuser
```

Execute `exit` to exit the pod

### Port-forward to the Vault service:
```shell
kubectl -n vault port-forward service/vault 8200:8200
```

### Read the secret
Open a new terminal and the execute the following:
```shell
kubectl -n vault get secret vault-ha-tls -o jsonpath="{.data.ca\.crt}" | base64 --decode > ca.crt && \
export TOKEN="`kubectl -n vault get secret vault-secrets -o jsonpath=\"{.data.root_token}\" | base64 --decode`" && \
curl --cacert $PWD/ca.crt \
   --header "X-Vault-Token: $TOKEN" \
   https://127.0.0.1:8200/v1/secret/data/custom/testuser | jq .data.data
```

**Press Ctrl+C to exit port forwarding**

## Delete everything
```shell
make kind-delete-cluster
```