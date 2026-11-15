# App index

<!-- Generated from each app's template.json and the Dockerfiles of its versions; not edited by hand. -->

Every version of every app, as its template states it: the image a machine pulls for it, what that image is
built from, the architectures it runs on and the license of its application. A machine pulls the image
exactly as named here, by digest where one is given, and an image of ours can be checked as
[Verifying an image](README.md#verifying-an-image) describes.

The license is the application's own. An image also carries the licenses of its base layers, which
[Licenses](README.md#licenses) explains.

| App | Version | Image | Built from | Architectures | Application license |
|---|---|---|---|---|---|
| [`hadoop`](hadoop/template.json) | 3.5.0 | `ghcr.io/kopernik-us/hadoop:3.5.0@sha256:3d07a2077dbd4e4e321fa31b24af8023315eb5c2508cef6a5377f044432fe55d` | [`hadoop/3.5.0/`](hadoop/3.5.0/), `FROM apache/hadoop:3.5.0` | x86_64 | Apache-2.0 |
| [`mysql`](mysql/template.json) | 8.4.13 | `ghcr.io/kopernik-us/mysql:8.4.13@sha256:60042f3d7d87b57c64a320bd328fd508d338b46c58c8fbe29e6b692a161fd68e` | [`mysql/8.4.13/`](mysql/8.4.13/), `FROM mysql:8.4.13` | x86_64, arm64 | GPL-2.0-only |
| [`mysql`](mysql/template.json) | 9.7.4 | `ghcr.io/kopernik-us/mysql:9.7.4@sha256:6cd8feab4740e1f4fca3b0c6127f0ce63d606a42a977d2f9ee5d144d85c55e95` | [`mysql/9.7.4/`](mysql/9.7.4/), `FROM mysql:9.7.4` | x86_64, arm64 | GPL-2.0-only |
| [`opensearch`](opensearch/template.json) | 3.5.0 | `opensearchproject/opensearch:3.5.0` | the upstream image, as published | any | Apache-2.0 |
| [`postgres`](postgres/template.json) | 18.4 | `postgres:18.4` | the upstream image, as published | any | PostgreSQL |
| [`valkey`](valkey/template.json) | 9 | `valkey/valkey:9` | the upstream image, as published | any | BSD-3-Clause |
