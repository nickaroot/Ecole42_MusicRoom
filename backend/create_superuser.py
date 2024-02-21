#!/usr/bin/python3

import os

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "django_app.settings")

import django

django.setup()

from django.contrib.auth import get_user_model

User = get_user_model()

try:
    User.objects.create_superuser(os.getenv('SUPERADMIN_USERNAME'), os.getenv('SUPERADMIN_EMAIL'), os.getenv('SUPERADMIN_PASSWORD'))
except Exception:
    pass
