# Verification checklist — postfix

Run against pfSense CE 2.9.0-RELEASE (`FreeBSD:16:amd64`, PHP 8.5.7).

## Done

### Code compatibility

The package needed **no porting**. Its PHP and XML are carried unmodified:

* every `.inc` passes `php -l` under PHP 8.5;
* every `.xml` parses through pfSense's own `parse_xml_config_pkg()`.

### Availability

`postfix` is present in FreeBSD's official repository for this ABI, and
`install.sh check` resolves it and prints a coherent install plan (9 MiB (4 packages)).

### Installer

`sh -n install.sh` is clean, and the `check` path runs end to end against the
real repository.

## Open — and this is a lot

**The package has not been installed or run.** Everything below is untested:

### A. Installation on a live system

`install.sh install` has not been executed for this package.

### B. Mail actually flowing

No message has been processed. For a mail component that is the test that
counts.

### C. The GUI

No screen opened in a browser.

### D. Interaction with the rest of the system

In particular whether anything else on the firewall binds the ports this needs.

### E. pfSense Plus

Not run there.
