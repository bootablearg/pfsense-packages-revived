# Mailscanner

Mail filtering gateway: wraps SpamAssassin and ClamAV to scan messages for spam, viruses and unwanted attachments. For **pfSense CE 2.9 / Plus 26.x**.

*[Versión en castellano: LEEME.md](LEEME.md)*

Revived from the mailscanner package in
[Unofficial-pfSense-packages](https://github.com/marcelloc/Unofficial-pfSense-packages)
(Apache-2.0, Marcello Coutinho). The binary comes from FreeBSD's official
package repository.

## Before you install

**It needs an MTA underneath** -- the [postfix](../postfix/) package in this repository provides one; install and configure that first. Also note FreeBSD ships **5.3.4** while upstream is at 5.5.x, the project's development has slowed relative to newer filtering stacks, and it pulls in about **93 MiB**.

## Status

| Verified | Not yet verified |
|---|---|
| Available in FreeBSD's repository for this ABI, install plan resolves (93 MiB) | Installed and running on a live box |
| Every package `.inc` lints clean under **PHP 8.5** | Any mail actually processed |
| Every package XML parses with pfSense's own parser | The GUI screens in a browser |
| Installer syntax-checks and its `check` path resolves the package | pfSense Plus |

**This package is less tested than the others in this repository.** Its code was
verified compatible and the installer resolves the package, but it has not been
run end to end on a live system. Treat it as a starting point, not a finished
deployment.

The package's PHP and XML are carried **unmodified** — they were already
compatible. Only an installer and documentation were added.

## Install

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/mailscanner/install.sh | sh -s check
```

`check` changes nothing and prints exactly what would be installed. Then
`| sh -s install`, and open **Services → Mailscanner**.

## Uninstall

```sh
./install.sh remove
```

## License

Apache-2.0. See [LICENSE](LICENSE) for attributions and the list of changes.
