# kopernik.us apps

The applications [kopernik.us](https://kopernik.us) offers to deploy on your own cloud account, one directory per
app, named after the app's template `uid`. They are published here so that you can read what your machines run
before running it, and check that the image a machine pulls was built from this repository.

```
INDEX.md            every version of every app: its image, what that is built from, and its license
<uid>/
  template.json     the app template: what the console offers, and how its containers run
  <version>/        one per template version whose image is ours, named as the template names the version
    Dockerfile      the image of that version, when the upstream image cannot run it as the template describes
    ...             whatever the image copies in, beside its Dockerfile
```

A directory is the single place an app is defined. The template names things its image provides — the image's own
ref, the scripts a container runs, the directories it prepares for data — so the two are kept together and changed
in one commit, and kopernik.us checks as it builds that they agree.

This repository is a mirror of the `apps/` directory of kopernik.us, kept with its history. It does not take
contributions yet: issues and pull requests are not answered.

The files here are under the [MIT license](LICENSE). The software inside the images is not: each image is built on,
or is, an upstream image, distributed under its own authors' licenses; see [Licenses](#licenses).

## Verifying an image

Every image under `ghcr.io/kopernik-us/` named by a template here is built by this repository's
[publish workflow](.github/workflows/publish.yml) from a commit of `main`, and the workflow attests each build: a
signed statement, kept in the registry and on GitHub, of the workflow, the commit and the digest. kopernik.us
publishes these images through that workflow alone, so every build of a tag is attested, whichever one a machine
pulled.

A template names an image by its tag, ours as upstream ones, so that a tag rebuilt on patched software reaches the
machines created after it. To check an image, take the digest a machine runs, from
`docker inspect --format '{{index .RepoDigests 0}}' <image>` on the machine, or the digest a tag names now, from
`docker buildx imagetools inspect <image>`, and run:

```bash
gh attestation verify oci://ghcr.io/kopernik-us/mysql@sha256:<digest> \
  --repo kopernik-us/apps \
  --signer-workflow kopernik-us/apps/.github/workflows/publish.yml \
  --source-ref refs/heads/main
```

The output names the commit the image was built from, whose `<uid>/<version>/` is everything that went into it.

## One directory per version

Each version's image is built from a directory of its own, which states everything about it, the base image's
tag included: `FROM mysql:8.4.13`, not a `VERSION` argument the build is handed. So a version's directory is all
that goes into its image, and a change made for one version, say an option a newer server renamed, reaches no other
until it is made there too. The cost is that files every version shares, such as MySQL's entry point, are copied
into each; a change meant for all of them is made in all of them, which a diff of one directory against another
shows.

A version is added by copying the directory of the nearest one, changing its `FROM` and whatever else differs,
adding the version to the end of `template.json`'s `versions`, which the console and the API take as the latest,
and publishing it. A version is retired by removing both, in one commit. An app directory holds its template and the
directories of the versions it declares, and nothing else, since nothing publishes an image from anywhere else.

What a version cannot differ in is its template. A version states its own image, `architectures`,
`machineRequirements`, license and product link, but containers, environment, ports and data paths belong to the
template, so versions whose application is configured differently, rather than built differently, are separate apps
under separate uids.

## When an app gets an image of its own

A template whose application reads its environment points at the upstream image and has no Dockerfile:
PostgreSQL, Valkey and OpenSearch, today. An app gets an image here when that is not enough:

- **The application cannot be configured by environment alone.** Hadoop is the case that started this
  directory: `fs.defaultFS` and `yarn.resourcemanager.hostname` are written into XML files rather than read
  from the environment, so something on the machine has to turn the variables kopernik.us injects into
  configuration before the daemon starts.
- **The application does not size itself to its machine.** An upstream image starts with the defaults its
  publisher chose for a laptop — MySQL's 128 MB InnoDB buffer pool, PostgreSQL's 128 MB `shared_buffers` —
  however large the machine you pay for, so most of it goes unused. An entry point which reads
  `K_US_CONTAINER_MEMORY_MB` and `K_US_CONTAINER_CPUS` (see below) can size the application to the share it
  was given, and does so again on every start, which a template cannot: its environment is fixed when the app
  is created.

Moving an app from the upstream image to one of ours is a change to its directory alone: add a directory with a
Dockerfile for each version, point those versions at `ghcr.io/kopernik-us/<uid>:<version>`, and publish. A
template may keep upstream images for some versions and ours for others.

## Publishing

An image is published by running the workflow **Publish an app version** on `main`, naming the app and,
optionally, the version; without one it publishes the latest the template lists. The workflow takes the image ref
from the template rather than from an input, because kopernik.us creates an app only from an image matching a
template version exactly, and that ref is always `ghcr.io/kopernik-us/<uid>:<version>`. The build context is
`<uid>/<version>/`, and the build is given no arguments: what the image is, its directory says.

A version already published is not rebuilt unless the run asks to `replace` it. Rebuilding is how a version of ours
takes up fixes beneath its application, such as a base image its publisher rebuilt under the same tag: the tag
names an application version rather than a build, and the new build reaches every machine created after it, while a
machine created before keeps the build it pulled. Nothing in the template changes, since it names the tag alone.

The platforms are the template's too. Each version of an app with an image of ours states `architectures`, named as
machine types name them (`x86_64`, `arm64`), and the workflow builds for exactly those, as `linux/amd64` and
`linux/arm64`. kopernik.us offers only machine types of a version's architectures, so an image built for fewer than
its template states would fail on machines it let through. A Dockerfile which runs nothing, setting modes with
`COPY --chmod` rather than `RUN chmod`, builds for every platform without emulation; one with a `RUN` step builds
the platforms other than the runner's own under QEMU, which is slower.

## The registry

`ghcr.io/kopernik-us/<uid>`, which needs no creating: the package exists after the first push.

**A new package is private, and a private one is unusable.** A machine pulls the image itself over cloud-init, so
the only way it could authenticate is with registry credentials given to the app — which would mean shipping a
kopernik.us token to every machine. After the first push, the package is set public, and given this repository's
workflow write access in its settings under **Manage Actions access**.

Public GHCR pulls are anonymous, which also avoids the Docker Hub rate limit an unauthenticated machine would
otherwise meet.

## `hadoop`

`FROM apache/hadoop:3.5.0`, the Apache Software Foundation's own convenience build, with an entry point that
composes the values the upstream image cannot take from the environment and then hands over to
`/opt/starter.sh` unchanged. The upstream image converts variables named `<FILE>.<EXT>_<property>` into
Hadoop configuration, so `CORE-SITE.XML_fs.defaultFS` is a value it would write — but not one a template
could state, because it holds the name of the cluster's first master, and the environment file reaches Docker
unexpanded. The entry point composes it on the machine, where `K_US_MASTER_HOSTS` has a value, and sets
nothing the cluster set for itself, so any of it can be overridden through the app's environment.

`format-hdfs.sh` is the template's init container. A step leads the service containers of its node, so the
namenode starts on a filesystem which exists. The step states the namenode's data path, `/data/namenode`, as its
own, which is what gives the two one directory: each data path is kept in a volume of the node which every
container of the role stating it shares, and a format kept anywhere else is one the namenode never finds. The size
stays on the namenode, which keeps the data. The script skips a directory which holds a filesystem already,
because the directory outlives the containers which use it, and formatting it again would discard the metadata of
every file in HDFS.

The entry point sizes each daemon's heap from `K_US_CONTAINER_MEMORY_MB` rather than leaving it to Java. Java finds
its limit in the cgroup only where it recognises a container, and on kernels which no longer list the cgroup v2
controllers in `/proc/cgroups`, Ubuntu 26.04's among them, it does not: every daemon then sized its heap from the whole
machine, so a resource manager limited to 1GB was let grow past its limit and a namenode given 2GB used under half.
The node manager's own work is light, and YARN's tasks run inside its container, so what YARN hands out is that
container less the node manager's heap and the memory its JVM needs beside it:

| Daemon | Heap |
|---|---|
| node manager | an eighth of its share, from 256MB to 1GB; YARN hands out the share less the heap and 256MB |
| every other | three quarters of its share, leaving at least 256MB |

MapReduce's defaults are scaled to a node of the template's smallest machine, where YARN hands out about 1.6GB: a 1GB
application master and 512MB tasks, allocated in steps of 256MB, rather than 1.5GB, 1GB and 1GB, which together do not
fit such a node at all. YARN's virtual memory check is off, since a JVM's reserved address space exceeds it from the
start; the physical memory check still holds each task to what it asked for. Any of it can be set through the app's
environment, `HADOOP_HEAPSIZE_MAX` included, and the node manager counts a heap set that way.

**`apache/hadoop:3.5.0` is published for amd64 only**, so this image is too, which its template states as
`"architectures": ["x86_64"]`. kopernik.us offers no arm64 machine type, such as AWS Graviton, for it. Publishing
for arm64 would mean building Hadoop from the `aarch64` binary the Apache download page offers rather than deriving
from the official image, which is a larger thing to own: the JDK, the layout and the user setup would become ours.

## `mysql`

`FROM mysql:<version>`, the official image, in `9.7.4/` and `8.4.13/`, with an entry point that sizes the InnoDB
buffer pool to the container's memory share before handing over to the upstream `docker-entrypoint.sh` unchanged.
Upstream starts every server with a 128 MB pool, however large the machine, so a database on an 8 GB machine kept
most of what it reads on disk. The entry point follows InnoDB's own `innodb_dedicated_server` rule, from
`K_US_CONTAINER_MEMORY_MB` rather than from the memory the server detects, which inside a container may be the
whole machine:

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
pointing at it got fixes without a release of ours. A version of ours names an exact release, 9.7.4 or 8.4.13, so a
MySQL security release reaches you only when a new version is added to the template and published, while fixes to
the system beneath it arrive when the version is rebuilt.

## Writing one

The build context is the version's own directory, and an application image needs nothing else, so everything it
uses sits beside its Dockerfile.

An entrypoint configures the application from what kopernik.us injects:

| Variable | What it says |
|---|---|
| `K_US_CONTAINER_MEMORY_MB`, `K_US_CONTAINER_CPUS` | the container's own share of the machine, never counting the memory kept for the system |
| `K_US_MACHINE_MEMORY_MB`, `K_US_MACHINE_CPUS` | the whole machine, for a container sizing itself against it |
| `K_US_CLUSTER_ROLE`, `K_US_NODE_INDEX` | which node of the cluster this is |
| `K_US_CLUSTER_UID`, `K_US_MASTER_NODE_COUNT`, `K_US_CORE_NODE_COUNT` | the cluster the node belongs to and its shape |
| `K_US_MASTER_HOSTS` | every master node by name, comma separated, for the configuration that needs one |

They are read on the machine when the app starts rather than taken from the machine type at provisioning,
so a resized machine is configured for its new size on the next start. The names are reserved: a template
container which sets one is refused. See [cluster apps](https://kopernik.us/docs/api-docs/clusterapp) for the full
list and what each node is told.

## Licenses

The [MIT license](LICENSE) covers what this repository holds: the templates, the Dockerfiles, the scripts they copy
into the images, and the workflow that builds them. It covers nothing an image takes from elsewhere.

An image of ours is an upstream image with a few files added, so almost all of it is the upstream application and
the operating system packages beneath it, each under its own license, which the upstream image documents. A template
which runs an upstream image directly adds nothing to it at all. Running an app means running that software under
those licenses, as running the upstream image yourself would.

Each template states the license of its application as `license`, and a version may state its own; the
[index](INDEX.md) lists the license of every version.

The application's license is not all of an image's: its base layers carry the licenses of the distribution's
packages, and some upstream images bundle further software. The upstream image's own documentation is the place to
read them.
