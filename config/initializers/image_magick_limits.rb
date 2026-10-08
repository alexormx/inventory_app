# frozen_string_literal: true

# Los dynos (web y worker) tienen 512 MB. Por defecto ImageMagick usa hasta
# 256 MiB de memoria y 512 MiB mapeados por imagen: una foto de teléfono de
# 12 MP llega a ~137 MB por proceso (y el worker procesa dos a la vez). Con
# estos topes ImageMagick pasa a disco al rebasarlos — unos 0.3 s más por foto
# — y el pico baja a ~43 MB. Se aplica a todo lo que procesa imágenes: la IA,
# la copia al catálogo y los análisis/variantes de ActiveStorage. Un valor ya
# definido en el entorno (config de Heroku) gana, para ajustarlo sin deploy.
ENV['MAGICK_MEMORY_LIMIT'] ||= '64MiB'
ENV['MAGICK_MAP_LIMIT'] ||= '128MiB'
