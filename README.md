# Weather Forecast for Sprinter DSS

Второй этап программы прогноза погоды для Sprinter DSS. Текущая версия читает
необязательный `WEATHER.CFG`, выбирает UNET backend, загружает готовую DLL,
отправляет Gopher selector и получает полный сырой ответ WX1.

Разбор WX1 в модель прогноза, `AFNT320` и графический интерфейс будут добавлены
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
make debug-image
```

Результаты:

- `build/WEATHER.EXE`;
- `distr/weather-forecast.zip`;
- `distr/weather-forecast.img`.
- `distr/weather-debug.img` — тестовый образ с координатами и выводом raw WX1.

Перед запуском на Sprinter сеть должна быть поднята:

- ESP/Wi-Fi: `NETUP`, публикующий `NET=WIFI`;
- RTL8019A: `NETCFG -i`, затем `IFUP`, публикующие `NET=RTL`.

DLL должны лежать рядом с `WEATHER.EXE`. Актуальный libman также умеет
использовать текущий каталог как fallback.

`WEATHER.CFG` необязателен. Без него используется
`go.sprinter.ru:70/weather/zx`; пример для отладки находится в
`resources/WEATHER.CFG.sample`.
