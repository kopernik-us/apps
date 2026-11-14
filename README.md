# Apps

The applications the console offers to deploy, one directory per app, named after the app's template `uid`:

```
apps/<uid>/
  template.json     the app template: what the console offers, and how its containers run
  <version>/        one per template version whose image is ours, named as the template names the version
    Dockerfile      the image of that version, when the upstream image cannot run it as the template describes
    ...             whatever the image copies in, beside its Dockerfile
```

A directory is the single place an app is defined. The template names things its image provides — the
image's own ref, the scripts a container runs, the directories it prepares for data — so the two are kept
together and changed in one commit, and `AppDirectoryTest` fails the build when they disagree.

The api-server bundles every `apps/*/template.json` into its resources as `app-templates/<uid>.json` and
generates `app-templates/index` from the directories found (`generateAppTemplates` in
`api-server/build.gradle.kts`), so an app is added by adding its directory and nothing else. The server refuses
a template whose `uid` is not the name of its directory.

## One directory per version

Each version's image is built from a directory of its own, which states everything about it, the base image's
tag included: `FROM mysql:8.4.13`, not a `VERSION` argument the build is handed. So a version's directory is all
that goes into its image, and a change made for one version, say an option a newer server renamed, reaches no other
until it is made there too. The cost is that files every version shares, such as MySQL's entry point, are copied
into each; a change meant for all of them is made in all of them, which a diff of one directory against another
shows.

A version is added by copying the directory of the nearest one, changing its `FROM` and whatever else differs,
adding the version to the end of `template.json`'s `versions`, which the console and the API take as the latest,
and publishing it. A version is retired by removing both, in one commit.
`AppDirectoryTest` fails a version naming an image of ours without a directory to build it from, a directory of a
version the template no longer declares, and a file beside `template.json`, since none of those is an image anything
publishes.

What a version cannot differ in is its template. A version states its own image, `architectures`,
`machineRequirements`, license and product link, but containers, environment, ports and data paths belong to the
template, so versions whose application is configured differently, rather than built differently, are separate apps
under separate uids.

## When an app gets an image of its own

A template whose application reads its environment points at the upstream image and has no Dockerfile:
PostgreSQL, Valkey and OpenSearch, today. An app gets an image here when that is not enough:

- **The application cannot be configured by environment alone.** Hadoop is the case that started this
  directory: `fs.defaultFS` and `yarn.resourcemanager.hostname` are written into XML files rather than read
  from the environment, so something on the machine has to turn the variables the API injects into
  configuration before the daemon starts.
- **The application does not size itself to its machine.** An upstream image starts with the defaults its
  publisher chose for a laptop — MySQL's 128 MB InnoDB buffer pool, PostgreSQL's 128 MB `shared_buffers` —
  however large the machine the customer pays for, so most of it goes unused. An entry point which reads
  `K_US_CONTAINER_MEMORY_MB` and `K_US_CONTAINER_CPUS` (see below) can size the application to the share it
  was given, and does so again on every start, which a template cannot: its environment is fixed when the app
  is created.

Moving an app from the upstream image to one of ours is a change to its directory alone: add a directory with a
Dockerfile for each version, point those versions at `ghcr.io/kopernik-us/<uid>:<version>`, and publish. A
template may keep upstream images for some versions and ours for others.

## These are not the images of `scripts/build.sh`

| | Component image | Application image |
|---|---|---|
| What it is | api-server, webapp | the application a customer's app runs |
| Built | every release | when the application's version changes |
| Tagged | the kopernik commit | the application's own version |
| Pushed to | `REGISTRY`, the registry inside the cluster | `ghcr.io/kopernik-us/<uid>`, public |
| Pulled by | the k3s cluster | a customer's machine, over the open internet |
| Platforms | `linux/amd64` | `linux/amd64` and `linux/arm64` |

`REGISTRY` and `KUBE_CONTEXT` therefore do not apply to anything in this directory, and an application
image is never added to `COMPONENTS`: it would be tagged with a kopernik commit and pushed to a registry on
the home network, which no customer machine can reach.

## Publishing

```bash
apps/publish.sh hadoop                  # the template's latest version, which it lists last
apps/publish.sh hadoop 3.4.1            # a particular version the template declares
apps/publish.sh mysql 8.4.13 9.7.4      # several, from the one commit, pinning each
```

The script takes the image ref from the template rather than from an argument, because
`ContainerAppServer.applyTemplate` rejects a create request whose image does not match a template version
exactly. `AppDirectoryTest` holds that ref to `ghcr.io/kopernik-us/<uid>:<version>`. The build context is
`apps/<uid>/<version>/`, and the build is given no arguments: what the image is, its directory says.

Publishing requires a clean working tree. The tag names an application version rather than a tree, so a
rebuilt tag cannot be told apart from the one customers already pulled.

The script then pins the digest it pushed in the template, as `versions[].image.digest`, and leaves the change
for you to commit. The server checks that digest against the request, so pinning makes a customer's pull
immutable rather than whatever the tag points at that week; a template naming an image of ours without one
fails `AppTemplateRegistryTest`.

