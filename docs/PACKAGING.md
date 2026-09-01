# How these packages register with pfSense

Every package here installs as a real `pfSense-pkg-*` package: it appears under
**System → Package Manager → Installed Packages**, the trash icon removes it,
and removal takes the files, the menu entries, the service and the config entry
with it.

Getting there took more care than expected, and most of the difficulty is
undocumented. This is the map.

## The short version

```
install.sh
  ├── installs binary dependencies from FreeBSD's repository
  ├── stages  pkg/ www/ priv/ bin/  into a temporary root
  ├── writes  info.xml + a pkg manifest with install/deinstall scripts
  ├── pkg create        -> pfSense-pkg-<Name>-<version>.pkg
  ├── pkg-static repo   -> a one-package local repository
  └── pkg install       -> from a local repository *named* pfSense
                              │
                              └── pkg runs the package's +INSTALL script
                                    └── /etc/rc.packages <pkg> POST-INSTALL
                                          └── install_package_xml()
                                                menu, service, config.xml
```

## Four things that are not obvious

### 1. Registering in `config.xml` does not make a package visible

The intuitive approach — add an entry under `installedpackages/package` — is
what an earlier version of this repository did. The package worked, the menu
appeared, and the Package Manager showed nothing at all.

`pkg_mgr_installed.php` does not read `config.xml`. It calls:

```php
$installed_packages = get_pkg_info('all', false, true);
```

which asks **pkg** for packages matching `pfSense-pkg-*`. A package that exists
only in `config.xml` is not one of them, so it is never listed.

### 2. The repository name decides whether a package is listed

This is the sharp edge. Inside `get_pkg_info()`:

```php
if (is_pkg_installed($pkg_info['name'])) {
    $rc = pkg_exec("query %R {$pkg_info['name']}", $out, $err);
    if (!$base_packages && rtrim($out) != g_get('product_name')) {
        continue;                     // <- skipped, silently
    }
```

`%R` is the repository a package came from. A package installed with
`pkg add ./whatever.pkg` reports `unknown-repository`, fails that comparison,
and is dropped from the list — with no message anywhere.

The fix is not a flag. The package has to be *installed from a repository named
`pfSense`*, which is why `install.sh` builds a throwaway local repository and
installs from that:

```sh
printf 'pfSense: { url: "file://%s", enabled: yes, mirror_type: "none" }\n' \
    "${REPO}" > "${REPOS_L}/local.conf"
pkg -o REPOS_DIR="${REPOS_L}" install -y -f "${PKG_FULL}"
```

That local repository lives in its own `REPOS_DIR`, not alongside the copies of
the firewall's own configuration — the real `pfSense.conf` defines a repository
with the same name and would win.

### 3. `pkg repo` does not run on pfSense

Generating the repository catalogue with the normal binary fails:

```
ld-elf.so.1: /usr/local/sbin/pkg: Undefined symbol "fts_open@FBSD_1.9"
```

The same userland-versus-packages gap that makes `IGNORE_OSVERSION` necessary:
pkg is built against a newer FreeBSD than the base system pfSense ships.
`pkg-static` carries its own copy and works:

```sh
pkg-static repo "${REPO}"
```

### 4. Repository config files are read in alphabetical order

pfSense ships `/usr/local/etc/pkg/repos/FreeBSD.conf` containing:

```
FreeBSD-ports: { enabled: no }
```

`install.sh` copies the firewall's repository definitions into a temporary
directory and adds its own alongside them. Later definitions win, so a file
named `00_ports.conf` is overridden by pfSense's `FreeBSD.conf` and the
repository stays **disabled** — while `pkg` reports only
`No packages available to install matching 'postfix'`, which reads like the
package does not exist for this ABI.

The file is therefore named `zz_ports.conf`, and `prepare_repos()` verifies the
result rather than trusting it:

```sh
if ! tpkg -vv | awk '/^  FreeBSD-ports: \{/,/^  \}/' | grep -q 'enabled *: *yes'; then
    err "The FreeBSD-ports repository is disabled in ${REPOS_D}."
fi
```

## The install and deinstall scripts

Two shell scripts in the manifest do the integration, and they are copied from
what Netgate's own packages do (`pkg query` on `pfSense-pkg-System_Patches`
shows the originals):

