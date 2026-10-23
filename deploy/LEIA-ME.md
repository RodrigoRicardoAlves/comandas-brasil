# Colocar o Comandas Brasil numa VPS

Testado no PC de desenvolvimento com `runserver`. Na VPS, use gunicorn + nginx (arquivos nesta pasta).
Exemplo para Debian/Ubuntu.

## 1. Pacotes e usuário
```bash
sudo apt install python3-venv python3-dev build-essential default-libmysqlclient-dev pkg-config mariadb-server nginx git
sudo useradd -r -m -d /srv/comandas comandas
sudo -u comandas git clone <repositório> /srv/comandas
```

## 2. Banco (MariaDB)
```sql
CREATE DATABASE bar CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'comandas'@'localhost' IDENTIFIED BY '<SENHA FORTE NOVA>';
GRANT ALL ON bar.* TO 'comandas'@'localhost';
```
Para levar os dados do PC: `mysqldump bar > bar.sql` no PC e `mysql bar < bar.sql` na VPS.

## 3. Configuração
Copie `.env.example` para `/srv/comandas/.env` e preencha: `SECRET_KEY` (nova, longa), `DEBUG=0`,
`HTTPS=1`, `ALLOWED_HOSTS=bar.rodrigoricardo.eng.br`, `CSRF_TRUSTED_ORIGINS=https://bar.rodrigoricardo.eng.br`,
dados do banco, `SITE_URL`, `CONTATO_EMAIL`.

## 4. Python e arquivos
```bash
cd /srv/comandas && python3 -m venv .venv && .venv/bin/pip install -r servidor/requirements.txt
cd servidor && ../.venv/bin/python manage.py migrate && ../.venv/bin/python manage.py collectstatic --noinput
../.venv/bin/python manage.py createsuperuser
```
Copie também `servidor/media/` (fotos do cardápio e o APK publicado) do PC.

## 5. Serviço e nginx
```bash
sudo cp deploy/comandas.service /etc/systemd/system/ && sudo systemctl enable --now comandas
sudo cp deploy/comandas-q.service /etc/systemd/system/ && sudo systemctl enable --now comandas-q   # tarefas agendadas
sudo cp deploy/nginx.conf /etc/nginx/sites-available/comandas && sudo ln -s ../sites-available/comandas /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```
HTTPS: aponte o túnel da Cloudflare para `http://localhost:80`, ou use `certbot --nginx`.

## 6. Publicar versões do app
No PC (onde está a chave de assinatura): suba `version:` em `app/pubspec.yaml`, rode `app/publicar.sh "novidades"`
e copie `servidor/media/app/` para a VPS. Os celulares avisam "Nova versão" sozinhos.

## Backup
- Banco: `mysqldump bar | gzip > bar-$(date +%F).sql.gz` diário (cron).
- **Chave de assinatura do app**: `~/chaves-comandas/` (jks + key.properties). Sem ela não dá para atualizar o
  app nos celulares nem na Play Store. Guarde cópia fora do computador.
