BASE_DIR 										?= ${PWD}
KIND_K8S_VERSION 						?= "1.24.7"
KIND_CLUSTER_NAME 					?= "vault"
VAULT_NAMESPACE							?= "vault"
VAULT_SECRETS								?= "vault-secrets"
HELM_VAULT_VERSION					?= "0.22.1"
HELM_CERT_MANAGER_NAMESPACE ?= "cert-manager"
HELM_CERT_MANAGER_VERSION 	?= "v1.10.1"
TLS_SECRET_NAME							?= "vault-ha-tls"

delete-self-signed-certificates:
	@ kubectl delete -f ${BASE_DIR}/helm/cert-manager/self-signed && \
		kubectl -n vault delete secret ${TLS_SECRET_NAME}
.PHONY: delete-self-signed-certificates

create-self-signed-certificates:
	@ kubectl create ns vault && \
		kubectl create -f ${BASE_DIR}/helm/cert-manager/self-signed
.PHONY: create-self-signed-certificates

helm-uninstall-cert-manager:
	@ helm delete cert-manager -n ${HELM_CERT_MANAGER_NAMESPACE}
.PHONY: helm-uninstall-cert-manager

helm-install-cert-manager: helm-install-cert-manager-repo
	@ helm install cert-manager jetstack/cert-manager \
  --namespace ${HELM_CERT_MANAGER_NAMESPACE} --create-namespace \
  --version ${HELM_CERT_MANAGER_VERSION} \
  --set installCRDs=true
.PHONY: helm-install-cert-manager

helm-install-cert-manager-repo:
	@ helm repo add jetstack https://charts.jetstack.io && \
		helm repo update
.PHONY: helm-install-cert-manager-repo

vault-init:
	@ rm -f cluster-keys.json && \
		kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > cluster-keys.json && \
		kubectl -n ${VAULT_NAMESPACE} create secret generic ${VAULT_SECRETS} \
		--from-literal=unseal_keys_b64=`jq -r ".unseal_keys_b64[]" cluster-keys.json` \
		--from-literal=unseal_keys_hex=`jq -r ".unseal_keys_hex[]" cluster-keys.json` \
		--from-literal=root_token=`jq -r ".root_token" cluster-keys.json` && \
		rm -f cluster-keys.json
.PHONY: vault-init

vault-unseal:
	@ VAULT_UNSEAL_KEY="`kubectl -n ${VAULT_NAMESPACE} get secret ${VAULT_SECRETS} -o jsonpath=\"{.data.unseal_keys_b64}\" | base64 --decode`" && \
		kubectl -n ${VAULT_NAMESPACE} exec vault-0 -- vault operator unseal $$VAULT_UNSEAL_KEY && \
		for i in {1..2}; do \
			kubectl -n ${VAULT_NAMESPACE} exec vault-$$i -- vault operator raft join -address=https://vault-$$i.vault-internal:8200 \
				-leader-ca-cert="`kubectl -n ${VAULT_NAMESPACE} get secret ${TLS_SECRET_NAME} -o jsonpath=\"{.data.ca\.crt}\" | base64 --decode`" \
				-leader-client-cert="`kubectl -n ${VAULT_NAMESPACE} get secret ${TLS_SECRET_NAME} -o jsonpath=\"{.data.tls\.crt}\" | base64 --decode`" \
				-leader-client-key="`kubectl -n ${VAULT_NAMESPACE} get secret ${TLS_SECRET_NAME} -o jsonpath=\"{.data.tls\.key}\" | base64 --decode`" \
				https://vault-0.vault-internal:8200; \
		done && \
		for i in {1..2}; do \
			kubectl -n ${VAULT_NAMESPACE} exec vault-$$i -- vault operator unseal $$VAULT_UNSEAL_KEY; \
		done
.PHONY: vault-unseal

helm-uninstall-vault:
	@ helm delete vault -n vault && \
		kubectl -n vault delete pvc,pv --all --grace-period=0 --force
.PHONY: helm-uninstall-vault

helm-install-vault: helm-install-hashicorp-repo
	@ helm install vault hashicorp/vault \
			-f ${BASE_DIR}/helm/vault/values.yaml \
			-n ${VAULT_NAMESPACE} --create-namespace \
			--version ${HELM_VAULT_VERSION}
.PHONY: helm-install-vault

helm-install-hashicorp-repo:
	@ helm repo add hashicorp https://helm.releases.hashicorp.com && \
		helm repo update
.PHONY: helm-install-repo

kind-create-cluster: kind-delete-cluster
	@	kind create cluster \
		--image kindest/node:v${KIND_K8S_VERSION} \
		--config ${BASE_DIR}/local/kind.yaml \
		--name ${KIND_CLUSTER_NAME}
.PHONY: kind-create-cluster

kind-delete-cluster:
	@	kind delete cluster --name ${KIND_CLUSTER_NAME}
.PHONY: kind-delete-cluster