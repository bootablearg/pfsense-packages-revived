# pfsense-packages-revived

Paquetes adicionales para **pfSense CE 2.9 / Plus 26.x**, reconstruidos a
partir de originales abandonados o pagos, de manera que se instalen usando
únicamente software libre: sin claves de licencia y sin repositorios de
binarios de terceros.

*[English version: README.md](README.md)*

Netgate fue quitando muchos paquetes del repositorio oficial con los años, y
varios paquetes de la comunidad dejaron de mantenerse alrededor de pfSense 2.4.
El código muchas veces sigue existiendo y con licencia libre — lo que ya no
funciona es su ejecución en un pfSense moderno: PHP 8 lo rompió, se eliminaron
APIs, y los binarios de los que dependía nunca se recompilaron para la ABI
actual.

Este repositorio los revive de a uno, siempre con el mismo método: portar la
interfaz a las APIs actuales de PHP y pfSense, e instalar los binarios desde el
**repositorio oficial de FreeBSD** en lugar de uno privado.

## Paquetes

| Paquete | Qué hace | Estado |
|---|---|---|
| **[samba-ad](samba-ad/)** | Une el firewall a un dominio de Active Directory (Samba/winbind). Integración opcional con Squid con inicio de sesión único. | Verificado de punta a punta en CE 2.9.0 contra un AD real |

Hay más en camino. En [docs/PATTERN.md](docs/PATTERN.md) está documentado cómo
se agrega un paquete; las instrucciones de instalación están en el README de
cada uno.

## Instalación

Cada paquete se instala por su cuenta. Desde la shell de pfSense como root:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/samba-ad/install.sh | sh -s check
```

`check` informa qué haría y no modifica nada. Conviene leer el README del
paquete antes de instalar: cada uno tiene sus propios requisitos y advertencias.

## Licencias

**Cada paquete conserva la licencia de la obra de la que deriva**, en su propio
directorio. Deliberadamente no hay una licencia única en la raíz, porque provienen
de autores distintos con términos distintos:

| Paquete | Licencia | Deriva de |
|---|---|---|
| [samba-ad](samba-ad/LICENSE) | BSD 2-Clause | pf2ad, © 2013-2016 Luiz Gustavo S. Costa |

Los avisos de copyright originales se conservan tal como esas licencias lo
exigen. Si bifurcás este repositorio, mantenelos.

## Qué significa "revived" acá

Cada paquete de este repositorio fue:

- **portado** a las APIs de PHP y pfSense de la versión objetivo, no simplemente
  copiado: funciones eliminadas reemplazadas, roturas de PHP 8 corregidas,
  puntos de inyección cerrados;
- **instalado sólo desde fuentes libres**: los binarios salen del repositorio
  oficial de FreeBSD, así que no hay clave que comprar ni repositorio de
  terceros en el que confiar;
- **ejecutado de verdad** sobre un pfSense real, con los resultados anotados en
  el `docs/VERIFY.md` de cada paquete, incluyendo lo que **no** se probó.

Si algo no está probado, lo dice. Acá nada afirma funcionar porque parezca que
debería.

## Marcas

pfSense es una marca registrada de Rubicon Communications, LLC (Netgate). Este
proyecto no está afiliado a Netgate ni cuenta con su respaldo.
