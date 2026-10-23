## Governance

`kv-cache-evictor` follows the llm-d contributor and maintainer model:

- **Contributors** open issues and submit pull requests.
- **Core maintainers** own the repository, review changes, and set direction.
- **A lead core maintainer** resolves decisions when core maintainers cannot reach consensus.

The current maintainers are listed in [OWNERS](OWNERS).

## Submitting a pull request

1. Open an issue for bugs and significant design changes.
2. Keep the change focused and add or update tests for behavior changes.
3. Follow the existing Go style and repository layout.
4. Run `make verify` from the repository root.
5. Sign your commits.

## Development

The filesystem backend lives under `filesystem/`. Use these targets from the repository root:

```sh
make fmt-check
make test
make lint
make build
make verify
```

Set `CONTAINER_ENGINE=docker` if you prefer Docker over the default Podman for `make image`.

## License

Contributions are licensed under the repository [Apache 2.0 license](LICENSE).
