#!/usr/bin/env bash
# Instala o Comandas Brasil numa VPS Debian/Ubuntu, isolado de outros apps.
# Cria usuário e pasta próprios (/srv/comandas), serviços próprios (comandas, comandas-q),
# escolhe uma porta interna livre, cria o banco (sem apagar nada) e configura o nginx.
# Rode como root. Não sobrescreve um .env já existente.
#
# Uso:
#   DOMINIO=bar.rodrigoricardo.eng.br DB_SENHA='xxxxx' bash instalar-vps.sh
#
# Variáveis:
#   DOMINIO     (obrigatória)  domínio do site
#   DB_SENHA    (obrigatória)  senha do usuário MariaDB
#   DB_NOME     (comandas)     nome do banco a criar/usar
#   DB_USER     (camila)       usuário MariaDB
#   DB_HOST     (127.0.0.1)    host do banco
#   DB_PORT     (3306)         porta do banco
#   HTTPS_FRONT (cloudflare)   cloudflare = HTTPS pela Cloudflare (nginx em http:80);
#                              certbot    = certificado no próprio servidor
#   REPO        (GitHub)       repositório de origem
set -euo pipefail

DOMINIO="${DOMINIO:?defina DOMINIO=seu.dominio}"
DB_SENHA="${DB_SENHA:?defina DB_SENHA=...}"
DB_NOME="${DB_NOME:-comandas}"
DB_USER="${DB_USER:-camila}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
HTTPS_FRONT="${HTTPS_FRONT:-cloudflare}"
REPO="${REPO:-https://github.com/RodrigoRicardoAlves/comandas-brasil.git}"
DESTINO=/srv/comandas
USUARIO=comandas

[ "$(id -u)" = 0 ] || { echo "Rode como root (sudo)."; exit 1; }
command -v apt-get >/dev/null || { echo "Este script é para Debian/Ubuntu (apt)."; exit 1; }

echo "== Pacotes =="
apt-get update -y
apt-get install -y python3-venv python3-dev build-essential default-libmysqlclient-dev pkg-config nginx git

echo "== Porta interna livre (a partir de 8100) =="
porta=8100
while ss -ltn | awk '{print $4}' | sed 's/.*://' | grep -qx "$porta"; do porta=$((porta+1)); done
echo "   gunicorn vai usar 127.0.0.1:$porta"

echo "== Usuário e código =="
id -u "$USUARIO" >/dev/null 2>&1 || useradd -r -m -d "$DESTINO" "$USUARIO"
if [ -d "$DESTINO/.git" ]; then
  sudo -u "$USUARIO" git -C "$DESTINO" pull --ff-only
else
  sudo -u "$USUARIO" git clone "$REPO" "$DESTINO"
fi

echo "== Ambiente Python =="
[ -d "$DESTINO/.venv" ] || sudo -u "$USUARIO" python3 -m venv "$DESTINO/.venv"
sudo -u "$USUARIO" "$DESTINO/.venv/bin/pip" install --upgrade pip >/dev/null
sudo -u "$USUARIO" "$DESTINO/.venv/bin/pip" install -r "$DESTINO/servidor/requirements.txt"

echo "== Banco (cria se não existir; não apaga nada) =="
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NOME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_SENHA';
GRANT ALL PRIVILEGES ON \`$DB_NOME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "== .env =="
if [ -f "$DESTINO/.env" ]; then
  echo "   já existe, mantido."
else
  SECRET=$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')
  cat > "$DESTINO/.env" <<ENV
DATABASE_NAME=$DB_NOME
DATABASE_USER=$DB_USER
DATABASE_PASSWORD=$DB_SENHA
DATABASE_HOST=$DB_HOST
DATABASE_PORT=$DB_PORT
SECRET_KEY=$SECRET
DEBUG=0
HTTPS=1
ALLOWED_HOSTS=$DOMINIO,localhost,127.0.0.1
CSRF_TRUSTED_ORIGINS=https://$DOMINIO
SITE_URL=https://$DOMINIO
CONTATO_EMAIL=
ENV
  chown "$USUARIO:$USUARIO" "$DESTINO/.env"
  chmod 600 "$DESTINO/.env"
  echo "   criado com SECRET_KEY nova."
fi

echo "== Migrações e arquivos estáticos =="
sudo -u "$USUARIO" bash -c "cd '$DESTINO/servidor' && ../.venv/bin/python manage.py migrate --noinput && ../.venv/bin/python manage.py collectstatic --noinput"
sudo -u "$USUARIO" mkdir -p "$DESTINO/servidor/media/app"

echo "== Serviços systemd =="
sed "s#127.0.0.1:8100#127.0.0.1:$porta#" "$DESTINO/deploy/comandas.service" > /etc/systemd/system/comandas.service
cp "$DESTINO/deploy/comandas-q.service" /etc/systemd/system/comandas-q.service
systemctl daemon-reload
systemctl enable --now comandas comandas-q

echo "== nginx =="
tmp=$(mktemp)
sed -e "s#127.0.0.1:8100#127.0.0.1:$porta#" \
    -e "s#server_name bar.rodrigoricardo.eng.br;#server_name $DOMINIO;#" \
    "$DESTINO/deploy/nginx.conf" > "$tmp"
if [ "$HTTPS_FRONT" = "cloudflare" ]; then
  # a Cloudflare termina o HTTPS e fala http com o nginx: fixa o proto como https
  sed -i 's#X-Forwarded-Proto \$scheme;#X-Forwarded-Proto https;#' "$tmp"
fi
mv "$tmp" /etc/nginx/sites-available/comandas
ln -sf ../sites-available/comandas /etc/nginx/sites-enabled/comandas
nginx -t
systemctl reload nginx

echo
echo "== PRONTO =="
echo "gunicorn: 127.0.0.1:$porta  |  nginx: $DOMINIO (porta 80, HTTPS pela $HTTPS_FRONT)"
echo "Status:   systemctl status comandas --no-pager"
echo
echo "Faltam 2 passos manuais:"
echo "  1) Super admin:  sudo -u $USUARIO bash -c 'cd $DESTINO/servidor && ../.venv/bin/python manage.py createsuperuser'"
echo "  2) Copiar a pasta media/ do PC (APK publicado e fotos do cardápio):"
echo "     no PC:  rsync -av servidor/media/ root@<IP>:$DESTINO/servidor/media/ && chown -R $USUARIO:$USUARIO $DESTINO/servidor/media"
