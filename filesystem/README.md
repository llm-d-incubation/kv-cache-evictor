# Filesystem KV-cache evictor

This backend is a Linux Go service. It watches a cache on a mounted filesystem, removes cold `.bin` blocks when the filesystem reaches a high-water mark, and stops when usage falls below a low-water mark. It can also remove empty cache directories and publish `BlockRemoved` events over ZMQ.

The service does not create or mount a PersistentVolumeClaim. The workload must provide the mount and cache root; the service waits for them to appear.

## Current scope

This implementation is customized for vLLM's filesystem cache layout,
metadata, and storage-event contract. SGLang, Mooncake, and other cache
formats are not supported yet; add their layout and event rules as separate
backend or adapter work.

## Code layout

```text
filesystem/
├── cmd/
│   └── pvc-evictor/       Service entry point
├── deploy/                Kustomize and Helm deployment flavors
└── internal/
    ├── cleaner/           Empty-directory cleanup
    ├── config/            Flags, environment variables, and validation
    ├── crawler/           Cache scanning and queueing
    ├── deleter/           File deletion and optional event publishing
    ├── disk/              Linux filesystem usage
    ├── events/            ZMQ storage-event publishing
    ├── filemeta/          File and directory metadata
    └── pending/           Paths waiting for deletion
```

## Cache layout

The scanner handles these cache shapes:

```text
<cache-root>/<model>_r<rank>/<hex-bucket>/<block-bucket>/*.bin
<cache-root>/<model>/<rank>/<dtype>/<hex-bucket>/<block-bucket>/*.bin
```

The first hex bucket is assigned to crawler workers by its value modulo 16.
`HEX_BUCKET_LEN` must match the first-bucket name length used by the cache and must be between 2 and 4.
The default is 3.

Files whose access time is newer than `FILE_ACCESS_TIME_THRESHOLD_MINUTES` are protected from deletion.

## Run locally

Run these commands from the repository root:

```sh
make build
./filesystem/bin/pvc-evictor
```

The default mount path is `/kv-cache`, and the default cache root is `/kv-cache/kv/model-cache/models`. Override settings with command-line flags or environment variables. Environment variables take precedence over flags.

For example:

```sh
PVC_MOUNT_PATH=/mnt/kv-cache \
CACHE_DIRECTORY=models \
CLEANUP_THRESHOLD=85 \
TARGET_THRESHOLD=70 \
./filesystem/bin/pvc-evictor
```

The service waits up to 60 seconds for the mount path and up to 5 minutes for the cache root.
It exits if either path does not appear.

## Settings

| Environment variable | Flag | Default | Purpose |
| --- | --- | ---: | --- |
| `PVC_MOUNT_PATH` | `--pvc-mount-path` | `/kv-cache` | Mounted filesystem path |
| `CACHE_DIRECTORY` | `--cache-directory` | `kv/model-cache/models` | Relative cache path below the mount |
| `CLEANUP_THRESHOLD` | `--cleanup-threshold` | `85` | Usage percentage that starts deletion |
| `TARGET_THRESHOLD` | `--target-threshold` | `70` | Usage percentage that stops deletion |
| `DRY_RUN` | `--dry-run` | `false` | Keep files and log deletion batches |
| `LOG_LEVEL` | `--log-level` | `INFO` | `DEBUG`, `INFO`, `WARNING`, or `ERROR` |
| `NUM_CRAWLER_PROCESSES` | `--num-crawler-processes` | `8` | Crawler workers; must be a power of two from 1 to 16 |
| `LOGGER_INTERVAL_SECONDS` | `--logger-interval-seconds` | `0.5` | Filesystem usage check interval |
| `FILE_QUEUE_MAXSIZE` | `--file-queue-max-size` | `10000` | Maximum queued file paths |
| `FILE_QUEUE_MIN_SIZE` | `--file-queue-min-size` | `1000` | Queue depth maintained while deletion is off |
| `DELETION_BATCH_SIZE` | `--deletion-batch-size` | `100` | Files handled per deletion batch |
| `DELETION_MAX_FILES_PER_SECOND` | `--deletion-max-files-per-second` | `0` | Deletion rate; zero means unlimited |
| `FILE_ACCESS_TIME_THRESHOLD_MINUTES` | `--file-access-time-threshold-minutes` | `60` | Minimum file age before deletion |
| `HEX_BUCKET_LEN` | `--hex-bucket-len` | `3` | First hex-bucket name length |
| `ENABLE_DIR_CLEANUP` | `--enable-dir-cleanup` | `true` | Remove empty cache directories |
| `DIR_CLEANUP_TTL_SECONDS` | `--dir-cleanup-ttl-seconds` | `120` | Quiet period before directory cleanup |
| `LOG_FILE_PATH` | `--log-file-path` | empty | Additional append-only log file |
| `STORAGE_EVENTS_ENDPOINT` | `--storage-events-endpoint` | empty | ZMQ endpoint for `BlockRemoved` events |

`TARGET_THRESHOLD` must be lower than `CLEANUP_THRESHOLD`. The cache directory must be a relative path below `PVC_MOUNT_PATH`.

## Storage events

When `STORAGE_EVENTS_ENDPOINT` is set, the service opens a ZMQ PUB socket and publishes events after successful deletions.
The topic is `kv@SHARED_STORAGE@<model-name>`. The model name is read from the model's `config.json` file.
If that metadata cannot be read after retries, the service continues deleting files but disables event publishing.

## Development

Run the complete local validation set from the repository root:

```sh
make verify
```

Individual targets are also available:

```sh
make fmt-check  # Check gofmt output
make test       # Run Go tests
make lint       # Run the pinned golangci-lint version
make build      # Build filesystem/bin/pvc-evictor
make image      # Build the container image
make chart-lint # Lint the Helm chart
make chart-render # Render the Helm chart
make kustomize-render # Render standalone Kustomize manifests
```

`make lint` downloads the pinned `golangci-lint` module when it is not already in the Go module cache.
`make image` uses Podman by default; set `CONTAINER_ENGINE=docker` to use Docker.

## Deployment

Kustomize provides the standalone Deployment. Helm provides standalone mode
and a sidecar container template for vLLM.

- Standalone mode runs one evictor Pod against an existing PVC.
- Sidecar mode runs the evictor container in the same Pod as vLLM.
- You must create the PVC before installing; neither method creates it.

See [deploy/README.md](deploy/README.md) for mode, settings, and install
commands.
