# SquidAnalyzer

Reportes por usuario a partir del log de acceso de Squid, para **pfSense CE 2.9
/ Plus 26.x**.

*[English version: README.md](README.md)*

Revivido del paquete squidanalyzer de
[Unofficial-pfSense-packages](https://github.com/marcelloc/Unofficial-pfSense-packages)
(Apache-2.0, Luiz Gustavo y Marcello Coutinho). El binario sale del repositorio
oficial de FreeBSD.

## Por qué combina con samba-ad

Squid registra por IP del cliente. En una red con DHCP eso vuelve los reportes
casi inútiles: la misma dirección es otra persona la semana que viene. Cuando
el proxy autentica contra Active Directory (ver [samba-ad](../samba-ad/)),
SquidAnalyzer reporta **por nombre de usuario del dominio**, y los números
empiezan a significar algo.

## Estado

| Verificado | Sin verificar todavía |
|---|---|
| Se instala desde el repositorio de FreeBSD: **11 MiB**, 0 CVEs conocidos | Los reportes vistos en un navegador |
| Todos los XML del paquete parsean con el parser propio de pfSense | Generación de reportes con tráfico real |
| `squidanalyzer.inc` carga limpio bajo **PHP 8.5** | El cron a lo largo del tiempo |
| El generador de configuración corre; el menú se registra en Status | pfSense Plus |

El PHP y el XML del paquete van **sin modificar**: ya eran compatibles. Sólo se
agregaron el instalador y la documentación.

## Instalación

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/squidanalyzer/install.sh | sh -s check
```

`check` no modifica nada. Después `| sh -s install`, y abrir **Status →
SquidAnalyzer**.

Los reportes los genera un cron a partir del log de Squid, así que no aparece
nada hasta que Squid haya registrado tráfico y el trabajo haya corrido al menos
una vez.

## Requisitos

Squid instalado y registrando. Sin eso no hay log que analizar — `check` avisa.

## Desinstalación

```sh
./install.sh remove
```

## Licencia

Apache-2.0. Ver [LICENSE](LICENSE) para las atribuciones y la lista de cambios.
SquidAnalyzer es GPLv3 y se instala desde el repositorio de FreeBSD.
