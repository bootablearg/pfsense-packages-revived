# The pattern

How a package gets revived here. This is not theory: every step below came out
of doing it once, and the gotchas are the ones that actually bit.

## The problem, in general

An abandoned pfSense package usually fails for three independent reasons at
once, and fixing only one gets you nowhere:

1. **The GUI code is dead.** Written for PHP 5.6/7 and pfSense 2.3/2.4. On PHP 8
   it hits removed functions, silent `foreach` no-ops over absent config arrays,
   and APIs that no longer exist (`conf_mount_rw()`, gone since 2.5).
2. **The binaries do not exist for the current ABI.** The upstream software may
   be alive and packaged by FreeBSD, but pfSense's repository does not carry it.
3. **The installer hardcodes a release.** `if [ "$(cat /etc/version)" != "2.4.5-RELEASE" ]; then exit; fi`
   is why so many of these died the day the next version shipped.

## The method

### 1. Establish the license before writing a line

Find the original and read its actual license file and per-file headers — not a
blog post about it. If it is BSD, Apache-2.0, MIT or GPL, you can fork it,
provided you **keep the original copyright notice**. If there is no license at
all, you cannot redistribute it, full stop.

Put the license in the package's own directory, with the original holder named.

### 2. Find the binaries in FreeBSD's official repository

Check the target's ABI first, on a real box:

```sh
pkg config abi           # e.g. FreeBSD:16:amd64
pkg search -q <name>     # is it in pfSense's own repo? usually not
```

Then look in FreeBSD's catalogue without installing anything:

```sh
fetch -qo - https://pkg.freebsd.org/FreeBSD:16:amd64/latest/packagesite.pkg \
  | tar -xOf - packagesite.yaml \
  | grep -oE '"name":"<name>[^"]*","origin":"[^"]*","version":"[^"]*"'
```

If it is there, you need no private repository and no build host. If it is not,
you are looking at poudriere — see `samba-ad/docs/BUILD-samba-poudriere.md`.

**Also check the version gap.** FreeBSD ports can lag upstream by years. And
check for known vulnerabilities before shipping anything:

```sh
pkg audit -F
pkg audit <name>-<version>
```

### 3. Expect the OS version mismatch

pfSense tracks a FreeBSD snapshot slightly behind the one the official packages
are built against, so `pkg` refuses the repository outright:

```
- package: 1600020
- running userland: 1600018
pkg: repository FreeBSD-ports contains packages for wrong OS version
```

`IGNORE_OSVERSION=yes` gets past it. On CE 2.9.0 the ABI matches, the binaries
run and `ldd` reports nothing missing — verified. It remains the one assumption
that could break on a future release, so say so in the package README rather
than hiding it.

### 4. Never write into the firewall's pkg configuration

Build a temporary `REPOS_DIR` that copies the existing repositories and adds
FreeBSD's alongside, and point pkg at it for the duration:

```sh
pkg -o REPOS_DIR="$TMP_REPOS" install -y <pkg>
```

The tempting alternative — writing into `/usr/local/etc/pkg/repos/` and deleting
it afterwards — leaves a third-party repository enabled if the script dies in
between, which can then override pfSense's own packages later. Use a `trap` to
clean up whatever happens.

### 5. Always dry-run first

```sh
IGNORE_OSVERSION=yes pkg -o REPOS_DIR=$D install -n <pkg>
```

Read the plan. **Anything under "to be UPGRADED" or "REINSTALLED" is a red
flag**: it means the package wants to replace something pfSense owns. Only
"New packages to be INSTALLED" is safe. Note the disk cost too — Samba pulls in
Python and needs 408 MiB, which matters on appliances with small eMMC.

### 6. Port the GUI

The recurring fixes, all of which were needed at least once:

| Problem | Fix |
|---|---|
| `global $config` | `config_get_path('path', [])` with a default |
| `foreach` over an absent config array | same — on PHP 8 it iterates nothing and only warns |
| `conf_mount_rw()` / `conf_mount_ro()` | delete; removed in pfSense 2.5 |
| A helper that redefines a pfSense function | use the native one; redefining is a fatal error |
| Credentials interpolated into a shell string | mode-0600 auth file + `escapeshellarg()` everywhere |
| `killall <daemon>` | `pkill -x`; `killall` hits processes you do not own |
| `ps axuw | grep` to detect a daemon | `pgrep -x` |
| A copied binary that goes stale | symlink |
| No uninstall | implement it; orphaned state is worse than no feature |

Then lint against the real target, which is the only PHP version that counts:

```sh
php -l pkg/<file>.inc
php -r 'require_once("pkg-utils.inc"); print_r(parse_xml_config_pkg("/usr/local/pkg/<file>.xml","packagegui"));'
```

### 7. Detect the platform, never hardcode it

```sh
php -r 'require_once("globals.inc"); echo $g["product_name"];'   # pfSense | pfSense Plus
```

Authoritative, because it is the same value the GUI uses. Parse `/etc/version`
only as a fallback.

### 8. Verify on a real box, and write down what you did not test

Every package carries a `docs/VERIFY.md` with the commands run and their real
output, plus an explicit "Open" section. **Reboot the box** — it is the cheapest
test there is and it caught a defect that nothing else did: a domain controller
pinned only for the join worked perfectly until the firewall restarted, and then
failed every lookup while the controller sat there reachable.

Also remember that pfSense starts package services late, so a service can take
one to two minutes after boot to appear.

## Repository conventions

- One directory per package, self-contained: `install.sh`, `pkg/`, `docs/`,
  `README.md`, `LEEME.md`, `LICENSE`.
- Installers take `check | install | remove | status`. `check` changes nothing
  and `remove` genuinely undoes things.
- Installers work from a clone *and* piped from the network (`| sh -s install`),
  which means never relying on `$0` having a directory.
- Code and docs in English; a `LEEME.md` in Spanish alongside.
- `.gitattributes` forces LF. A CRLF in `install.sh` makes FreeBSD fail with
  "bad interpreter", and git on Windows will happily introduce one.
- **Never commit anything carrying a license key, a token or a customer's
  domain data.** Grep before publishing — the originals of these packages
  sometimes have vendor keys embedded in them.
