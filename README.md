# llm-d KV-cache evictor

This repository contains KV-cache eviction backends for the `llm-d-incubation` project.

The current filesystem backend is customized for vLLM's cache layout and metadata.
Support for SGLang, Mooncake, and other cache formats can be added later without changing the repository-level structure.

## Backends

- [Filesystem](filesystem/): Linux service for caches on mounted filesystems, including PVCs and local SSDs.

Future backends should have their own directory and README.

## Development

Run the common validation set from the repository root:

```sh
make verify
```

Build the container image with:

```sh
make image
```

See [filesystem/README.md](filesystem/README.md) for backend-specific usage, settings, cache layouts, and storage events.
