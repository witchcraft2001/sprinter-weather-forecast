# Weather Forecast для Sprinter DSS

Версия: 0.1.0. Автор: Dmitry Mikhalchenkov, FidoNet: 2:5030/1997.10.

## Назначение и состояние

Проект содержит два клиента одного Gopher/WX1 сервиса:

- `WEATHERC.EXE` — законченный текстовый клиент DSS;
- `WEATHER.EXE` — графический клиент `320×256×256` с `AFNT320.DLL` и
  `GFX320.DLL`.

Оба читают необязательный `WEATHER.CFG`, выбирают `UNETESP.DLL` при
`NET=WIFI` либо `UNETRTL.DLL` при `NET=RTL`, получают `/weather/zx`, строго
разбирают WX1 и безопасно очищают сеть, DLL и DSS-память при любом выходе.

## Сервис и WX1

Default: `go.sprinter.ru:70`, selector `/weather/zx`. Это Gopher, не HTTP:

```text
/weather/zx\r\n
/weather/zx<TAB>Almaty,KZ\r\n
```

`WEATHER.CFG` может переопределить `HOST`, `PORT`, `SELECTOR` и `LOCATION`
без пересборки. Строки WX1 допускают только один вид конца строки во всём
ответе: CRLF, CR или LF. Parser принимает поток произвольными chunks,
собирает временную модель и публикует `WeatherModel` лишь после валидной
последней строки `.`. Данные после неё — ошибка формата.

## Runtime-архитектура

`WEATHER.EXE` — PRELOAD EXE с двумя независимыми частями.

```text
Файл: EXE header | primary loader | WFG2 | resident runtime | Hrust streams

primary loader (#8100, временно)
  ├─ выводит текстовый баннер версии и автора
  ├─ копирует DSS PSP #8000–#80FF в новую страницу и читает runtime со смещения #0100
  ├─ выделяет пять страниц ассетов и одну scratch-страницу
  ├─ читает каждый Hrust stream в WIN3 при системной странице в WIN0
  ├─ на время DI включает целевую страницу в WIN0, распаковывает и восстанавливает WIN0
  ├─ освобождает scratch, закрывает EXE
  └─ trampoline из WIN1 включает runtime в WIN2 и передаёт A=asset block

resident runtime (#8100, новая страница WIN2)
  ├─ очищает BSS, сохраняет переданный asset block
  ├─ загружает GFX320/AFNT320 и сразу включает графический режим
  ├─ выполняет CFG/UNET/WX1 с графическими progress/error экранами
  └─ знает только готовые страницы ассетов, не WFG2/Hrust
```

Загрузчик находится в `src/weather_loader.asm`; Hrust включён только в него.
Основной клиент собирается из `src/weather.asm`/`src/weatherc.asm` с
`WEATHER_RUNTIME=1`; его стек снова `0x600` байт. `WIN1` принадлежит libman,
`WIN2` — resident-коду и стеку, `WIN3` — UNET/VRAM по текущей фазе, `WIN0` —
источнику GFX320 и временной цели распаковки.

`WFG2` содержит размер runtime и пять размеров Hrust streams. Каждый stream
ограничен одной DSS-страницей; они читаются и распаковываются по одному, без
зависимости от суммарного размера сжатого хвоста. После старта весь UI работает
исключительно из DSS-памяти и не обращается к диску.

## Графика и ресурсы

`resources/gfx/` — редактируемый источник ассетов, встраиваемых в EXE:

- `weather/64/` — 15 пиктограмм 64×64 для текущей погоды;
- `weather/32/` — независимые 32×32 варианты для карточек прогноза;
- `ui/` — вспомогательные 16×16 пиктограммы.

`tools/build_assets.py` преобразует PNG в индексированные тайловые страницы;
`tools/pack_hrust.py` упаковывает каждую страницу; `tools/pack_weather_exe.py`
собирает WFG2. Палитра, прозрачность `#FF` и правила редактирования описаны в
`resources/gfx/README.md`.

