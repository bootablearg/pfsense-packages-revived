# pfsense-samba-ad

Unir un firewall pfSense a un dominio de Active Directory usando winbind de
Samba, sin clave de licencia y sin repositorios propietarios.

*[English version: README.md](README.md)*

Este proyecto es un derivado modernizado de
[pf2ad](https://github.com/pf2ad/pf2ad), rama `2.4.3-SAMBA4`, publicada por
Luiz Gustavo S. Costa bajo licencia BSD 2-Clause. Las versiones posteriores de
pf2ad pasaron a un modelo comercial, con claves de descarga por instalación y
un repositorio de binarios alojado por el proveedor. Este proyecto retoma
aquella base BSD y la reconstruye sobre el **repositorio oficial de paquetes de
FreeBSD**, de modo que todo lo que hay acá es software libre que cualquiera
puede instalar, inspeccionar y bifurcar.

## Estado

Verificado sobre **pfSense CE 2.9.0-RELEASE** (FreeBSD 16.0-CURRENT,
`FreeBSD:16:amd64`, PHP 8.5.7) con **Samba 4.24.6**, unido a un dominio Active
Directory real y comprobado de punta a punta.

| Verificado | Sin verificar todavía |
|---|---|
| **El join funciona**: `net ads testjoin` devuelve `Join is OK` y la cuenta de máquina aparece en el directorio | Revisión visual de las pantallas en un navegador |
| **Confianza y winbind**: `wbinfo -t` y `wbinfo -p` correctos | pfSense Plus (el instalador lo detecta, pero no se probó ahí) |
| **Usuarios y grupos del dominio se resuelven** (`wbinfo -u`, `wbinfo -g`) | Squid instalado y funcionando como proxy con estas credenciales |
| **idmap `rid` mapea correctamente** dentro del rango configurado | Comportamiento tras una actualización de pfSense |
| **La autenticación funciona**: `ntlm_auth --helper-protocol=squid-2.5-basic` devuelve `OK`, que es exactamente el camino que usa Squid | |
| Keytab de Kerberos con los principales `HOST/` y `RestrictedKrbHost/` | |
| Samba se instala sin tocar ningún paquete de pfSense (57 paquetes, sin actualizaciones ni reemplazos) | |
| El instalador es idempotente: instalar → quitar → instalar; la desinstalación deja la configuración como estaba | |
| El `smb4.conf` generado pasa `testparm` sin advertencias | |
| Los archivos PHP pasan `php -l` con PHP 8.5.7; el XML lo interpreta el propio parser de pfSense | |

## Qué hace

* Instala Samba (winbind) desde el repositorio oficial de FreeBSD.
* Agrega una pantalla **Services → Samba AD** para unir el firewall al dominio.
* Agrega una pantalla de **Diagnostics** para probar la membresía y depurar.
* Genera `smb4.conf` y `krb5.conf`, hace el join y crea el keytab de Kerberos.
* Deja `ntlm_auth` disponible para que Squid *pueda* autenticar contra el AD,
  sin depender de que Squid esté instalado.

## Qué no hace

* **No parchea el paquete Squid.** El original reescribía `squid.inc` y
  `squid_auth.xml` con un parche protegido por un MD5 fijo de una compilación
  exacta del proveedor. Eso se rompía con cada actualización de Squid y era lo
  más frágil que tenía. Acá la integración con Squid son unas pocas líneas de
  configuración que se pegan a mano (ver más abajo).
* **No convierte a pfSense en controlador de dominio.** Lo une como *miembro*.
  El servicio de archivos (`smbd`) viene desactivado.
* **No distribuye binarios.** Samba se instala desde el repositorio de FreeBSD.

## Requisitos

* pfSense CE 2.8/2.9 o pfSense Plus 25.x/26.x.
* Unos **400 MiB de espacio libre**. Samba arrastra Python y alrededor de 30
  módulos `py312-*`. Conviene revisar `df -h /` antes, sobre todo en equipos
  con eMMC chico.
* Resolución DNS del dominio AD, y reloj sincronizado dentro de los cinco
  minutos respecto de los controladores de dominio (si no, Kerberos rechaza la
  autenticación).

## Instalación

Todo se ejecuta como root desde la shell de pfSense (opción 8 de la consola, o
por SSH).

**Primero verificar — esto no modifica nada:**

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install.sh | sh -s check
```

Informa el producto, la versión y la ABI detectados, si hay un Samba
compatible disponible, y qué instalaría.

**Después instalar:**

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install.sh | sh -s install
```

Conviene detenerse un segundo antes de canalizar un script de internet hacia
una shell de root en un firewall. Si se prefiere, primero leerlo — son unos
cientos de líneas, comentadas:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install.sh | less
```

**O desde un clon**, que no necesita red para los archivos del paquete:

```sh
git clone https://github.com/bootablearg/pfsense-samba-ad.git
cd pfsense-samba-ad
chmod +x install.sh
./install.sh check
./install.sh install
```

Después abrir **Services → Samba AD**, completar los datos del dominio y tildar
*Enable* para hacer el join.

### Opciones

| Variable | Para qué sirve |
|---|---|
| `SAMBA_PKG` | Fijar una rama de Samba en lugar de la más nueva, por ejemplo `SAMBA_PKG=samba423` |
| `SAMBA_AD_SRC_URL` | URL base de los archivos del paquete — apuntarla a un fork o rama propia |
| `SAMBA_AD_REPO_URL` | Repositorio pkg alternativo, si se compila Samba por cuenta propia |

## Las pantallas

El instalador agrega y registra dos pantallas:

**Services → Samba AD → Settings** (`pkg/samba_ad.xml`)
La pantalla que une el firewall al dominio:

| Campo | Notas |
|---|---|
| Enable | Al destildarlo se detienen los demonios pero se conserva la membresía, así que volver a activarlo no requiere un nuevo join |
| Listen interface(s) | Selección múltiple. La interfaz de loopback se agrega siempre |
| Domain / Realm | Nombre DNS completo, por ejemplo `example.local` |
| Workgroup | Nombre NetBIOS corto, por ejemplo `EXAMPLE` |
| Domain controller | Opcional. Ver la nota sobre DNS más abajo |
| Join Username / Password | Se usan sólo para el join y para crear el keytab |
| idmap backend | `rid` (predeterminado) o `ad` — ver más abajo |
| Rangos de idmap | Se valida que no se superpongan antes de escribir nada |
| Also run smbd/nmbd | Desactivado por defecto; sólo hace falta para compartir archivos |
| Log level, Custom options | Se trasladan a `smb4.conf` |

**Services → Samba AD → Diagnostics** (`pkg/diag_samba_ad.php`)
Estado de winbindd, el keytab, el canal privilegiado de winbind y ntlm_auth,
más pruebas de un clic: verificar la membresía (`net ads testjoin`), hacer ping
a winbindd, revisar el secreto de confianza, mostrar información del dominio,
listar el keytab y validar `smb4.conf` con `testparm`.

Cada comando de diagnóstico es una cadena fija; la petición sólo elige cuál
ejecutar, de modo que ninguna entrada del usuario llega nunca a una shell.

### Sobre el backend de idmap

El valor predeterminado es **`rid`**, no `ad`. El backend `ad` requiere que los
atributos `uidNumber` y `gidNumber` estén cargados en el directorio (RFC2307).
La mayoría de los dominios no los tiene, y entonces winbind no mapea ningún
usuario — una falla confusa que el original facilitaba al usar `ad` por
defecto. `rid` deriva los identificadores por algoritmo y funciona contra un
Active Directory de fábrica. Conviene elegir `ad` sólo si se sabe que el
directorio tiene atributos POSIX.

### Sobre el DNS y el campo "Domain controller"

Kerberos localiza el KDC mediante registros SRV (`_kerberos._tcp.<dominio>` y
`_ldap._tcp.<dominio>`). Es habitual que el resolver del firewall resuelva el
nombre del dominio pero **no** sus registros SRV: en ese caso el join falla.

Para eso existe el campo opcional **Domain controller**: al completarlo, el KDC
queda fijado en `krb5.conf` bajo `[realms]` y se le pasa `-S` a `net`, con lo
cual el join funciona sin modificar la configuración DNS del firewall.

La solución más prolija en producción es un *Domain Override* en el DNS
Resolver (**Services → DNS Resolver → Domain Overrides**) que apunte la zona
del AD a un controlador de dominio, para que la zona resuelva completa.

## Opcional: autenticar Squid contra el AD

Instalar Squid normalmente (**System → Package Manager**) y pegar esto en las
*Custom Options (Before Auth)* de Squid o en `squid.conf`:

```
# Kerberos / Negotiate -- preferido. Transparente para clientes del dominio.
auth_param negotiate program /usr/local/libexec/squid/ntlm_auth --helper-protocol=gss-spnego
auth_param negotiate children 20
auth_param negotiate keep_alive on

# NTLM -- alternativa para clientes que no pueden usar Kerberos.
auth_param ntlm program /usr/local/libexec/squid/ntlm_auth --helper-protocol=squid-2.5-ntlmssp
auth_param ntlm children 20
auth_param ntlm keep_alive on

# Basic -- ultimo recurso. Envia credenciales en texto claro salvo sobre TLS.
auth_param basic program /usr/local/libexec/squid/ntlm_auth --helper-protocol=squid-2.5-basic
auth_param basic children 5
auth_param basic realm Proxy
auth_param basic credentialsttl 2 hours

acl usuarios_dominio proxy_auth REQUIRED
http_access allow usuarios_dominio
```

`/usr/local/libexec/squid/ntlm_auth` es un **enlace simbólico** al binario de
Samba, creado por este paquete. El original copiaba el archivo, con lo cual
quedaba desactualizado en cada actualización de Samba y después fallaba de
formas que parecían problemas del dominio.

Conviene preferir Negotiate sobre NTLM: Microsoft declaró obsoleto a NTLM, y
Samba desactiva NTLMv1 por defecto. Este paquete configura
`ntlm auth = ntlmv2-only`.

Si la pantalla de Diagnostics muestra *ntlm_auth linked into Squid: not in
use*, quiere decir que Squid se instaló después que este paquete: basta con
volver a ejecutar `./install.sh install` para crear el enlace.

## Notas y advertencias

**Desfase de versión del sistema operativo.** pfSense sigue una instantánea de
FreeBSD levemente anterior a aquella contra la que se compilan los paquetes
oficiales. En CE 2.9.0 el userland informa `1600018` mientras que los paquetes
están compilados para `1600020`, y `pkg` rechaza el repositorio por defecto. El
instalador usa `IGNORE_OSVERSION=yes`. Esto se probó: la ABI coincide
(`FreeBSD:16:amd64`), los binarios se ejecutan y `ldd` no informa bibliotecas
faltantes. Aun así, es la única suposición del proyecto que podría romperse en
una versión futura: si Samba empieza a fallar después de actualizar pfSense,
esto es lo primero que hay que revisar.

**El repositorio adicional nunca se escribe en la configuración del firewall.**
Vive en un `REPOS_DIR` temporal que se usa sólo durante la instalación. El
original escribía en `/usr/local/etc/pkg/repos/` y lo borraba al final; si moría
en el medio, quedaba habilitado un repositorio de terceros que después podía
sobrescribir paquetes de pfSense. Acá, una ejecución interrumpida no deja nada.

**Actualizaciones.** Las actualizaciones mayores de pfSense reemplazan el
sistema base. Hay que prever volver a ejecutar el instalador y reinstalar Samba
para la nueva ABI. Netgate recomienda quitar los paquetes adicionales antes de
una actualización mayor.

**Credenciales.** La contraseña de la cuenta de join queda almacenada en
`config.xml`, como ocurre con todo paquete de pfSense que necesite una. Conviene
usar una cuenta delegada con permiso para unir equipos, no una de Domain Admin.

## Desinstalación

```sh
./install.sh remove
```

Abandona el dominio (quitando la cuenta de máquina del directorio), desregistra
las pantallas, restaura el `krb5.conf` anterior y elimina los archivos del
paquete. Samba queda instalado; el script informa el comando para quitarlo.

## Licencia

BSD 2-Clause. Copyright (c) 2013-2016 Luiz Gustavo S. Costa; copyright (c) 2026
los contribuyentes de pfsense-samba-ad. Ver [LICENSE](LICENSE).

Samba se distribuye bajo GPLv3 y no se incluye en este proyecto: se instala
desde el repositorio de paquetes de FreeBSD durante la instalación.

pfSense es una marca registrada de Rubicon Communications, LLC (Netgate). Este
proyecto no está afiliado a Netgate ni respaldado por Netgate, ni por el
proyecto pf2ad.
