# Regenerate the Capsule kustomize bundle from the upstream Helm chart.
#
# Invoked via `mise run capsule:template`. Produces deterministic output:
# - resources/capsule-from-helm.yaml  (helm template result, with a provenance header)
# - crds/*.yaml                       (copied verbatim from the chart tarball)
#
# SECURITY: chart version MUST be pinned (no `latest`, no floating tag).
# Bump CHART_VERSION and re-run to upgrade.

CHART_VERSION ?= 0.12.4
CHART_REPO     = https://projectcapsule.github.io/charts
CHART_NAME     = capsule
RELEASE_NAME   = capsule
NAMESPACE      = capsule-system

.PHONY: template clean

template: clean
	@echo "==> helm repo add + update"
	helm repo add projectcapsule $(CHART_REPO) >/dev/null 2>&1 || true
	helm repo update projectcapsule >/dev/null

	@echo "==> helm pull $(CHART_NAME) v$(CHART_VERSION)"
	helm pull projectcapsule/$(CHART_NAME) --version $(CHART_VERSION) --untar --untardir .

	@echo "==> copy CRDs"
	mkdir -p crds
	cp -p $(CHART_NAME)/crds/*.yaml crds/

	@echo "==> helm template > resources/capsule-from-helm.yaml"
	mkdir -p resources
	printf '# GENERATED — do not edit by hand.\n# Chart: projectcapsule/%s @ v%s\n# Regen: mise run capsule:template\n# Timestamp: %s\n---\n' \
	  "$(CHART_NAME)" "$(CHART_VERSION)" "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > resources/capsule-from-helm.yaml.tmp
	helm template $(RELEASE_NAME) projectcapsule/$(CHART_NAME) \
	  --version $(CHART_VERSION) \
	  --namespace $(NAMESPACE) \
	  --include-crds=false \
	  --values values.yaml >> resources/capsule-from-helm.yaml.tmp
	mv resources/capsule-from-helm.yaml.tmp resources/capsule-from-helm.yaml

	@echo "==> cleanup pulled chart"
	rm -rf $(CHART_NAME)

	@echo "==> done. review diff before committing."

clean:
	rm -rf $(CHART_NAME)
	rm -f resources/capsule-from-helm.yaml.tmp