The platforms are the template's too. Each version of an app with an image of ours states `architectures`, named as
machine types name them (`x86_64`, `arm64`), and the script builds for exactly those, as `linux/amd64` and
`linux/arm64`. The console offers only machine types of a version's architectures, so an image built for fewer than
its template states fails on machines the console let through, and `AppDirectoryTest` fails a version of ours which
states none. A Dockerfile which runs nothing, setting modes with `COPY --chmod` rather than `RUN chmod`, builds for
every platform on any machine; one with a `RUN` step needs an emulator for the platforms other than the machine's
own, which `docker run --privileged --rm tonistiigi/binfmt --install arm64` registers.

## The registry

`ghcr.io/kopernik-us/<uid>`, which needs no creating: the package exists after the first push.

**A new package is private, and a private one is unusable.** A customer's machine pulls the image itself
over cloud-init, so the only way it could authenticate is
`containerAppCreate.containerImageRepositoryCredentials` — which would mean shipping a kopernik token to
every customer machine. After the first push, set the package public:

> Package → Package settings → Danger Zone → Change visibility → Public

Public GHCR pulls are anonymous, which also avoids the Docker Hub rate limit an unauthenticated machine
would otherwise meet. An organization can forbid public packages altogether, under `kopernik-us` → Settings
→ Packages → Package creation, which is worth checking before the first push rather than after.

## `hadoop`

`FROM apache/hadoop:3.5.0`, the Apache Software Foundation's own convenience build, with an entry point that
composes the values the upstream image cannot take from the environment and then hands over to
`/opt/starter.sh` unchanged. The upstream image converts variables named `<FILE>.<EXT>_<property>` into
Hadoop configuration, so `CORE-SITE.XML_fs.defaultFS` is a value it would write — but not one a template
could state, because it holds the name of the cluster's first master, and the environment file reaches Docker
unexpanded. The entry point composes it on the machine, where `K_US_MASTER_HOSTS` has a value, and sets
nothing the cluster set for itself, so any of it can be overridden through `runtimeProps.env`.

`format-hdfs.sh` is the template's init container. A step leads the service containers of its node, so the
namenode starts on a filesystem which exists. The step states the namenode's data path, `/data/namenode`, as its
own, which is what gives the two one directory: each data path is kept in a volume of the node which every
container of the role stating it shares, and a format kept anywhere else is one the namenode never finds. The size
stays on the namenode, which keeps the data. The script skips a directory which holds a filesystem already,
because the directory outlives the containers which use it, and formatting it again would discard the metadata of
every file in HDFS.

**`apache/hadoop:3.5.0` is published for amd64 only**, so this image is too, which its template states as
`"architectures": ["x86_64"]`. The console offers no arm64 machine type, such as AWS Graviton, for it, and the API
refuses a request naming one. Publishing for arm64 would mean building Hadoop from the `aarch64` binary the Apache
download page offers rather than deriving from the official image, which is a larger thing to own: the JDK, the
layout and the user setup would become ours.

## `mysql`

`FROM mysql:<version>`, the official image, in `9.7.4/` and `8.4.13/`, with an entry point that sizes the InnoDB buffer pool to the container's
memory share before handing over to the upstream `docker-entrypoint.sh` unchanged. Upstream starts every server with
a 128 MB pool, however large the machine, so a database on an 8 GB machine kept most of what it reads on disk. The
entry point follows InnoDB's own `innodb_dedicated_server` rule, from `K_US_CONTAINER_MEMORY_MB` rather than from the
memory the server detects, which inside a container may be the whole machine:

| Container memory | Buffer pool |
|---|---|
| under 1 GB | 128 MB, the upstream default |
| 1 GB to 4 GB | half |
| over 4 GB | three quarters |

MySQL rounds the size up to a multiple of its chunk size, so the pool it reports may be a little larger. A size the
app states itself, `--innodb-buffer-pool-size` or `--innodb_buffer_pool_size` in its arguments, is never
overridden, and nothing is sized when the image runs outside kopernik.us, where the variable is not set. Only the
server is sized: the image run as a client or a shell is left alone.

The data directory, `/var/lib/mysql`, is the upstream image's to prepare: its entry point gives it to the `mysql`
user on every start.

**Owning the image means owning its patches.** The upstream tag `mysql:9` moves to each patched build, so an app
pointing at it got fixes without a release of ours. A version of ours names an exact release, 9.7.4 or 8.4.13, pinned
by digest, and a MySQL security release reaches customers only when a new version is added to the template and
published.

## Writing one

The build context is the version's own directory, unlike the component Dockerfiles, which take the repo root
because they build from the source tree. An application image needs nothing else from this repository, so
everything it uses sits beside its Dockerfile.

An entrypoint configures the application from what the API injects:

| Variable | What it says |
|---|---|
| `K_US_CONTAINER_MEMORY_MB`, `K_US_CONTAINER_CPUS` | the container's own share of the machine |
| `K_US_MACHINE_MEMORY_MB`, `K_US_MACHINE_CPUS` | the whole machine, for a container sizing itself against it |
| `K_US_CLUSTER_ROLE`, `K_US_NODE_INDEX` | which node of the cluster this is |
| `K_US_CLUSTER_UID`, `K_US_MASTER_NODE_COUNT`, `K_US_CORE_NODE_COUNT` | the cluster the node belongs to and its shape |
| `K_US_MASTER_HOSTS` | every master node by name, comma separated, for the configuration that needs one |

They are read on the machine when the app starts rather than taken from the machine type at provisioning,
so a resized machine is configured for its new size on the next start. The names are reserved: a template
container which sets one is refused as the server loads the template. See
[cluster apps](../webapp/docs/api-docs/clusterapp.md) for the full list and what each node is told.
