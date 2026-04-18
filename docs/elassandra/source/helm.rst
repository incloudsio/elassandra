
Helm chart
==========

The maintained Elassandra Helm chart now lives in the dedicated
``incloudsio/helm-charts`` repository under ``charts/elassandra``.
The chart models one Elassandra JVM per StatefulSet pod, exposes separate CQL and
search services, and optionally deploys OpenSearch Dashboards.

Install with default values
...........................

Clone the chart repository and install from the chart directory::

  git clone https://github.com/incloudsio/helm-charts.git
  helm install elassandra ./helm-charts/charts/elassandra

This default path is intentionally conservative:

- one Elassandra pod by default
- persistent storage enabled
- separate headless, CQL, and search services
- OpenSearch Dashboards disabled by default

Install on minikube
...................

Build the local image first from the Elassandra source repository::

  ./gradlew :distribution:docker:buildDockerImage
  minikube image load elassandra:test

Then install the minikube profile::

  helm install elassandra ./helm-charts/charts/elassandra \
    -f ./helm-charts/charts/elassandra/values-minikube.yaml

The ``values-minikube.yaml`` preset keeps the deployment to a single Elassandra pod and
switches the CQL and search services to ``NodePort`` for easier local access.

Enable OpenSearch Dashboards
............................

Dashboards stays optional so that local and test installs can remain lightweight.
Enable it at install time with either inline values or your own overlay file::

  helm install elassandra ./helm-charts/charts/elassandra \
    -f ./helm-charts/charts/elassandra/values-minikube.yaml \
    --set dashboards.enabled=true

Provider presets
................

The chart includes shallow provider-specific values files:

- ``helm-charts/charts/elassandra/values-aws.yaml``
- ``helm-charts/charts/elassandra/values-gcp.yaml``
- ``helm-charts/charts/elassandra/values-azure.yaml``
- ``helm-charts/charts/elassandra/values-minikube.yaml``

These presets intentionally focus on install-time defaults such as replica count,
heap sizing, anti-affinity, and storage class names. They do **not** yet automate
provider identity integrations such as IRSA, GKE Workload Identity, or Azure managed identity.

Example::

  helm install elassandra ./helm-charts/charts/elassandra \
    -f ./helm-charts/charts/elassandra/values-aws.yaml

AKS / ACR example
.................

The Azure preset references ``elassandra.azurecr.io/elassandra:1.3.20``.

If your AKS cluster is attached to the ACR::

  az aks update \
    --resource-group <resource-group> \
    --name <aks-cluster> \
    --attach-acr elassandra

  helm upgrade --install elassandra ./helm-charts/charts/elassandra \
    --namespace elassandra \
    --create-namespace \
    -f ./helm-charts/charts/elassandra/values-azure.yaml

If the cluster is not attached to the ACR, create an image pull secret and pass it to the chart::

  kubectl create namespace elassandra

  kubectl create secret docker-registry elassandra-acr \
    --namespace elassandra \
    --docker-server=elassandra.azurecr.io \
    --docker-username=<acr-username> \
    --docker-password=<acr-password>

  helm upgrade --install elassandra ./helm-charts/charts/elassandra \
    --namespace elassandra \
    -f ./helm-charts/charts/elassandra/values-azure.yaml \
    --set imagePullSecrets[0].name=elassandra-acr

Rendered resources
..................

The chart creates:

- a StatefulSet for Elassandra
- a headless service for peer discovery
- a CQL/JMX service
- an HTTP search service
- optional OpenSearch Dashboards deployment and service

Validate before installing
..........................

Typical validation commands::

  helm lint ./helm-charts/charts/elassandra
  helm template elassandra ./helm-charts/charts/elassandra \
    -f ./helm-charts/charts/elassandra/values-minikube.yaml
