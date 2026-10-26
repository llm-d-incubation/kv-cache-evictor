# Filesystem evictor deployment

The filesystem evictor can run in two modes:

- **Standalone:** a separate evictor Deployment mounts the cache PVC.
- **Sidecar:** the evictor container runs in the same Pod as vLLM.

Kustomize provides the standalone Deployment. Helm provides standalone mode
and a sidecar container template.

Neither method creates the PVC. You must provide the PVC and the cache
volume. Run one evictor for each shared cache because the evictor has no
leader election.

The evictor and vLLM must resolve to the same cache directory.

For example, if vLLM mounts the PVC at `/mnt/files-storage` and the evictor mounts the same PVC at `/kv-cache`, use:

- vLLM `root_dir`: `/mnt/files-storage/kv/model-cache/models`
- evictor `PVC_MOUNT_PATH`: `/kv-cache`
- evictor `CACHE_DIRECTORY`: `kv/model-cache/models`

`root_dir` is a field in vLLM’s `kv-transfer-config`. `PVC_MOUNT_PATH` and
`CACHE_DIRECTORY` are environment variables read by the evictor.

`CLEANUP_THRESHOLD` and `TARGET_THRESHOLD` are percentages of the mounted filesystem’s usable capacity, not of `PVC.spec.resources.requests.storage`.

## Kustomize

### Standalone

#### You provide

- an existing PVC containing the cache
- the namespace for the cache workload

#### This repository provides

- an evictor Deployment
- a ConfigMap with the evictor environment variables
- the evictor image

1. Open `filesystem/deploy/kustomize/standalone/kustomization.yaml`.

   Set these values in the file:

   - `namespace: <your-namespace>` — the namespace containing your PVC;
   - `value: <your-pvc-name>` — the name of your existing PVC;
   - `newTag: <your-image-tag>` — the tag of the evictor image to run.

   Use the namespace where the PVC exists. Use the exact PVC name from
   `metadata.name`. The `value` line is the JSON patch that changes the PVC
   name in the generated evictor Deployment; you do not need to edit
   `deployment.yaml` for this change.

   `newTag` is the image tag after the colon. `main` uses the latest main
   image and is mutable. Use a release or commit tag only when that tag exists
   in the image registry.

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

To publish storage events, set `STORAGE_EVENTS_ENDPOINT` in
`filesystem/deploy/kustomize/standalone/configmap.env`. Kustomize does not
create a Service for this endpoint.

### Sidecar

Add the PVC evictor container and its environment values to your vLLM
Deployment. It must mount the same cache PVC as vLLM. Use the environment
variables documented in [Filesystem settings](../README.md#settings).

Add this container under `spec.template.spec.containers`:

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
  env:
    - name: PVC_MOUNT_PATH
      value: /kv-cache
    - name: CACHE_DIRECTORY
      value: kv/model-cache/models
    - name: CLEANUP_THRESHOLD
      value: "85.0"
    - name: TARGET_THRESHOLD
      value: "70.0"
  volumeMounts:
    - name: cache-storage
      mountPath: /kv-cache
```

Change the image tag, cache directory, thresholds, and volume name to match
your vLLM Deployment.

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

Install the chart and set the PVC name:

```sh
helm install kv-cache-evictor filesystem/deploy/helm \
  --create-namespace \
  --namespace llm-d-cache \
  --set mode=standalone \
  --set standalone.existingClaim=kv-cache-pvc
```

Set the image tag and evictor settings with `helm/values.yaml` or `--set`.
Keep `standalone.replicaCount` at `1`.

Uninstall the evictor with:

```sh
helm uninstall kv-cache-evictor --namespace llm-d-cache
```

The Helm chart does not create or delete the PVC.

To publish storage events, add these flags to the install command:

```sh
--set-string events.endpoint='tcp://*:5570' \
--set events.service.enabled=true \
--set events.service.port=5570
```

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

Install the chart in sidecar mode:

```sh
helm install kv-cache-evictor filesystem/deploy/helm \
  --create-namespace \
  --namespace llm-d-cache \
  --set mode=sidecar \
  --set sidecar.volumeName=cache-storage
```

Then add the container printed in the install notes under `containers` in the
vLLM Pod:

The following example is for Helm sidecar mode. Helm creates the
`kv-cache-evictor-settings` ConfigMap used by `envFrom`.

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

Helm updates the ConfigMap, but it does not restart or reconcile a vLLM Deployment owned by another chart.
Add the checksum annotation to the parent Pod template so a Helm upgrade restarts the Pod when the ConfigMap changes.

```gotemplate
{{- $evictor := index .Subcharts "kv-cache-evictor" -}}
annotations:
  checksum/kv-cache-evictor: {{ include "kv-cache-evictor.configChecksum" $evictor }}
```

To publish storage events in sidecar mode, set `events.endpoint` when you
install the chart and expose port `5570` through the vLLM Pod and Service.
The Helm chart does not create the Service in sidecar mode.

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
