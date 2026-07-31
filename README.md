# Weather Forecast for Sprinter DSS

Программа прогноза погоды для Sprinter DSS. Она читает
необязательный `WEATHER.CFG`, выбирает UNET backend, получает и строго
разбирает потоковый WX1, затем показывает текущую погоду и прогноз на семь
дней через штатный текстовый вывод DSS.

Поддерживаются CRLF, CR и LF ответы WX1, но один ответ обязан использовать
только один тип окончания строки. `R`/Enter выполняют новый запрос с повторным
чтением CFG и `NET`; Esc завершает программу.

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
make weatherc
make console
make test
make package
make image
make debug-image
```

Результаты:

- `build/WEATHERC.EXE`;
- `distr/weather-forecast.zip`;
- `distr/weather-forecast.img`.
- `distr/weather-debug.img` — диагностический образ с test `WEATHER.CFG`.

Перед запуском на Sprinter сеть должна быть поднята:

- ESP/Wi-Fi: `NETUP`, публикующий `NET=WIFI`;
- RTL8019A: `NETCFG -i`, затем `IFUP`, публикующие `NET=RTL`.

DLL должны лежать рядом с `WEATHERC.EXE`. Актуальный libman также умеет
использовать текущий каталог как fallback.

`WEATHER.CFG` необязателен. Без него используется
`go.sprinter.ru:70/weather/zx`; пример для отладки находится в
`resources/WEATHER.CFG.sample`.

`WEATHER.EXE` — графическая версия 320×256. При запуске она считывает компактный
Hrust-хвост со встроенными ассетами в одну DSS-страницу и закрывает EXE. После
этого данные распаковываются в пять DSS-страниц; дальнейшая перерисовка не
зависит от диска. Для неё рядом с EXE нужны `AFNT320.DLL` и
`GFX320.DLL`.
`WEATHERC.EXE` остаётся самостоятельной текстовой версией. Обе программы
используют общий необязательный `WEATHER.CFG`.

Редактируемые исходники пиктограмм находятся в `resources/gfx/`: отдельно
`64×64` для текущей погоды и `32×32` для прогноза. Требования к PNG и палитре
описаны в `resources/gfx/README.md`.
