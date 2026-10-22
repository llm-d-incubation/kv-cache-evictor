# Filesystem evictor deployment

The filesystem evictor can run in two modes:

- **Standalone:** a separate evictor Deployment mounts the cache PVC.
- **Sidecar:** the evictor container runs in the same Pod as vLLM.

Kustomize provides the standalone Deployment. Helm provides standalone mode
and a sidecar container template.

Neither method creates the PVC. You must provide the PVC and the cache
volume. Run one evictor for each shared cache because the evictor has no
leader election.

## Kustomize

### Standalone

#### You provide

- an existing PVC containing the cache
- the namespace for the cache workload

#### This repository provides

- an evictor Deployment
- a ConfigMap with the evictor environment variables
- the evictor image

#### You do

1. Open `filesystem/deploy/kustomize/standalone/kustomization.yaml`.

   Find these lines and replace the values on the right:

   ```text
   namespace: llm-d-cache  ->  namespace: team-a
   value: kv-cache-pvc     ->  value: vllm-cache
   newTag: main            ->  newTag: v1.0.0
   ```

   Use the namespace where the PVC exists. Use the exact PVC name from
   `metadata.name`. The `value` line is the JSON patch that changes the PVC
   name in the generated evictor Deployment; you do not need to edit
   `deployment.yaml` for this change.

   The image is then:

   ```text
   ghcr.io/llm-d-incubation/kv-cache-evictor:v1.0.0
   ```

   `main` follows the latest main image and is mutable. Use a release or
   commit tag for a fixed image.

2. Edit `filesystem/deploy/kustomize/standalone/configmap.env`:

   - set `CACHE_DIRECTORY` to the cache directory on the PVC;
   - set `CLEANUP_THRESHOLD` and `TARGET_THRESHOLD`;
   - change other evictor settings if needed.

3. Preview the resources from the repository root:

   ```sh
   kubectl kustomize filesystem/deploy/kustomize/standalone
   ```

4. Apply them:

   ```sh
   kubectl apply -k filesystem/deploy/kustomize/standalone
   ```

5. Remove the evictor Deployment when needed:

   ```sh
   kubectl delete -k filesystem/deploy/kustomize/standalone
   ```

The standalone Kustomize files do not create or delete the PVC.

### Sidecar

Deploy the PVC evictor as a sidecar in your vLLM Deployment. The sidecar must
mount the same cache PVC as vLLM and use the environment variables documented
in [filesystem/README.md](../README.md).

This repository does not provide a Kustomize sidecar overlay.

## Helm

### Standalone

#### You provide

- an existing namespace;
- an existing PVC containing the cache.

#### This repository provides

- an evictor Deployment;
- a ConfigMap with the evictor environment variables;
- the evictor image.

#### You do

Install the chart and set the PVC name:

```sh
helm install kv-cache-evictor filesystem/deploy/helm \
  --namespace llm-d-cache \
  --create-namespace \
  --set standalone.existingClaim=kv-cache-pvc
```

Set the image tag and evictor settings with `helm/values.yaml` or `--set`.
Keep `standalone.replicaCount` at `1`.

Uninstall the evictor with:

```sh
helm uninstall kv-cache-evictor --namespace llm-d-cache
```

The Helm chart does not create or delete the PVC.

### Sidecar

#### You provide

- the vLLM Pod or chart;
- an existing PVC and cache volume mounted by that Pod;
- a way to add the evictor container to the vLLM Pod.

#### This repository provides

- a ConfigMap with the evictor environment variables;
- a reusable Helm container template;
- the evictor image and default security settings.

The chart does not modify a vLLM Deployment owned by another chart.

#### You do

Install the chart in sidecar mode:

```sh
helm install kv-cache-evictor filesystem/deploy/helm \
  --namespace llm-d-cache \
  --create-namespace \
  --set mode=sidecar \
  --set sidecar.volumeName=cache-storage
```

Then add the container printed in the install notes to the vLLM Pod. It must
be under `containers`, not `initContainers`:

```yaml
- name: filesystem-evictor
  image: ghcr.io/llm-d-incubation/kv-cache-evictor:main
  imagePullPolicy: Always
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    runAsNonRoot: true
  envFrom:
    - configMapRef:
        name: kv-cache-evictor-settings
  volumeMounts:
    - name: cache-storage
      mountPath: /kv-cache
```

If your vLLM chart includes this chart as a dependency, use the dependency
context when rendering the container:

```gotemplate
{{- $evictor := index .Subcharts "kv-cache-evictor" -}}
{{ include "kv-cache-evictor.sidecarContainer" $evictor | nindent 2 }}
```

Use the dependency alias instead of `kv-cache-evictor` if you set an alias.

Add the checksum to the vLLM Pod template so a Helm upgrade restarts the
sidecar when its settings change:

```gotemplate
{{- $evictor := index .Subcharts "kv-cache-evictor" -}}
annotations:
  checksum/kv-cache-evictor: {{ include "kv-cache-evictor.configChecksum" $evictor }}
```

## Scheduling and permissions

In sidecar mode, the evictor always runs on the same node as vLLM because it
is in the same Pod.

In standalone mode, the PVC access mode controls scheduling:

- `ReadWriteMany`: the evictor can run on any node that can mount the volume;
- `ReadWriteOnce`: if the vLLM Pod already mounts the PVC, the evictor must
  run on the same node;
- `ReadWriteOncePod`: not supported for standalone mode because only one Pod
  can mount the volume;
- `ReadOnlyMany`: not supported because the evictor must delete files.

The evictor container must have Unix permission to delete files in the cache.
If the volume requires a specific user or group, set those fields on the Pod
that owns the cache mount.

## Storage events

`STORAGE_EVENTS_ENDPOINT` works in both modes.

In standalone Helm mode, you can create a Service for the event endpoint. Set
a matching TCP endpoint and Service port:

```sh
--set events.endpoint='tcp://*:5570' \
--set events.service.enabled=true \
--set events.service.port=5570
```

In sidecar mode, expose the event port through the vLLM Pod and its Service.
