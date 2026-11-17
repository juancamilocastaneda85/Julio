#!/data/data/com.termux/files/usr/bin/bash
# Corre como root. Usa las herramientas de Termux (magick, potrace, aapt2, apksigner).
# Uso: fpicon.sh imagen [niveles_de_gris]
set -e
IMG="$1"
NCOL="${2:-5}"      # niveles de gris (sombras)
H=/data/data/com.termux/files/home
W="${FPWORK:-/data/local/tmp/fpwork}"

[ -f "$IMG" ] || { echo "Falta la imagen"; exit 1; }
if [ -z "$DRYRUN" ]; then
  [ -f "$H/framework-res.apk" ] || { echo "Falta $H/framework-res.apk"; exit 1; }
  [ -f "$H/rro.keystore" ] || { echo "Falta $H/rro.keystore"; exit 1; }
fi

# Dibujo cuadrado (65x65) para aprovechar todo el espacio del icono

rm -rf "$W"; mkdir -p "$W/res/drawable" "$W/res/drawable-v21"; cd "$W"

# Color del fondo de la foto (esquina superior izquierda): se vuelve transparente
BG=$(magick "$IMG" -alpha off -format '%[pixel:p{0,0}]' info:)

for S in 400 300 200 150; do
  H2=$S
  case $S in
    400) SC=0.01625;; 300) SC=0.021667;; 200) SC=0.0325;; 150) SC=0.043333;;
  esac
  # Android pinta el icono de un solo color, pero respeta la transparencia:
  # los grises se guardan como niveles de transparencia (sombras)
  magick "$IMG" -alpha off -resize ${S}x${H2} -background "$BG" -gravity center -extent ${S}x${H2} -colorspace Gray -normalize +dither -colors "$NCOL" -type TrueColor q.png
  BGHEX=$(magick q.png -format '%[hex:p{0,0}]' info: | tr a-f A-F | cut -c1-6)
  : > body.txt
  for C in $(magick q.png -unique-colors txt:- | grep -o '#[0-9A-Fa-f]\{6\}' | tr a-f A-F | sort -u); do
    HEX=${C#\#}
    [ "$HEX" = "$BGHEX" ] && continue
    LUM=$((16#${HEX:0:2}))
    AL=$(printf '%02X' $(( 150 + LUM*105/255 )))
    magick q.png -fuzz 0% -transparent "$C" -alpha extract -threshold 50% m.pbm
    potrace -s -t 4 -O 0.5 m.pbm -o m.svg
    sed -n '/<path/,$p' m.svg | tr '\n' ' ' \
      | sed "s/<path d=\"/<path android:fillColor=\"#${AL}FFFFFF\" android:pathData=\"/g; s/\" *\/>/\"\/>\n/g" \
      | grep '<path' >> body.txt || true
  done
  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo "<vector xmlns:android=\"http://schemas.android.com/apk/res/android\" android:width=\"65dp\" android:height=\"65dp\" android:viewportWidth=\"65\" android:viewportHeight=\"65\"><group android:translateY=\"65\" android:scaleX=\"$SC\" android:scaleY=\"-$SC\">"
    cat body.txt
    echo '</group></vector>'
  } > ic.xml
  SIZE=$(wc -c < ic.xml)
  echo "Intento ${S}px, ${NCOL} niveles -> ${SIZE} bytes"
  [ "$SIZE" -le 50000 ] && break
done
[ -s body.txt ] || { echo "No se genero ningun trazo. Prueba otra foto."; exit 1; }
[ "$SIZE" -le 70000 ] || { echo "Imagen demasiado compleja. Usa una mas simple."; exit 1; }

if [ -n "$DRYRUN" ]; then echo "DRYRUN: ic.xml listo en $W"; exit 0; fi

for d in drawable drawable-v21; do
  cp ic.xml res/$d/ic_fingerprint.xml
  cp ic.xml res/$d/cat_icon.xml
done
for n in unlock_to_fp fp_to_locked fp_to_unlock; do
  printf '<?xml version="1.0" encoding="utf-8"?>\n<animated-vector xmlns:android="http://schemas.android.com/apk/res/android" android:drawable="@drawable/cat_icon"/>\n' > res/drawable/$n.xml
done
# Quita el circulo oscuro del fondo
printf '<?xml version="1.0" encoding="utf-8"?>\n<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval"><solid android:color="#00000000"/></shape>\n' > res/drawable/fingerprint_bg.xml

printf '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.custom.fpicon">\n<overlay android:targetPackage="com.android.systemui" android:isStatic="true" android:priority="99"/>\n<application android:hasCode="false"/>\n</manifest>\n' > AndroidManifest.xml

aapt2 compile --dir res -o res.zip
aapt2 link -o un.apk -I "$H/framework-res.apk" --manifest AndroidManifest.xml res.zip
apksigner sign --ks "$H/rro.keystore" --ks-pass pass:123456 --out FpIconOverlay.apk un.apk

mount -o rw,remount /product || true
cp FpIconOverlay.apk /product/overlay/FpIconOverlay.apk
chmod 644 /product/overlay/FpIconOverlay.apk
chcon u:object_r:system_file:s0 /product/overlay/FpIconOverlay.apk
echo "Dibujo cuadrado 65x65 listo"
echo "LISTO. Reinicia el telefono."
