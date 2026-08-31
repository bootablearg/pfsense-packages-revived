# Fallback: building Samba yourself with poudriere

**You probably do not need this.** Samba installs directly from FreeBSD's
official package repository, which is what `install.sh` does by default and
what has been verified on pfSense CE 2.9.0. This document is the fallback for
the one case where that stops working.

## When you would need it

FreeBSD builds packages against a specific `__FreeBSD_version`. pfSense tracks a
snapshot slightly behind it, so `pkg` reports a mismatch:

```
- package: 1600020
- running userland: 1600018
pkg: repository FreeBSD-ports contains packages for wrong OS version
```

The installer passes `IGNORE_OSVERSION=yes`, and on CE 2.9.0 the resulting
binaries run correctly with no missing libraries. That holds because the ABI
(`FreeBSD:16:amd64`) is the same and the gap is small.

Build your own if any of these happen:

* Samba binaries fail to start, or `ldd` reports missing or wrong-version
  libraries after a pfSense upgrade.
* The gap between the pfSense userland and FreeBSD's packages widens across a
  major version boundary.
* Your policy forbids `IGNORE_OSVERSION` on production firewalls.
* You need Samba built with non-default options — for example, without Python,
  to avoid the ~400 MiB footprint.

## What you need

A FreeBSD build host (a VM is fine) whose base matches the pfSense target's
FreeBSD branch. **Do not build on the firewall itself.** Find the target's
values first:

```sh
# On the pfSense box
uname -r                 # e.g. 16.0-CURRENT
pkg config abi           # e.g. FreeBSD:16:amd64
sysctl -n kern.osreldate # e.g. 1600018   <-- match this
```

## Setup

```sh
pkg install -y poudriere-devel git
```

Edit `/usr/local/etc/poudriere.conf` — set `ZPOOL`, `FREEBSD_HOST` and
`USE_TMPFS=yes`.

Create a jail matching the target userland. The `-v` value must correspond to
the `kern.osreldate` you read above; for a `-CURRENT` target you generally
build from source at the matching revision:

```sh
poudriere jail -c -j pf29 -v main -a amd64 -m git+https
poudriere ports -c -p default -m git+https
```

## Build

```sh
echo "net/samba424" > /usr/local/etc/poudriere.d/pf29-pkglist

# Optional: trim the dependency tree
poudriere options -j pf29 -p default -f /usr/local/etc/poudriere.d/pf29-pkglist

poudriere bulk -j pf29 -p default -f /usr/local/etc/poudriere.d/pf29-pkglist
```

Packages land in `/usr/local/poudriere/data/packages/pf29-default/`.

## Publish and use

Serve that directory over HTTPS (any static web server; the original pf2ad
project hosted its repository as plain files in a GitHub repo, which also
works). Then point the installer at it:

```sh
SAMBA_AD_REPO_URL="https://your.host/pf29-default" ./install.sh install
```

`install.sh` writes the repository into a temporary `REPOS_DIR` used only for
the duration of the install, so your firewall's own pkg configuration is never
modified.

## Signing (recommended if others will use it)

```sh
openssl genrsa -out repo.key 4096
openssl rsa -in repo.key -pubout -out repo.pub
poudriere bulk -j pf29 -p default -f pkglist   # then sign the repo
```

Distribute `repo.pub` and add `signature_type: "pubkey"` plus `pubkey:` to the
repository definition. An unsigned third-party package repository on a firewall
is a meaningful supply-chain risk — if you publish one for others, sign it.
