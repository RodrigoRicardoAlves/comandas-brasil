"""Configurações do servidor. Tudo que é segredo ou muda por ambiente vem do .env."""
import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR.parent / '.env')


def env(nome, padrao=''):
    return os.environ.get(nome, padrao)


def env_lista(nome, padrao=''):
    return [x.strip() for x in env(nome, padrao).split(',') if x.strip()]


SECRET_KEY = env('SECRET_KEY', 'dev-inseguro')
DEBUG = env('DEBUG', '0') == '1'
ALLOWED_HOSTS = env_lista('ALLOWED_HOSTS', 'localhost,127.0.0.1')
CSRF_TRUSTED_ORIGINS = env_lista('CSRF_TRUSTED_ORIGINS')
# atrás do túnel da Cloudflare o acesso chega como HTTPS
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'bares',
    'contas',
    'cardapio',
    'comandas',
    'publico',
    'painel',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': env('DATABASE_NAME', 'bar'),
        'USER': env('DATABASE_USER'),
        'PASSWORD': env('DATABASE_PASSWORD'),
        'HOST': env('DATABASE_HOST', '127.0.0.1'),
        'PORT': env('DATABASE_PORT', '3306'),
        'OPTIONS': {'charset': 'utf8mb4'},
        'TEST': {'CHARSET': 'utf8mb4', 'COLLATION': 'utf8mb4_unicode_ci'},
    }
}

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
]

LANGUAGE_CODE = 'pt-br'
TIME_ZONE = 'America/Sao_Paulo'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
MEDIA_URL = 'media/'
MEDIA_ROOT = BASE_DIR / 'media'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# endereço público (vai no QR Code do cardápio)
SITE_URL = env('SITE_URL', 'https://bar.rodrigoricardo.eng.br').rstrip('/')

# o "dia de expediente" vai das 06:00 às 05:59 do dia seguinte
INICIO_EXPEDIENTE = 6
