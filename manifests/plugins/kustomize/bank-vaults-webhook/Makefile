# Bank-Vaults webhook kustomize bundle generator.
# Renders the vault-secrets-webhook Helm chart into a kustomize-buildable folder.
#
# Usage:
#   make template          # pull + render
#   make clean             # remove rendered output
#
# Chart: oci://ghcr.io/bank-vaults/helm-charts/vault-secrets-webhook
# Regenerate via: mise run bank-vaults:template

CHART_NAME    ?= vault-secrets-webhook
CHART_VERSION ?= 1.22.2
CHART_OCI     := oci://ghcr.io/bank-vaults/helm-charts/$(CHART_NAME)
RELEASE_NAME  ?= vault-secrets-webhook
NAMESPACE     ?= bank-vaults-system

.PHONY: template clean

template: clean
	@echo "==> pulling chart $(CHART_NAME) v$(CHART_VERSION) (OCI)"
	helm pull $(CHART_OCI) --version $(CHART_VERSION) --untar --untardir .
	@echo "==> rendering chart"
	@printf '# GENERATED — do not edit manually.\n# Chart: %s @ v%s\n# Regen: mise run bank-vaults:template\n# Timestamp: %s\n---\n' \
	  "$(CHART_NAME)" "$(CHART_VERSION)" "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > resources/$(CHART_NAME)-from-helm.yaml.tmp
	helm template $(RELEASE_NAME) ./$(CHART_NAME) \
	  --version $(CHART_VERSION) \
	  --namespace $(NAMESPACE) \
	  --include-crds=false \
	  --values values.yaml >> resources/$(CHART_NAME)-from-helm.yaml.tmp
	mv resources/$(CHART_NAME)-from-helm.yaml.tmp resources/$(CHART_NAME)-from-helm.yaml
	@echo "==> cleanup pulled chart"
	rm -rf $(CHART_NAME)
	@echo "==> done. review diff before committing."

clean:
	@rm -rf $(CHART_NAME)
	@rm -f resources/$(CHART_NAME)-from-helm.yaml.tmp
