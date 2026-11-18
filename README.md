# GitHub Starter

Template de GitHub independiente del lenguaje. Incluye CI básico, revisión de
dependencias y escaneo de secretos, Dependabot para GitHub Actions, formularios
de issues, una plantilla de PR y releases con Release Please.

## 1. Publicar y marcar el template

Subí esta carpeta como raíz de un repositorio de GitHub y clonalo con un remote
`origin` en GitHub.com. Para configurar el repositorio necesitás Git, PowerShell
7, GitHub CLI autenticado y acceso de administración al destino.

Ejecutá primero la vista previa y verificá la cuenta, el repositorio, la
visibilidad y la rama que informa el script.

```powershell
./scripts/setup.ps1 -Repository OWNER/github-starter -MarkAsTemplate -SkipRuleset
./scripts/setup.ps1 -Repository OWNER/github-starter -MarkAsTemplate -SkipRuleset -Apply
```

`-Apply` guarda los cambios. El script habilita issues, configura squash como
método de merge y elimina las ramas de origen después de mergear. El título y
el cuerpo del PR se usan como valores predeterminados del squash commit.

## 2. Crear un proyecto y verificar sus checks

Usá **Use this template** en GitHub y cloná el nuevo repositorio. Abrí un PR de
prueba con un título como `feat: add project overview`. Verificá **Repository
checks**, **Conventional PR title** y **Secret scan**. Si el repositorio es
público, comprobá también **Dependency review**. Cambiá temporalmente el título
a uno inválido para comprobar que falle y restaurá el título válido.

El CI revisa espacios en el diff y la sintaxis de los archivos de configuración.
Agregá los comandos de build y test de tu proyecto al job **Repository checks**.
Agregá el ecosistema de tu proyecto a `.github/dependabot.yml` y habilitá
Dependabot alerts en **Settings → Advanced Security** si están disponibles.
Gitleaks analiza el historial Git y oculta los valores detectados en la salida.
Para análisis de código, configurá CodeQL cuando el lenguaje y el plan sean
compatibles.

## 3. Aplicar las reglas del proyecto

```powershell
./scripts/setup.ps1 -Repository OWNER/PROJECT -EnableReleasePlease
./scripts/setup.ps1 -Repository OWNER/PROJECT -EnableReleasePlease -Apply
```

En repositorios públicos el script crea un ruleset para la rama predeterminada.
Exige PR y checks de GitHub Actions, bloquea force pushes y borrado de la rama,
y permite a una persona mantener el proyecto sin una segunda aprobación.
Repetir el setup conserva un ruleset idéntico. Si el ruleset del template
se modificó manualmente, el script avisa antes de escribir. Usá
`-SkipRuleset` para configurar el resto mientras probás los checks.

En repositorios privados el script omite el ruleset y el workflow omite
Dependency Review para mantener compatibilidad con GitHub Free. CI, validación
de títulos, Gitleaks, Dependabot y Release Please siguen disponibles cuando la
cuenta permite ejecutar Actions.

## 4. Probar un release

`-EnableReleasePlease` habilita la opción de GitHub Actions para crear y aprobar
PRs. El workflow usa el token integrado con permisos de escritura acotados al
job de release. La política de la organización puede limitar esa opción.

Mergeá el PR de prueba conservando el título Conventional Commits. Release
Please abre un PR de release al detectar cambios publicables como `feat:` o
`fix:`. Si GitHub muestra **Approve workflows to run** en el PR automático,
aprobá la ejecución de los checks. Al mergear ese PR, Release Please crea el
tag y el GitHub Release, y las notas quedan en `CHANGELOG.md`. La estrategia
`simple` también mantiene un archivo `version.txt`.

La guía de contribución está en [CONTRIBUTING.md](CONTRIBUTING.md) y el canal de
reporte de vulnerabilidades en [SECURITY.md](SECURITY.md). Definí la licencia
del proyecto según corresponda.
