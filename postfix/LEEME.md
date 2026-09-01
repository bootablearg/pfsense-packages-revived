# Postfix Forwarder

Pasarela y reenviador de correo: acepta SMTP, aplica antispam y políticas de acceso, y retransmite al servidor de correo real. Para **pfSense CE 2.9 / Plus 26.x**.

*[English version: README.md](README.md)*

Revivido del paquete postfix de
[Unofficial-pfSense-packages](https://github.com/marcelloc/Unofficial-pfSense-packages)
(Apache-2.0, Marcello Coutinho). El binario sale del repositorio oficial de
FreeBSD.

## Estado — leer antes de instalar

**Este paquete está menos probado que los demás de este repositorio.** Se
verificó que su código es compatible y que el instalador resuelve el paquete,
pero **no se ejecutó de punta a punta en un sistema real**. Tomalo como punto
de partida, no como un despliegue terminado.

| Verificado | Sin verificar |
|---|---|
| Disponible en el repositorio de FreeBSD para esta ABI; el plan de instalación resuelve | Instalado y funcionando en un equipo real |
| Todos los `.inc` pasan `php -l` con **PHP 8.5** | Correo realmente procesado |
| Todos los XML parsean con el parser propio de pfSense | Las pantallas en un navegador |
| El instalador pasa la verificación de sintaxis | pfSense Plus |

El PHP y el XML del paquete van **sin modificar**: ya eran compatibles. Sólo se
agregaron el instalador y la documentación.

## Instalación

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/postfix/install.sh | sh -s check
```

`check` no modifica nada e informa exactamente qué se instalaría. Después
`| sh -s install`, y abrir **Services → Postfix Forwarder**.

## Desinstalación

```sh
./install.sh remove
```

## Licencia

Apache-2.0. Ver [LICENSE](LICENSE) para las atribuciones y la lista de cambios.
