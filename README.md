# cnpg-phoenix-demo

A minimal Phoenix LiveView app purpose-built to demo [CloudNativePG](https://cloudnative-pg.io/)
(CNPG) wiring in Kubernetes. It stores notes in a Postgres database and shows the
cluster wiring on its home page: Postgres server version, connected database and
user, plus the pod and node it runs on.

Built for the [kina](https://github.com/vinnie357/kina) CNPG examples
(`kina-cli/examples/demos/cnpg-app/`), but it works against any Postgres.

![Dashboard: topology across an HA CNPG cluster and a second analytics cluster, with live-updating visits and notes](docs/screenshot.png)

## Image

Multi-arch (`linux/amd64`, `linux/arm64`) images are published on version tags:

```
ghcr.io/vinnie357/cnpg-phoenix-demo:<tag>
```

## Configuration (environment variables)

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | yes | Postgres connection URL for writes (`postgresql://user:pass@host:port/db`). The CNPG `<cluster>-app` secret's `uri` key works directly. |
| `DATABASE_RO_URL` | no | Read-only pool URL — point it at the CNPG `-ro` service on an HA cluster. Falls back to `DATABASE_URL` when unset. |
| `ANALYTICS_DATABASE_URL` | no | Second CNPG cluster for page-visit events. Unset ⇒ the analytics repo isn't started and its UI sections hide. |
| `SECRET_KEY_BASE` | yes | Phoenix secret; generate with `openssl rand -base64 48`. |
| `PHX_HOST` | yes | Public hostname the app is served on (also used for LiveView origin checks). |
| `PORT` | no | HTTP listen port (default `4000`). |
| `NODE_NAME` | no | Kubernetes node name, typically injected via the downward API (`spec.nodeName`). Display-only. |
| `POOL_SIZE` | no | Ecto pool size **per repo** (default `5`; up to three pools run). |

The home page shows the topology (which CNPG instance each pool landed on,
`pg_is_in_recovery`, streaming standbys via `pg_stat_replication` — grant
`pg_monitor` to the app user for standby details), a read-only table browser
per database, and page-visit counts from the analytics cluster.

The release runs Ecto migrations automatically on boot; until the database is
reachable the pod exits and is restarted by Kubernetes.

## Local development

Requires Erlang/Elixir (see `mise.toml`) and a local Postgres with
`postgres`/`postgres` credentials.

```sh
mise run setup
mix ecto.create
mix phx.server
```

Run the quality gate (format check, warnings-as-errors compile, tests):

```sh
mise run ci
```

## License

MIT — see [LICENSE](LICENSE).