Текущий экран показывает заголовок, location/country, текущую температуру,
64×64 WMO icon и шесть 32×32 карточек с min/max. `R`/Enter выполняет полный
refresh с перечитыванием CFG и `NET`, Esc завершает программу. Палитра
включается fade-in, при выходе используется fade-out. Графический режим
включается до чтения CFG и загрузки UNET; подключение, отправка запроса,
ожидание ответа и все штатные ошибки показываются через AFNT320. При переходе
между сетевыми стадиями очищается и перерисовывается только строка состояния,
без полной очистки экрана. Текстовый
fallback допустим только при невозможности загрузить или запустить сам
GFX320/AFNT320.

## Модули

```text
src/
  weatherc.asm        общий runtime: ENV, UNET, cleanup, entry
  weather.asm         выбор графического runtime
  weather_loader.asm  PRELOAD loader, WFG2, Hrust и handoff
  config.asm          WEATHER.CFG
  transport.asm       Gopher TCP transport
  wx1.asm             streaming WX1 parser
  text_ui.asm         WEATHERC.EXE
  graphics_ui.asm     WEATHER.EXE layout поверх AFNT320/GFX320
resources/gfx/        редактируемые PNG
tools/                сборка, WFG2 packer, FAT/ZIP и harness
extern/               закреплённые ESP, RTL, libman, sprinter-libs
```

Готовые UNET DLL не пересобираются данным проектом. Локальных копий libman,
UNET ABI или исходников сетевых DLL нет.

## Сборка и проверки

```text
make             WEATHER.EXE и WEATHERC.EXE
make weather     только графический EXE и primary loader
make weatherc    только console EXE
make test        host checks, WX1 harness и Hrust round-trip harness
make package     ZIP с обоими EXE и четырьмя DLL
make image       distr/weather-forecast.img
```

Сборка проверяет DLL, EXE header, WFG2 размеры, границы runtime BSS/stack,
ресурсы PNG и отсутствие Hrust/debug-console кода в resident runtime. Hrust
harness проверяет распаковку пяти реальных потоков и восстановление SP.

## TODO

### Завершено

- [x] CFG, UNET ESP/RTL, Gopher transport, streaming WX1, text UI и cleanup.
- [x] `WEATHERC.EXE` и `WEATHER.EXE`, ZIP/FAT12-образ и host/Z80 harness.
- [x] AFNT320/GFX320, WMO tile mapping, PNG asset pipeline и fade UI.
- [x] WFG2 primary loader: runtime в отдельной WIN2 странице, Hrust только в
      loader, ассеты готовы до запуска сети.

### Следующий графический этап

- [ ] Согласовать и реализовать финальный макет: updated time, WMO text,
      feels-like, влажность, ветер, день недели/дата и precipitation на
      карточках, постоянная атрибуция Open-Meteo.
- [x] Добавить единый графический экран сетевой/CFG/parser/DLL ошибки и
      графические состояния подключения/запроса.
- [ ] Отретушировать PNG и проверить все 15 WMO семейств в 64×64 и 32×32.
- [ ] Проверить `R`/Enter после графического кадра на ESP и RTL.

### Release gate

- [ ] Проверить default и alternate `HOST`/`PORT`/`SELECTOR`/`LOCATION`.
- [ ] Прогнать ESP-AT 2.2.2 и RTL8019A в MAME и на реальном Sprinter:
      успех, timeout, early close, data lost, malformed WX1, DLL/CFG errors.
- [ ] Проверить 40/80 columns, CP866, запуск рядом с EXE и через `PATH`,
      повторный refresh и повторный запуск.
- [ ] Проверить ZIP и FAT12/FAT16 с обоими EXE и всеми DLL.
- [ ] Добавить hardware gate для PRELOAD loader: WFG2 read, пять распаковок,
      переход trampoline в WIN2 и последующий `R`/Enter.

## Ограничения

Нет HTTPS/HTTP, почасового прогноза, фонового обновления и прямого управления
ESP/RTL в обход UNET. Графический runtime не реализует собственный blitter и
не читает ассеты с диска после старта.
