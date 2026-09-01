# speedtest — medición de ancho de banda desde el firewall

Mide bajada, subida y latencia desde el propio firewall, eligiendo con qué
dirección de origen probar.

Revivido del [paquete speedtest de Marcello Coutinho](https://github.com/marcelloc/Unofficial-pfSense-packages),
portado a pfSense CE 2.9 / PHP 8.5. Apache-2.0 y BSD-2-Clause; ver
[LICENSE](LICENSE).

## Por qué medir acá

Una medición hecha en una PC no distingue "el enlace WAN está lento" de "el
camino entre este escritorio y el firewall está lento". Medir en el borde
contesta lo primero directamente, y el selector de origen permite probar por una
WAN específica en un equipo con varias.

## Qué instala

`speedtest-cli`, que viene del **repositorio propio de pfSense** — no de un
tercero. Unos 100 KiB de descarga.

```sh
./install.sh check      # dice qué haría; no cambia nada
./install.sh install
./install.sh remove
```

Después: **Diagnostics → SpeedTest**.

## El resultado se queda acá

El original pasaba `--share` en cada corrida y mostraba el resultado como nada
más que la imagen que devuelve Ookla. Eso significaba que **no se podía medir
sin publicar**: `speedtest-cli --share` sube la medición a Ookla, que la aloja
en una URL pública junto con el ISP y la ubicación aproximada que deducen de tu
dirección pública, y después el navegador del administrador iba a buscar esa
imagen a speedtest.net.

Acá los números se leen del JSON y se muestran localmente, y **Publish result**
es una casilla que viene desactivada. Si la marcás, además obtenés el link
público, validado y escapado en vez de metido crudo en un `<img src>`.

## Advertencias

- La medición en sí contacta la lista de servidores de speedtest.net y un
  servidor cercano. Eso es inevitable para este tipo de prueba, y es todo el
  tráfico que genera la página con el compartir apagado.
- Una medición satura el enlace mientras dura. No la corras en un firewall de
  producción ocupado esperando que el número signifique algo, ni que los
  usuarios se pongan contentos.

## Estado

**Verificado en CE 2.9.0-RELEASE**: corre una medición real, el JSON parsea y el
panel de resultados lo muestra. Ver [docs/VERIFY.md](docs/VERIFY.md).
