# Apps

The applications the console offers to deploy, one directory per app, named after the app's template `uid`:

```
apps/<uid>/
  template.json     the app template: what the console offers, and how its containers run
  Dockerfile        the image of the app, when the upstream image cannot run it as the template describes
  ...               whatever the image copies in, beside its Dockerfile
```

A directory is the single place an app is defined. The template names things its image provides — the
image's own ref, the scripts a container runs, the directories it prepares for data — so the two are kept
together and changed in one commit, and `AppDirectoryTest` fails the build when they disagree.

The api-server bundles every `apps/*/template.json` into its resources as `app-templates/<uid>.json` and
generates `app-templates/index` from the directories found (`generateAppTemplates` in
`api-server/build.gradle.kts`), so an app is added by adding its directory and nothing else. The server refuses
a template whose `uid` is not the name of its directory.

## When an app gets an image of its own

A template whose application reads its environment points at the upstream image and has no Dockerfile:
MySQL, PostgreSQL, Valkey and OpenSearch, today. An app gets an image here when that is not enough:

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

Moving an app from the upstream image to one of ours is a change to its directory alone: add the Dockerfile,
point the template's versions at `ghcr.io/kopernik-us/<uid>:<version>`, and publish.

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
apps/publish.sh hadoop          # the template's first version, which is its default
apps/publish.sh hadoop 3.4.1    # a particular version the template declares
```

The script takes the image ref from the template rather than from an argument, because
`ContainerAppServer.applyTemplate` rejects a create request whose image does not match a template version
exactly. `AppDirectoryTest` holds that ref to `ghcr.io/kopernik-us/<uid>:<version>`. The version is passed as
a `VERSION` build argument, so one Dockerfile serves every version a template declares, and the Dockerfile
states no default of its own: a version is bumped in `template.json` alone.

Publishing requires a clean working tree. The tag names an application version rather than a tree, so a
rebuilt tag cannot be told apart from the one customers already pulled.

The script then pins the digest it pushed in the template, as `versions[].image.digest`, and leaves the change
for you to commit. The server checks that digest against the request, so pinning makes a customer's pull
immutable rather than whatever the tag points at that week; a template naming an image of ours without one
fails `AppTemplateRegistryTest`.

Multi-platform builds need a buildx builder that supports them; Docker Desktop's default one does. An image
whose base offers one architecture records that in a `platforms` file beside its Dockerfile, one platform per
line, rather than leaving it to be remembered on the command line; `PLATFORMS` in the environment overrides
either.

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
namenode starts on a filesystem which exists; the script skips a directory which holds one already, because a
machine replaced under a running cluster comes back with the volume its predecessor wrote, and formatting
that would discard the metadata of every file in HDFS.

**`apache/hadoop:3.5.0` is published for amd64 only**, so this image is too, which is what its `platforms`
file records. A cluster whose machine type is arm64 — AWS Graviton, or the ARM plans at Akamai and
DigitalOcean — fails when the machine pulls the image, and nothing in `machineRequirements` can express an
architecture for the console to steer away from one. Publishing for arm64 would mean building Hadoop from the
`aarch64` binary the Apache download page offers rather than deriving from the official image, which is a
larger thing to own: the JDK, the layout and the user setup would become ours.

## Writing one

The build context is the app's own directory, unlike the component Dockerfiles, which take the repo root
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
