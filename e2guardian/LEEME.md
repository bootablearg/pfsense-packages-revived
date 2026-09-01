# E2guardian

Filtrado de contenido web para **pfSense CE 2.9 / Plus 26.x**. Filtra por el
*contenido* de la respuesta — frases, tipos MIME, tipos de archivo — y permite
aplicar políticas distintas por grupo de usuarios.

*[English version: README.md](README.md)*

Revivido a partir del [paquete e2guardian de Marcello
Coutinho](https://github.com/marcelloc/Unofficial-pfSense-packages)
(Apache-2.0, 2015-2017), portado a pfSense 2.9 / PHP 8.5 y a e2guardian 5.3.x.
El binario sale del repositorio oficial de FreeBSD: sin repositorio privado y
sin clave.

## Estado

| Verificado | Sin verificar todavía |
|---|---|
| Se instala desde el repositorio de FreeBSD: **3 paquetes, 13 MiB**, sin tocar ningún paquete de pfSense | Las pantallas de la interfaz en un navegador |
| **0 vulnerabilidades conocidas** en el port (`pkg audit`) | Filtrado de tráfico real de punta a punta |
| Los **18 XML** del paquete se leen con el parser propio de pfSense | Descarga de blacklists y filtrado por categorías |
| `e2guardian.inc` (2394 líneas) carga limpio bajo **PHP 8.5** | Encadenado detrás de Squid con autenticación AD |
| El generador de configuración produce un `e2guardian.conf` y un `e2guardianf1.conf` válidos | pfSense Plus |
| **e2guardian arranca y queda escuchando** en el puerto configurado | |
| La entrada de menú y el servicio se registran correctamente | |

## Requisitos

* pfSense CE 2.9 (probado) o Plus 26.x (sin probar).
* ~13 MiB. Mucho más liviano que la mayoría de los stacks de proxy: sólo
  arrastra `harfbuzz` y `talloc`.
* Un proxy por delante, o modo transparente, según el diseño que uses.

## Instalación

Desde la shell de pfSense como root:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/e2guardian/install.sh | sh -s check
```

`check` no modifica nada. Después:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/e2guardian/install.sh | sh -s install
```

Luego abrir **Services → E2guardian Proxy**.

Las blacklists **no** se descargan durante la instalación: son grandes y lentas
de bajar. Se obtienen desde la pestaña Blacklist del paquete cuando hagan falta.

## El arreglo que lo hace funcionar en 5.3.x

El paquete original emite `transparenthttpsport` siempre. Como dice el propio
comentario de configuración de e2guardian, *definir* esa directiva es lo que
habilita HTTPS transparente — su sola presencia, no su valor. Las versiones
viejas lo toleraban con SSL apagado; **5.3.x intenta enlazar el socket igual y
aborta al arrancar**:

```
Error binding server thttps socket: (Address already in use)
```

Ese mensaje engaña por partida doble: el puerto está libre, y señala un
conflicto que no existe. Este paquete emite la directiva sólo cuando SSL o SSL
MITM están habilitados. Sin ese cambio, e2guardian 5.3.4 no arranca en absoluto
con una configuración por defecto.

## Dónde encaja

Conviene tenerlo claro para no construir de más:

| | Filtra por | Estado |
|---|---|---|
| **pfBlockerNG** | dominio e IP (DNS) | oficial, con soporte de Netgate |
| **e2guardian** | contenido de la respuesta, y por grupo | de terceros, este paquete |

Si sólo hace falta bloquear categorías de sitios, **pfBlockerNG cubre la mayor
parte** con soporte oficial y sin proxy. e2guardian se justifica cuando hay que
inspeccionar lo que vuelve, o aplicar reglas distintas a grupos distintos — que
combina naturalmente con el paquete [samba-ad](../samba-ad/) de este
repositorio para la autenticación contra Active Directory.

## Advertencias

**El port de FreeBSD va atrasado.** FreeBSD trae e2guardian **5.3.4** mientras
upstream va por 5.5.x. `pkg audit` no reporta vulnerabilidades conocidas para
5.3.4, pero se trata de software un par de años atrás. Si eso pesa en tu modelo
de amenazas, compilá 5.5.x con poudriere — ver
[../docs/PATTERN.md](../docs/PATTERN.md).

**Squid está deprecado.** Si pensás encadenar e2guardian detrás de Squid, tené
presente que Netgate deprecó ese paquete. e2guardian también puede funcionar de
forma independiente.

**La interfaz es la original.** Funciona, pero fue diseñada en 2015-2017 y se
nota. Rediseñarla es un trabajo aparte de hacerla funcionar.

## Desinstalación

```sh
./install.sh remove
```

Desregistra la interfaz y elimina los archivos del paquete. e2guardian y
`/usr/local/etc/e2guardian` quedan en su lugar; el script informa el comando
para quitarlos.

## Licencia

Apache-2.0. Copyright © 2015-2017 Marcello Coutinho; © 2026 los contribuyentes
de pfsense-packages-revived. Ver [LICENSE](LICENSE), que enumera los cambios
hechos al original tal como exige la Sección 4(b).

e2guardian es GPLv2 y no se distribuye acá: se instala desde el repositorio de
FreeBSD.
