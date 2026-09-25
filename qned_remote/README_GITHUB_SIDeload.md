# Compilar y probar en iPhone desde Windows, sin Mac local

1. Sube este proyecto a un repositorio de GitHub.
2. Puedes usar un repositorio PUBLICO para que GitHub Actions use el runner macOS sin costo adicional. No hay secretos en este proyecto.
3. En GitHub entra a Actions > Build iOS IPA (unsigned) > Run workflow.
4. Espera a que termine el job y descarga el artefacto `qned-remote-ios-unsigned`.
5. Dentro estará el archivo `.ipa`.
6. En Windows instala Sideloadly y usa tu Apple ID gratuito para firmar e instalar el IPA en tu iPhone.
7. El certificado gratuito normalmente dura 7 días; vuelve a instalar/refrescar al vencer.

Nota: el IPA generado por este workflow es deliberadamente SIN firma. Sideloadly lo firma para tu dispositivo durante la instalación.