```sh
# +INSTALL, called with $2 = PRE-INSTALL then POST-INSTALL
if [ "${2}" != "POST-INSTALL" ]; then exit 0; fi
/usr/local/bin/php -f /etc/rc.packages pfSense-pkg-<Name> ${2}

# +DEINSTALL, called with $2 = DEINSTALL then POST-DEINSTALL
/usr/local/bin/php -f /etc/rc.packages pfSense-pkg-<Name> ${2}
```

Both deinstall phases matter, and they do different work:

| phase | when | what `delete_package_xml()` does |
|---|---|---|
| `DEINSTALL` | before files are removed | runs `custom_php_deinstall_command`, removes menu entries and services |
| `POST-DEINSTALL` | after files are removed | removes the `installedpackages/package` entry |

The package's own cleanup runs while its `.inc` files still exist. That is why
`samba_ad_deinstall()` can still leave the domain on the way out.

## Services cannot be started from the install script

This one costs an afternoon if you do not know it.

`pkg` makes itself the *reaper* of the process tree of every script it runs
(`procctl(PROC_REAP_ACQUIRE)`), and kills everything still in that tree when the
script returns. A reaper follows reparented children, so the usual escapes do
not help: `winbindd -D` daemonises, `daemon(8)` calls `setsid()`, the process
ends up with PPID 1 in a session of its own -- and is still killed.

What that looks like from the outside is unnerving. The package's install hook
starts the daemon, checks it, logs that it is running, and finishes cleanly:

```
Samba AD: starting winbindd (rc=0)
Samba AD: winbindd is running.
pfSense-pkg-Samba_AD reinstalled: 1.1.0 -> 1.1.0
```

Two seconds later the daemon is gone, with nothing in its own log -- SIGKILL
leaves no parting message, so there is not even a "received signal 15" line to
suggest somebody killed it.

Netgate's packages do not start services from their install scripts either;
services come up when the settings page is saved, or at boot. `install.sh`
therefore runs the package's own resync once more *after* `pkg` has finished
and let go:

```sh
start_services() {
	php -r 'require_once("pkg-utils.inc");
	        $GLOBALS["pkg_interface"] = "console";
	        sync_package("<Name>");'
}
```

That is the same code path the GUI uses on save, and outside the reaper it
sticks.

## `info.xml`

`/usr/local/share/pfSense-pkg-<Name>/info.xml` is what `install_package_xml()`
reads, and its contents become the `config.xml` entry verbatim:

```xml
<pfsensepkgs>
	<package>
		<name>Samba AD</name>
		<internal_name>Samba_AD</internal_name>
		<descr><![CDATA[...]]></descr>
		<version>1.1.0</version>
		<configurationfile>samba_ad.xml</configurationfile>
	</package>
</pfsensepkgs>
```

`internal_name` must equal the suffix of the pkg name: `uninstall_package()`
reconstructs `pfSense-pkg-{$internal_name}` to decide what to delete.

## Dependencies

The manifest's `deps` are generated from what is installed at build time rather
than hard-coded:

```sh
pkg query %v e2guardian      # version
pkg query %o e2guardian      # origin
```

so the manifest can never disagree with the machine it was built on, and no
version needs updating when FreeBSD moves.

Dependencies **this script installed** are then marked automatic
(`pkg set -A 1`), so removing the package takes them with it. Anything that was
already present is left explicitly installed — it may be there for reasons of
its own, and quietly making somebody else's package auto-removable would be
rude.

## What this deliberately does not do

- **No pkg repository is hosted.** Building on the target means the ABI always
  matches and there is no signing key to manage or trust. The cost is that
  installation needs the FreeBSD repository reachable once.
- **The firewall's `/usr/local/etc/pkg/repos/` is never written to.** Every
  repository definition lives in a temporary `REPOS_DIR` that is deleted on
  exit, including on failure. An interrupted run cannot leave a third-party
  repository enabled on a firewall.

## Testing a change to the packaging

The trap to avoid is testing only the path where everything is already
installed. Two bugs in this repository — the `${ABI}` expansion and the
`00_ports.conf` ordering — were both invisible that way, because an installed
dependency skips the repository code entirely.

```sh
./install.sh check                       # changes nothing
./install.sh install
pkg query %R pfSense-pkg-<Name>          # must print exactly: pfSense
php -r 'require_once("pkg-utils.inc");
        foreach (get_pkg_info("all",false,true) as $p) echo $p["name"]."\n";'
```

Then remove it the way a user would, and confirm the files actually go:

```sh
php -r 'require_once("pkg-utils.inc"); uninstall_package("<Name>");'
ls /usr/local/www/<something-the-package-owned>   # must be gone
```
