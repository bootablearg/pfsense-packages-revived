# ipguard — mantener equipos desconocidos afuera de la LAN

Impone una lista de pares MAC/IP en un segmento de red. Lo que no está en la
lista queda sin poder comunicarse.

Revivido del [paquete ipguard de Marcello Coutinho](https://github.com/marcelloc/Unofficial-pfSense-packages),
portado a pfSense CE 2.9 / PHP 8.5. BSD-2-Clause; ver [LICENSE](LICENSE).

## Leé esto antes de instalarlo

**ipguard funciona haciendo ARP spoofing.** Vigila el segmento y contesta los
ARP de direcciones que no están en su lista con respuestas falsas, así los
equipos no autorizados no llegan a ningún lado. Ese es el mecanismo, y trae
consecuencias:

- Un equipo que te olvidás de cargar **se queda sin red**, sin ningún mensaje
  de error que apunte al firewall. Impresoras, teléfonos IP, dispositivos IoT y
  cualquier cosa con MAC aleatoria son las víctimas típicas.
- Es una barrera de molestia, no un control de seguridad. Quien pueda fijarse su
  propia MAC e IP copia un par permitido y pasa igual. Tomalo como orden, no
  como autenticación.
- Si querés control real a nivel de puerto, la respuesta es 802.1X en el switch.
  Esto existe para redes cuyos switches no pueden.

Arrancá con dos equipos de prueba, no con toda la oficina.

## Qué instala

`ipguard` del repositorio de FreeBSD, más la GUI. Corre un daemon por cada
interfaz configurada.

```sh
./install.sh check      # dice qué haría; no cambia nada
./install.sh install
./install.sh remove
```

Después: **Firewall → IPguard**. Una entrada por equipo permitido: interfaz,
MAC, IP y descripción. El daemon arranca cuando hay al menos una entrada
habilitada, y para cuando no queda ninguna.

Los logs van a `/var/log/ipguard_<interfaz>.log`.

## Lo que se arregló al portarlo

El paquete tal como estaba publicado **no se podía instalar** en pfSense 2.9. Su
comando de resync corre al instalar, cuando todavía no hay configuración, y
llegaba a `count()` con una variable indefinida:

```
count(): Argument #1 ($value) must be of type Countable|array, null given
```

PHP 7 contaba null como cero y seguía; PHP 8 lo hace fatal. `php -l` no lo ve:
el archivo parsea perfecto y sólo muere al ejecutarse.

Dos más, estos de lógica original y no de versión de PHP:

- Que el daemon arrancara dependía de `$ipguard['enable']` que quedaba colgado
  del `foreach` anterior — o sea, de **la última entrada de la lista**. Una
  entrada deshabilitada al final dejaba el servicio abajo sin importar lo que
  hubiera arriba.
- Cada archivo de configuración se escribía dos veces con el mismo contenido.

También se sacó el workaround de PBI para pfSense 2.2: PBI se retiró en 2016 y
`/usr/pbi` no existe en ninguna versión soportada.

## Estado

Instala y se registra en CE 2.9.0-RELEASE, y el camino de instalación que
crasheaba ahora termina bien. **Ningún equipo fue bloqueado ni permitido por él
todavía** — ver [docs/VERIFY.md](docs/VERIFY.md).
