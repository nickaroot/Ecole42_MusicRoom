# Generated by Django 3.2.15 on 2024-02-20 23:26

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('music_room', '0069_alter_playlist_name'),
    ]

    operations = [
        migrations.AlterField(
            model_name='playlist',
            name='name',
            field=models.CharField(default='<function uuid4 at 0x7f661fb9efc0>', max_length=150),
        ),
    ]
