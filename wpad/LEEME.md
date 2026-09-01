# wpad — descubrimiento automático de proxy para pfSense

Sirve `wpad.dat` y `proxy.pac` desde el firewall, así los navegadores encuentran
el proxy solos en vez de configurarse uno por uno.

Revivido del [paquete wpad de Marcello Coutinho](https://github.com/marcelloc/Unofficial-pfSense-packages),
portado a pfSense CE 2.9 / PHP 8.5. Apache-2.0; ver [LICENSE](LICENSE).

## Por qué importa

Un proxy al que nadie llega no es un proxy. Squid, e2guardian y los paquetes de
reportes de este repositorio recién sirven cuando el tráfico pasa por ahí, y
lograrlo es o tocar cada navegador o publicar un archivo PAC. Esto lo publica.

Encadenado con [samba-ad](../samba-ad/), el resultado es una máquina que se
conecta a la red, descubre el proxy, se autentica con Kerberos y navega
filtrada — sin que nadie haya configurado ni tipeado nada.

## Qué instala

Ningún binario de ningún repositorio: levanta un segundo nginx chico, que
pfSense ya trae. Son seis archivos de configuración, una página y la definición
de privilegios.

```sh
./install.sh check      # dice qué haría; no cambia nada
./install.sh install
./install.sh remove
```

Aparece en **System → Package Manager** y el ícono de la papelera lo borra.

## Cómo se configura

**Services → WPAD.** Elegís interfaz y puerto donde escuchar, y cargás el
contenido del PAC. Puede servir un archivo estático o un script PHP (si el
contenido arranca con `<?php` se ejecuta, y `.pac`, `.dat` y `.da` también se
mapean al handler de PHP).

Después apuntás a los clientes, de cualquiera de las dos formas:

- **Opción 252 de DHCP** — `http://<firewall>/wpad.dat`, en las opciones
  avanzadas del servidor DHCP.
- **DNS** — un registro A `wpad` apuntando al firewall. Ojo que los navegadores
  se volvieron cada vez más desconfiados del WPAD por DNS; DHCP es más confiable.

## Advertencias

- Escucha en un puerto propio. El 80 del firewall puede estar ocupado por la
  redirección a la GUI — fijate antes de elegirlo.
- WPAD es, por diseño, confianza en el primer uso: cualquier cosa que pueda
  contestar DHCP o DNS en esa red puede mandar a los navegadores al proxy que se
  le antoje. Es una propiedad de WPAD, no de este paquete, pero conviene saberlo
  antes de desplegarlo en una red que no controlás.

## Estado

Instala, se registra y su pantalla carga en CE 2.9.0-RELEASE. **Todavía no
sirvió un PAC a un cliente real** — en [docs/VERIFY.md](docs/VERIFY.md) está
exactamente qué se probó y qué no.
