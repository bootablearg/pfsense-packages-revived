# Sarg Reports

Squid Analysis Report Generator para **pfSense CE 2.9 / Plus 26.x**: reportes
detallados de navegación por usuario, sitio, fecha y volumen descargado.

*[English version: README.md](README.md)*

Revivido del paquete sarg de
[Unofficial-pfSense-packages](https://github.com/marcelloc/Unofficial-pfSense-packages).
Este llegó a ser parte de pfSense en su momento — de ahí el copyright de ESF,
LLC (Electric Sheep Fencing, la empresa detrás de pfSense antes de Netgate).

## ¿Sarg o SquidAnalyzer?

Los dos leen el log de acceso de Squid y los dos están en este repositorio. Se
superponen, así que conviene elegir uno en lugar de correr ambos:

| | Sarg | SquidAnalyzer |
|---|---|---|
| Reportes | muy detallados, muchos cortes, programables | más livianos, orientados a gráficos |
| Tamaño | 17 MiB | 11 MiB |
| Programación | pestaña de agenda propia | cron |

Sarg es el más minucioso; SquidAnalyzer se lee más fácil de un vistazo. Ninguno
es mejor en abstracto.

Ambos ganan muchísimo si el proxy autentica contra Active Directory (ver
[samba-ad](../samba-ad/)): reportes por **nombre de usuario del dominio** en
lugar de por IP, que en una red con DHCP es lo que los vuelve utilizables.

## Estado

| Verificado | Sin verificar todavía |
|---|---|
| Se instala desde el repositorio de FreeBSD: **17 MiB**, 0 CVEs conocidos | Los reportes vistos en un navegador |
| Los 5 XML del paquete parsean con el parser propio de pfSense | Generación de reportes con tráfico real |
| `sarg.inc` (662 líneas) carga limpio bajo **PHP 8.5** | El programador a lo largo del tiempo |
| El generador de configuración corre y escribe su config | pfSense Plus |

El PHP y el XML del paquete van **sin modificar**: ya eran compatibles. Sólo se
agregaron el instalador y la documentación.

## Instalación

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/sarg/install.sh | sh -s check
```

`check` no modifica nada. Después `| sh -s install`, y abrir **Status → Sarg
Reports**.

## Requisitos

Squid instalado y registrando. `check` avisa si falta.

## Desinstalación

```sh
./install.sh remove
```

## Licencia

BSD 2-Clause. Ver [LICENSE](LICENSE) para las atribuciones y la lista de
cambios. Sarg es GPLv2 y se instala desde el repositorio de FreeBSD.
