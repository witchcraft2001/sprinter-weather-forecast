# Weather Forecast for Sprinter DSS

Первый этап программы прогноза погоды для Sprinter DSS. Текущая версия
проверяет настройку сети, выбирает UNET backend, загружает готовую DLL через
актуальный libman и выполняет `GETCAPS`, `STATUS`, `NETINIT`, `NETDONE`.

Получение и разбор прогноза, `AFNT320` и графический интерфейс будут добавлены
на следующих этапах.

## Зависимости

```sh
git submodule update --init --recursive
```

Для сборки нужны:

- `sjasmplus`;
- Python 3.10 или новее;
- `zip` для `make package`;
- `mtools` (`mformat`, `mcopy`, `mdir`) для `make image`.

Готовые `UNETESP.DLL` и `UNETRTL.DLL` берутся из закреплённых сабмодулей и
никогда не пересобираются этим проектом.

## Сборка

```sh
make
make test
make package
make image
```

Результаты:

- `build/WEATHER.EXE`;
- `distr/weather-forecast.zip`;
- `distr/weather-forecast.img`.

Перед запуском на Sprinter сеть должна быть поднята:

- ESP/Wi-Fi: `NETUP`, публикующий `NET=WIFI`;
- RTL8019A: `NETCFG -i`, затем `IFUP`, публикующие `NET=RTL`.

DLL должны лежать рядом с `WEATHER.EXE`. Актуальный libman также умеет
использовать текущий каталог как fallback.
