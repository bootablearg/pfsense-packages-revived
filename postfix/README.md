# Postfix Forwarder

Mail gateway and forwarder: accepts SMTP, applies antispam and access policy, and relays on to your real mail server. For **pfSense CE 2.9 / Plus 26.x**.

*[Versión en castellano: LEEME.md](LEEME.md)*

Revived from the postfix package in
[Unofficial-pfSense-packages](https://github.com/marcelloc/Unofficial-pfSense-packages)
(Apache-2.0, Marcello Coutinho). The binary comes from FreeBSD's official
package repository.

## Before you install

**It listens on SMTP.** Do not install it where something already binds port 25, and think about whether your border firewall is where mail processing belongs. For a small office already running pfSense this avoids a separate appliance; at larger scale a dedicated gateway is the better shape.

## Status

| Verified | Not yet verified |
|---|---|
| Available in FreeBSD's repository for this ABI, install plan resolves (9 MiB (4 packages)) | Installed and running on a live box |
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
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/postfix/install.sh | sh -s check
```

`check` changes nothing and prints exactly what would be installed. Then
`| sh -s install`, and open **Services → Postfix Forwarder**.

## Uninstall

```sh
./install.sh remove
```

## License

Apache-2.0. See [LICENSE](LICENSE) for attributions and the list of changes.
