# Generated by Django 4.0.5 on 2022-06-18 17:48

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('music_room', '0001_initial'),
    ]

    operations = [
        migrations.AlterField(
            model_name='track',
            name='name',
            field=models.CharField(max_length=150, unique=True),
        ),
    ]