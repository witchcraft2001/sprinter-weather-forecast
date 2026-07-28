# Weather Forecast для Sprinter DSS

## 1. Цель и текущий milestone

Итоговая цель — пользовательская программа `WEATHER.EXE` для Sprinter DSS,
которая:

- получает текстовый прогноз по Gopher с `go.sprinter.ru:70`, selector
  `/weather/zx`;
- во время исполнения выбирает сетевой backend по окружению DSS:
  `NET=WIFI` — `UNETESP.DLL`, `NET=RTL` — `UNETRTL.DLL`;
- разбирает компактный протокол `WX1`;
- допускает смену сервера и selector без пересборки через необязательный
  `WEATHER.CFG`;
- корректно закрывает соединение, выгружает DLL и освобождает ресурсы при
  успехе, ошибке и отмене пользователем.

Завершённый первый milestone — сетевой bootstrap программы. Он проходит путь
«чтение `NET` → выбор UNET backend → загрузка DLL → проверка ABI/TCP →
`STATUS`/`NETINIT` → безопасный `NETDONE`/выгрузка» и выводит в штатном
текстовом режиме DSS результат либо понятную ошибку с диагностикой.

Следующий milestone добавит Gopher-запрос, streaming parser `WX1` и вывод
нормализованной модели. Эти части не входят в первый milestone.

Графический интерфейс отложен. В дальнейшем он будет использовать
`AFNT320.DLL` и отдельную библиотеку-blitter из Git-сабмодуля
`git@github.com:witchcraft2001/sprinter-libs.git`, но текущий milestone эти DLL
не загружает и от их незавершённого ABI не зависит.

Название исполняемого файла и конфигурации укладывается в формат DSS/FAT 8.3:
`WEATHER.EXE`, `WEATHER.CFG`.

## 2. Границы milestones

В завершённый первый milestone входят:

- загрузка `UNETESP.DLL` или `UNETRTL.DLL` по значению `NET`;
- проверка L1 DLL через актуальный libman;
- проверка UNET ABI major 1 и `UNET_CAP_TCP`;
- `STATUS`, `NETINIT`, `NETDONE` и выгрузка DLL;
- понятные подсказки для `NETUP` и `NETCFG -i`/`IFUP`;
- русские пользовательские сообщения в CP866;
- Makefile, host-проверки, ZIP и тестовый FAT12-образ.

В последующий текстовый MVP войдут:

- Gopher-запрос к настраиваемому host/port/selector;
- строгий streaming parser `WX1`;
- вывод location, текущих условий, всех дневных записей и атрибуции через
  текстовые функции DSS;
- вывод стадии сбоя, понятного сообщения, UNET status и безопасно обрезанного
  `LASTERR`;
- повтор запроса по `R`/`Enter` и выход по `Esc`;
- необязательное явное местоположение из конфигурации;
- работа как с ESP/Wi-Fi, так и с RTL8019A через единый UNET ABI.

Не входят в первый milestone:

- `WEATHER.CFG`, TCP-соединение и запрос к погодному сервису;
- parser `WX1`, модель прогноза, retry и интерактивный цикл;
- графический режим `320×256×256`;
- `AFNT320.DLL`, библиотека-blitter, VRAM, акселератор и double buffering;
- погодные пиктограммы, palette, converter и resource pack;
- primary-loader для графических ресурсов;
- редактор конфигурации внутри программы;
- HTTPS и HTTP;
- почасовой прогноз;
- фоновая служба и автоматическое обновление после выхода из программы;
- прямое управление ESP-AT или RTL8019A в обход UNET DLL.

## 3. Проверенные исходные данные

### 3.1. Сервис и протокол

Источник:

- `/Users/dmitry/dev/zx/gopher-gate/docs/weather-gateway.md`;
- `/Users/dmitry/dev/zx/gopher-gate/internal/gates/weather/zx.go`;
- `/Users/dmitry/dev/zx/gopher-gate/internal/gates/weather/gateway.go`;
- `/Users/dmitry/dev/zx/gopher-gate/internal/gates/weather/gateway_test.go`.

Запрос — не HTTP. После TCP connect нужно передать Gopher selector:

```text
/weather/zx\r\n
```

Если в конфигурации задано местоположение:

```text
/weather/zx<TAB>Almaty,KZ\r\n
```

или, предпочтительно для независимости от кодировки:

```text
/weather/zx<TAB>43.2389,76.8897\r\n
```

Успешный ответ имеет строки с CRLF. Текстовые поля закодированы в CP866,
числа и имена записей — ASCII:

```text
WX1|OK|7
L|Алматы|KZ
N|20260727T1430|235|241|63|2|117|230
D|20260727|164|257|61|40|153
...
A|Open-Meteo.com|https://open-meteo.com/
.
```

Смысл полей:

| Запись | Поля |
|---|---|
| `WX1|OK|n` | версия, статус и число дневных записей |
| `L|name|cc` | название места в CP866 и двухбуквенный код страны |
| `N|time|t|feels|humidity|code|wind|direction` | текущее время, температура и ощущаемая температура в десятых °C, влажность %, WMO-код, ветер в десятых м/с, направление в градусах |
| `D|date|min|max|code|precip|wind` | дата, минимум/максимум в десятых °C, WMO-код, вероятность осадков %, максимальный ветер в десятых м/с |
| `A|...` | обязательная атрибуция источника |
| `.` | конец сообщения |

Ошибка сервиса:

```text
WX1|ERR|0
E|GEO_UNAVAILABLE
.
```

Поддерживаемые коды: `BAD_LOCATION`, `LOCATION_NOT_FOUND`,
`GEO_UNAVAILABLE`, `WEATHER_UNAVAILABLE`.

### 3.2. Сетевой ABI

Источники:

- `/Users/dmitry/dev/zx/sprinter/sprinter_wifi/network/docs/UNETAPI.md`;
- `/Users/dmitry/dev/zx/sprinter/sprinter_wifi/network/src/include/unet.inc`;
- `/Users/dmitry/dev/zx/sprinter/sprinter_wifi/network/src/dll/unetesp.asm`;
- `/Users/dmitry/dev/zx/sprinter/sprinter-rtl8019a/docs/UNETRTL.md`;
- `/Users/dmitry/dev/zx/sprinter/sprinter-rtl8019a/src/dll/unetrtl.asm`;
- оба варианта `src/apps/unettest.asm`.

Программа использует только единый UNET ABI:

1. `GETCAPS`;
2. `SETOPT(CANCELKEYS=1)`;
3. `STATUS(0xFF)`;
4. `NETINIT`;
5. `CONNECT`;
6. `SEND`;
7. цикл `RECV`;
8. `CLOSE`;
9. `NETDONE`.

Критические ограничения ABI:

- сетевую DLL загружать через `libman 1.3` в окно 1 (`0x4000`);
- не загружать сетевую DLL в окно 3: оба backend используют его для ISA;
- код программы размещать в окне 2 с `ORG 0x8100`;
- все строки и сетевые буферы держать ниже `0xC000`, в окне программы, вне
  окна DLL;
- проверять статус UNET в `A`, а не carry;
- проверить ABI major `1` и capability `UNET_CAP_TCP`;
- `RECV: A=0, DE=0` означает таймаут опроса, но не конец файла;
- `NERR_CLOSED` означает закрытие peer;
- бит 2 флагов `RECV` означает потерю данных и должен приводить к ошибке
  передачи, а не к попытке разобрать повреждённый прогноз;
- при `UNET_CAP_RXFLOW` медленный вывод/дисковые операции во время приёма
  оборачивать в `RXPAUSE`/`RXRESUME`. Текстовый MVP вообще не вызывает
  `PCHARS` в активном цикле `RECV`.

`UNETESP.DLL` в текущем проекте требует сессию `NETUP` с
`NET_ESP_FW=2.2.2`. При другом профиле нужно показать понятное сообщение, а не
пытаться перенастроить ESP.

### 3.3. Выбор backend

Окружение читается через DSS `ENVIRON #46`, подфункцию `ENV_GET #01`:
`HL` — имя, `DE` — буфер, `A=0xFF` — значение найдено.

Алгоритм:

| Значение `NET` | Библиотека | Подсказка при отсутствии настройки |
|---|---|---|
| `WIFI` | `UNETESP.DLL` | запустить `NETUP` |
| `RTL` | `UNETRTL.DLL` | запустить `NETCFG -i`, затем `IFUP` |
| отсутствует/другое | не загружать DLL | показать обе допустимые команды |

Программа не должна молча пробовать обе DLL: при одновременно установленном
оборудовании это даст непредсказуемый выбор.

### 3.4. Libman и размещение DLL

Используется актуальный исходник
`extern/libman/libman/libman.asm` из закреплённого сабмодуля. Исторические
копии `libman13.asm` из сетевых проектов не используются.

Приложение передаёт `LIBMAN.l_load` короткое имя DLL. Libman сам:

1. получает каталог `WEATHER.EXE` через DSS `APPINFO #47`;
2. пробует `<exe-dir>\<name>.DLL`;
3. при ошибке открытия пробует имя относительно текущего каталога.

Конфигурация include: `LIBMAN_MAX_LIBS=1`, `LIBMAN_NO_LEGACY_API`.

Сетевую DLL загружать в окно 1. Жизненный цикл текстового MVP:

1. загрузить выбранную UNET DLL;
2. получить и разобрать прогноз;
3. выполнить `CLOSE`, `NETDONE`, `l_free`;
4. вывести `WeatherModel` или сохранённую ошибку через DSS `PCHARS`;
5. повторить запрос либо завершить программу.

### 3.5. Закреплённые сабмодули

| Каталог | Репозиторий | Коммит |
|---|---|---|
| `extern/esp_net` | `git@github.com:witchcraft2001/sprinter_net.git` | `019dbfeb8bbb38b6681d5a2634078057d24e4b0e` |
| `extern/rtl_net` | `git@github.com:witchcraft2001/sprinter-rtl8019a.git` | `68c6d45ab23899dfa3da4a9b594b3de9fb7f2c43` |
| `extern/libman` | `git@github.com:witchcraft2001/sprinter-libman.git` | `18bc17b75400ebea60fdd2f68b8bc4476ef8254f` |
| `extern/sprinter-libs` | `git@github.com:witchcraft2001/sprinter-libs.git` | `169f515f4d5a8142eab1b8783146f7388b7dba74` |

Готовые runtime-библиотеки берутся из корней сетевых сабмодулей:

| Файл | Размер | SHA-256 |
|---|---:|---|
| `extern/esp_net/UNETESP.DLL` | 10 720 | `f03352df4f4af42683d1fde4a8260d0bd3a55f51b1366f10b5467b38566e9abc` |
| `extern/rtl_net/UNETRTL.DLL` | 13 651 | `051e53b1a4c10f3a41ddad8ad3f26dd974786ebd821c17f8202fb2d91b702fb1` |

Правила зависимости:

- `.gitmodules` содержит SSH URL всех четырёх сабмодулей;
- сборка выполняется с закреплённым commit сабмодуля, а не с плавающей веткой;
- `README` указывает `git submodule update --init --recursive`;
- UNET DLL не пересобираются: их размер, SHA-256 и L1-структура проверяются
  перед сборкой;
- `unet.inc` подключается из `esp_net`, а тест подтверждает его идентичность
  версии из `rtl_net`;
- `AFNT320.DLL` и будущая библиотека-blitter берутся из этого сабмодуля только
  на графическом этапе;
- `GFX320.DLL` уже предоставляет MVP для режима `320×256×256`: очистку,
  прямоугольники, линии и 16×16 tiles. Она будет подключена в графическом
  milestone; текущий сетевой bootstrap не загружает графические DLL.

Локальные экспериментальные реализации AFNT320/ANTONFNT и reference-код для
Profi не являются зависимостями weather-forecast и в проект не включаются.
После подключения сабмодуля единственным источником AFNT320 считается
закреплённая ревизия `extern/sprinter-libs`.

## 4. Конфигурация

### 4.1. Имя и поиск

Необязательный файл `WEATHER.CFG` ищется рядом с EXE через
`APPINFO_EXE_HOMEDIR`. Если файла нет, это не ошибка: используются defaults.
Файл перечитывается при каждом ручном обновлении.

### 4.2. Формат

```ini
# WEATHER.CFG
HOST=go.sprinter.ru
PORT=70
SELECTOR=/weather/zx

# Необязательно. Пусто = определение места сервисом по IP.
# Для независимости от кодировки удобнее координаты:
LOCATION=43.2389,76.8897
```

Defaults:

| Ключ | Значение |
|---|---|
| `HOST` | `go.sprinter.ru` |
| `PORT` | `70` |
| `SELECTOR` | `/weather/zx` |
| `LOCATION` | пустая строка |

Ограничения parser:

- размер файла не более 1024 байт;
- строки CRLF и LF;
- пустые строки и строки с `#`/`;` в начале игнорируются;
- ключи нечувствительны к регистру, значения сохраняются как есть после
  удаления внешних пробелов;
- `HOST`: 1–128 ASCII-байт, без пробелов и управляющих символов;
- `PORT`: десятичное `1..65535`, после разбора хранится и как `u16`, и как
  ASCIIZ для UNET;
- `SELECTOR`: начинается с `/`, не содержит CR, LF, NUL или TAB, длина до
  96 байт;
- `LOCATION`: до 96 байт, без CR, LF, NUL и TAB; передаётся серверу как есть.
  Для кириллицы сервер ожидает UTF-8, поэтому для простого редактирования на
  DSS рекомендуются координаты или латиница;
- неизвестный ключ — предупреждение с номером строки;
- неверный известный ключ — экран ошибки с выбором `Enter: defaults`,
  `R: перечитать`, `Esc: выход`.

Итоговый запрос ограничить 192 байтами.

## 5. Архитектура

### 5.1. Модули

Фактическая структура первого milestone:

```text
Makefile
README.md
specs.md
src/
  weather.asm           EXE header, ENV, UNET bootstrap, cleanup и UX
resources/
  messages.json         UTF-8 каталог строк для генерации CP866
  README.ru.txt         UTF-8 источник README.TXT
tools/
  build/test/package/image и проверки форматов
extern/
  esp_net/              готовая UNETESP.DLL и общий UNET ABI
  rtl_net/              готовая UNETRTL.DLL
  libman/               актуальный исходник загрузчика
  sprinter-libs/        отложенные AFNT320 и blitter
build/
distr/
```

Локальных копий `dss.inc`, `unet.inc`, libman или исходников UNET DLL в
weather-forecast нет. Все они берутся напрямую из закреплённых сабмодулей;
абсолютные пути разработчика сборке не требуются.

### 5.2. Состояния программы

```text
START
  -> BANNER
  -> ENV_GET("NET")
  -> SELECT_BACKEND
  -> LIBMAN.l_load / l_info
  -> GETCAPS
  -> STATUS
  -> NETINIT
  -> PRINT_RESULT
  -> NETDONE
  -> LIBMAN.l_free
  -> DSS_EXIT
```

Флаги `DLL_LOADED` и `NET_INITIALIZED` обеспечивают идемпотентный cleanup при
ошибке на любой стадии. Первый milestone не вызывает `CONNECT`, `SETVMOD`, не
меняет video page и не трогает VRAM.

### 5.3. Модель данных

Хранить нормализованные числовые поля, а не указатели в receive buffer:

```text
WeatherModel
  status
  location[65] CP866
  country[3]
  current:
    year, month, day, hour, minute
    temperature_tenths        s16
    apparent_tenths           s16
    humidity                  u8
    weather_code              u8
    wind_tenths               u16
    wind_direction            u16
  day_count                   u8 (1..7)
  days[7]:
    year, month, day
    min_tenths                s16
    max_tenths                s16
    weather_code              u8
    precipitation             u8
    max_wind_tenths           u16
```

Город обрезать только для показа, но parser должен отклонять поле длиннее
буфера вместо записи за границу.

### 5.4. Память

- основной код: `ORG 0x8100`, окно 2;
- stack: `STACK_TOP=BSS_END+0x600`, compile-time проверка `<=0xC000`;
- libman и небольшое состояние — в image программы;
- буфер `ENV_GET`: 256 байт, поскольку DSS не принимает размер назначения;
- сетевой receive chunk: 256 или 512 байт;
- line buffer WX1: 160 байт;
- text output scratch: до 192 байт с обязательным NUL;
- сетевой DLL: окно 1;
- `WeatherModel`, parser state и все указатели UNET находятся ниже `#C000`;
- окно 3 не резервируется приложением: RTL backend может использовать его для
  ISA согласно своему ABI;
- большие нулевые буферы не включать в EXE, задать `EQU`-картой BSS и
  инициализировать во время запуска;
- добавить sjasmplus `ASSERT` для границ image, BSS, stack и всех UNET
  buffers (`<0xC000`).

### 5.5. Вывод текстового MVP

Текстовый milestone использует только штатные функции DSS:

- `PCHARS #5C` для ASCIIZ-строк в CP866;
- `WAITKEY #30`/`SCANKEY #31` для ожидания `R`, `Enter`, `Esc`;
- CR/LF в строках формируются явно;
- длинные поля выводятся частями либо безопасно обрезаются с маркером `...`;
- ни одна строка не форматируется непосредственно в receive buffer;
- перед каждым `PCHARS` сетевой приём уже завершён и UNET channel закрыт.

Успешный вывод:

```text
Weather forecast
Location: Алматы, KZ
Updated: 27.07.2026 14:30
Now: +23.5 C, feels +24.1 C, humidity 63%
Code: 2, wind 11.7 m/s, direction 230

27.07  min +16.4  max +25.7  code 61  rain 40%  wind 15.3
...

Source: Open-Meteo.com
R/Enter - refresh, Esc - exit
```

Вывод строится только из полностью подтверждённого `WeatherModel`. До
терминатора `.` программа может печатать один короткий status
`Loading weather...`, но не должна смешивать частично принятые данные с
результатом.

### 5.6. Отложенный графический слой

Графическая архитектура намеренно не специфицируется до готовности ABI
библиотеки-blitter. В weather-forecast не реализуются собственные:

- переключение видеорежима и видеостраниц;
- clear/fill/line/box;
- bitmap blit, transparency и clipping;
- управление акселератором, `PORT_Y` и VRAM aliases;
- выделение DSS-страниц под изображения;
- runtime decoder графических ресурсов.

После публикации ABI отдельным изменением `specs.md` будут зафиксированы:
версии и entry points обеих DLL, ownership MMU/DSS pages, формат входных
ресурсов, правила ошибок/cleanup и состав package. Подготовка самих
графических ресурсов начинается только после этого.

## 6. Сетевой сценарий

1. Прочитать `NET`.
2. Разрешить путь и загрузить нужную DLL в окно 1.
3. Вызвать `l_info`, `GETCAPS`, проверить ABI 1.x и TCP.
4. Включить `CANCELKEYS`.
5. Проверить `STATUS(0xFF)`.
6. Выполнить `NETINIT`.
7. `CONNECT`: `HOST`, строка `PORT`, channel 0.
8. Собрать selector, передать одной операцией `SEND`, проверить фактическое
   число отправленных байт.
9. Цикл `RECV` с timeout 5000 ms:
   - `A=OK, DE>0`: передать bytes потоковому parser;
   - `A=OK, DE=0`: считать idle-интервалы, после двух показать timeout;
   - `A=CLOSED`: успех только если parser уже получил `.\r\n`;
   - `A=CANCEL`: перейти в `ATTEMPT_CLEANUP`;
   - другие ошибки: сохранить код и `LASTERR`;
   - flag `more pending`: немедленно вызвать `RECV` повторно;
   - flag `data lost`: прекратить parsing и предложить retry.
10. Ограничить весь ответ 2048 байтами, число строк — 16, длину строки —
    159 байтами.
11. После терминатора выполнить `CLOSE`, `NETDONE`, `l_free`.

Не считать закрытие соединения единственным признаком успеха: валидный ответ
обязан иметь header, нужные записи, атрибуцию и точку-терминатор.

## 7. Parser WX1

Parser должен работать при любом разбиении TCP: CR и LF, разделитель `|`,
число и даже CP866-символ могут прийти в разных `RECV`.

Порядок:

1. собрать строку до CRLF;
2. header:
   - принять только `WX1`;
   - ветвиться по `OK`/`ERR`;
   - проверить `day_count 1..7`;
3. для `OK` принять строго одну `L`, одну `N`, ровно `day_count` записей `D`,
   одну `A` и `.` в правильном порядке;
4. для `ERR` принять одну `E` и `.`;
5. числа разбирать с контролем знака, переполнения и полного потребления поля;
6. проверить диапазоны:
   - humidity и precipitation `0..100`;
   - direction `0..360`;
   - weather code `0..255`;
   - корректные длины date/time;
   - разумный безопасный диапазон температуры и ветра;
7. не обновлять отображаемую модель, пока весь ответ не прошёл проверку.

Нужны fixtures:

- нормальный ответ с семью днями;
- отрицательная температура;
- город на CP866;
- каждый server error;
- ответ по одному byte на `RECV`;
- несколько строк в одном `RECV`;
- CR и LF в разных chunks;
- неизвестная версия;
- неверное число дней;
- отсутствующая `A` или `.`;
- слишком длинная строка/ответ;
- overflow и мусор после числа;
- преждевременное закрытие;
- UNET data-lost flag.

## 8. Графические ресурсы — отложено

Источник пиктограмм, набор состояний, palette, размеры, бинарный формат,
упаковка в EXE и converter пока не выбираются. Эти решения зависят от ABI и
формата ресурсов библиотеки-blitter в `sprinter-libs` и будут оформлены
отдельной ревизией спецификации.

До этого момента в репозиторий не добавляются временный bitmap format,
собственный runtime decoder или код прямого вывода в VRAM.

## 9. Отложенный макет 320×256

Этот макет остаётся ориентиром для будущей графической версии и не является
критерием готовности текстового MVP.

```text
┌────────────────────────────────────────┐  y=0
│ Алматы, KZ                    27.07 14:30│
├────────────────────────────────────────┤  y=24
│  ┌────────┐  +24 C                       │
│  │  64x64 │  ощущается +25 C             │
│  │ сегодня│  влажность 63%               │
│  └────────┘  ветер ЮЗ 11.7 м/с           │
│              мин +16 / макс +26, дождь 40%│
├────────────────────────────────────────┤  y=120
│ ПН     ВТ     СР     ЧТ     ПТ     СБ   │
│ 32x32  32x32  32x32  32x32  32x32 32x32│
│ +12    +11    +10     +8     +9     +7  │
│ +22    +19    +17    +15    +16    +14  │
│ 20%    55%    40%    10%     5%    30%  │
├────────────────────────────────────────┤  y=226
│ R/Enter: обновить  F1: помощь  Esc: выход│
│ ESP · Open-Meteo.com                    │
└────────────────────────────────────────┘  y=255
```

Точные зоны:

| Элемент | Координаты |
|---|---|
| header | `(0,0)–(319,23)` |
| текущая иконка | `(8,36)–(71,99)` |
| текущая температура 2× | от `(84,34)` |
| текущие параметры | `(84,62)–(315,112)` |
| разделитель | `y=120..127` |
| шесть карточек | `x=5+n×52`, `y=128..225`, ширина 50 |
| footer | `y=226..255` |

Первую дневную запись, дата которой совпадает с `N`, объединить с текущими
данными в большой блок. Остальные шесть вывести карточками. Если даты не
совпали, сегодняшним считать первую `D`, но не выходить за `day_count`.

На карточке оставить только день недели, 32×32 icon, min/max и вероятность
осадков. Максимальный ветер показывать в большом блоке/помощи, чтобы не
перегрузить экран.

Атрибуцию `Open-Meteo.com` показывать постоянно в footer.

## 10. Форматирование

- температура хранится в десятых; текстовый MVP показывает одну десятичную
  только при ненулевой дробной части для текущих и дневных значений;
- всегда показывать знак температуры;
- не использовать floating point;
- направление ветра переводить из градусов в 8 секторов:
  `С, СВ, В, ЮВ, Ю, ЮЗ, З, СЗ`;
- date/time проверять и форматировать как `DD.MM HH:MM`;
- день недели вычислять на Z80 из даты, без получения дополнительного поля;
- статические русские строки хранить в UTF-8 source и конвертировать в CP866
  во время сборки;
- текстовый MVP использует безопасные символы DSS-шрифта: `C` вместо символа
  градуса и `-` вместо typographic dash.

## 11. Ошибки и UX

### 11.1. Сообщения

| Ситуация | Сообщение и действие |
|---|---|
| нет `WEATHER.CFG` | молча использовать defaults |
| ошибка CFG | имя ключа/номер строки; defaults, retry или exit |
| нет `NET` | «Сеть не поднята. Запустите NETUP или NETCFG -i + IFUP» |
| `NET=WIFI`, неверный firmware | «UNETESP требует ESP-AT 2.2.2; снова запустите NETUP с подходящей прошивкой» |
| DLL не найдена | показать точное имя и каталог поиска |
| неверная DLL/ABI | «Несовместимая версия UNET DLL» |
| DNS/connect | показать host:port и предложить retry |
| send/receive timeout | «Сервис не ответил вовремя» |
| data lost | «Данные потеряны при приёме; уменьшите baud/проверьте связь» |
| server `BAD_LOCATION` | «Неверное место в WEATHER.CFG» |
| `LOCATION_NOT_FOUND` | «Место не найдено» |
| `GEO_UNAVAILABLE` | «Не удалось определить город; задайте LOCATION» |
| `WEATHER_UNAVAILABLE` | «Погодный сервис временно недоступен» |
| malformed/truncated WX1 | «Получен повреждённый или несовместимый ответ» |

Основной текст ошибки:

```text
Ошибка сети
Не удалось подключиться к go.sprinter.ru:70
Stage: CONNECT, code: 05
Detail: <безопасно обрезанный LASTERR>

R/Enter — повторить
Esc     — выход
```

Для config/server/parser errors используются те же обязательные поля
stage/code/detail; секретов в diagnostic output нет.

### 11.2. Cleanup

Ввести флаги:

- UNET DLL загружена;
- `NETINIT` выполнен;
- channel открыт;

`ATTEMPT_CLEANUP` выполняется в обратном порядке и допускает повторный вызов:

1. `CLOSE`;
2. `NETDONE`;
3. `l_free` UNET;
4. очистить сохранённые handles/pointers/state;

После него разрешены текстовый вывод и новый запрос. `APP_CLEANUP` вызывает
`ATTEMPT_CLEANUP`, очищает клавиатурное состояние и выполняет `DSS_EXIT`.

Рекомендуемые exit codes: `0` — нормальный выход/отмена, `2` — DLL/hardware,
`3` — network/protocol, `4` — config.

## 12. Сборка и поставка

Makefile:

```text
make / make build   проверить DLL, сгенерировать CP866 и собрать WEATHER.EXE
make deps           проверить сабмодули, UNET ABI и готовые DLL
make test           dependency, source-contract и EXE checks
make package        WEATHER.EXE + две UNET DLL + README.TXT в ZIP
make image          тестовый FAT12 1,44 МБ для Sprinter/MAME
make clean          удалить только generated build/distr
make submodule-check проверить ревизии и чистоту всех сабмодулей
```

`make package` включает:

- `WEATHER.EXE`;
- `UNETESP.DLL`;
- `UNETRTL.DLL`;
- краткий `README.TXT` в CP866/CRLF.

`AFNT320.DLL`, blitter DLL и погодные assets в пакет текстового MVP не входят.
Их состав и способ получения будут определены после стабилизации ABI
`sprinter-libs`.

Сборка — только `sjasmplus`; host-side scripts допустимы для CP866 strings,
fixtures и тестов, runtime полностью на Z80 asm.

Makefile должен:

- проверять наличие `sjasmplus`;
- проверять точные URL/ревизии четырёх сабмодулей;
- валидировать размер, SHA-256 и L1-структуру обеих готовых DLL через
  актуальный `sprinter-mkdll verify`;
- подтверждать идентичность `unet.inc` в ESP и RTL репозиториях;
- копировать готовые DLL в `build`, не собирая сетевые сабмодули;
- проверять `ASSERT`-границы code/BSS/stack;
- печатать размеры code, BSS и stack headroom;
- не обращаться к сети и не обновлять сабмодули во время обычной сборки.

## 13. Тестирование

### 13.1. Host

Для первого milestone реализованы:

- проверка URL, commit и чистоты четырёх сабмодулей;
- проверка размеров, SHA-256 и L1-структуры готовых UNET DLL;
- проверка идентичности `unet.inc` у ESP и RTL backend;
- проверка DSS EXE v1 header, file/image size и границ image/BSS/stack;
- проверка генерации CP866-сообщений и отсутствия CONNECT/AFNT/ANTONFNT;
- проверка плоского 8.3-состава ZIP и FAT12-образа.

На этапах parser и text UI добавляются fixtures, fuzz всех TCP chunk splits и
golden-тесты форматирования `WeatherModel`.

### 13.2. MAME

RTL baseline:

- использовать инструкцию
  `/Users/dmitry/dev/zx/sprinter/sprinter-rtl8019a/docs/MAME_NETWORK.md`;
- MAME `rtl8019as` + `pcap`, предпочтительно пара `feth0/feth1`;
- для первого milestone проверить `NET` отсутствует/неизвестен/`RTL`,
  успешную загрузку DLL и ошибки конфигурации/оборудования;
- локальный `gopher-gate`, timeout, early close и malformed response добавить
  после реализации transport.

### 13.3. Реальный Sprinter

Проверить оба backend:

- для ESP выполнить `NETUP` с ESP-AT 2.2.2;
- для RTL выполнить `NETCFG -i`, затем `IFUP`;
- запуск из каталога программы;
- запуск через `PATH` из другого current directory;
- `NET` отсутствует, неизвестен, равен `WIFI` и равен `RTL`;
- DLL отсутствует, повреждена и корректна;
- сообщения об ошибках и коды завершения `0`, `2`, `3`, `4`;
- читаемость текстового вывода в 40- и 80-колоночной оболочке DSS;
- видеорежим и MMU не меняются после успеха и после каждой ошибки;
- отсутствие зависания при отключённом кабеле/точке доступа;
- повторный запуск без reboot.

Проверки `WEATHER.CFG`, кириллицы в городе и погодных чисел добавляются в
соответствующих следующих milestones.

### 13.4. Критерии готовности текстового MVP

- один и тот же `WEATHER.EXE` работает с ESP и RTL;
- сервер можно сменить только правкой `WEATHER.CFG`;
- запрос является Gopher selector, HTTP-кода в программе нет;
- все валидные WX1 fields разбираются независимо от TCP chunking;
- повреждённый ответ никогда не приводит к записи за границы buffers;
- валидный ответ полностью и однозначно выводится через DSS `PCHARS`;
- server, config, DLL, network и parser errors имеют понятный текст и
  техническую диагностику;
- атрибуция `Open-Meteo.com` присутствует в успешном выводе;
- `R/Enter` повторяет полный цикл с перечитыванием CFG, `Esc` безопасно выходит;
- ни один text-MVP path не загружает AFNT/blitter и не меняет video/MMU;
- package запускается с FAT12/FAT16 и содержит только 8.3 имена.

## 14. Поэтапный TODO

### Этап 1. Сетевой bootstrap — завершён

- [x] Подключить и закрепить `esp_net`, `rtl_net`, `libman` и
      `sprinter-libs` как сабмодули.
- [x] Использовать готовые `UNETESP.DLL`/`UNETRTL.DLL`, не собирая и не
      копируя их исходники в проект.
- [x] Интегрировать актуальный `libman/libman.asm` с `LIBMAN_MAX_LIBS=1`.
- [x] Добавить Makefile: `deps`, `build`, `test`, `package`, `image`,
      `submodule-check`, `clean`.
- [x] Собрать `WEATHER.EXE` с DSS EXE v1 header, `ORG 0x8100`,
      BSS/stack assertions и CP866-сообщениями.
- [x] Реализовать `ENV_GET("NET")` и точный выбор
      `UNETESP.DLL`/`UNETRTL.DLL`.
- [x] Реализовать `l_load`, `l_info`, `GETCAPS`, `STATUS`, `NETINIT`,
      `NETDONE`, `l_free` и идемпотентный cleanup.
- [x] Проверить ABI major 1, `UNET_CAP_TCP` и отобразить подсказки
      `NETUP`/`NETCFG -i`/`IFUP`.
- [x] Проверять закреплённые коммиты, хеши DLL, L1-структуру, общий UNET ABI,
      EXE header, memory map и состав дистрибутива.
- [x] Формировать плоский ZIP и FAT12-образ из `WEATHER.EXE`, двух DLL и
      `README.TXT`.
- [x] Gate: `make test`, `make package` и `make image` выполняются успешно.

### Этап 2. Конфигурация, UNET и Gopher transport

- [ ] Реализовать поиск и parser необязательного `WEATHER.CFG`.
- [ ] Реализовать `STATUS`, `NETINIT` и `SETOPT(CANCELKEYS=1)`.
- [ ] Реализовать `CONNECT`, selector builder и полную проверку `SEND`.
- [ ] Реализовать bounded `RECV` loop, timeout, `more pending`, `data lost`,
      `NERR_CLOSED`, cancel и `LASTERR`.
- [ ] Подавать принятые bytes в callback parser; временный debug dump разрешён
      только compile-time флагом.
- [ ] Реализовать `CLOSE/NETDONE/l_free` на всех ветках.
- [ ] Зафиксировать реальные binary fixtures `/weather/zx`.
- [ ] Gate: получить полный raw WX1 через ESP и RTL, корректно завершить
      соединение при success, timeout, cancel и disconnect.

### Этап 3. Streaming parser WX1

- [ ] Реализовать CRLF line assembler, устойчивый к любому chunk split.
- [ ] Реализовать строгие state machines `WX1|OK` и `WX1|ERR`.
- [ ] Реализовать checked signed/unsigned decimal parser без floating point.
- [ ] Заполнять временную модель и commit в `WeatherModel` только после
      обязательных `A` и `.`.
- [ ] Добавить mapping server errors и точные parser error stages.
- [ ] Прогнать fixtures, все byte splits, limits, overflow и truncation.
- [ ] Gate: ожидаемая модель совпадает побайтно; malformed response никогда не
      публикует частичную модель.

### Этап 4. Текстовый прогноз и UX

- [ ] Вывести location/country, время, текущие показатели и все `D` records.
- [ ] Форматировать десятые доли, знаки, даты и направление ветра.
- [ ] Постоянно выводить атрибуцию из `A`, ожидаемо `Open-Meteo.com`.
- [ ] Реализовать success/error prompt: `R/Enter` — полный refresh с reload
      CFG, `Esc` — cleanup и выход.
- [ ] Не выполнять `PCHARS` внутри активного цикла `RECV`, кроме одного
      status до начала приёма.
- [ ] Gate: каждый fixture даёт стабильный golden text; все ошибки остаются
      user friendly и содержат stage/code/detail.

### Этап 5. Интеграция и релиз текстового MVP

- [ ] Проверить default `go.sprinter.ru:70/weather/zx`.
- [ ] Проверить alternate host/port/selector без rebuild.
- [ ] Проверить ESP-AT 2.2.2 и RTL8019A в MAME/на реальном Sprinter.
- [ ] Проверить запуск рядом с EXE и через `PATH`, CFG и DLL error matrix.
- [ ] Проверить CP866, 40/80 columns, повторный refresh и повторный запуск.
- [ ] Собрать ZIP и FAT image: EXE, две UNET DLL, sample CFG, README.
- [ ] Gate: выполнены все критерии §13.4; зафиксирован baseline перед
      подключением графики.

### Этап 6. Графика — заблокирован до готовности ABI

- [ ] Дождаться опубликованного ABI AFNT320 и blitter в `sprinter-libs`.
- [ ] Обновить и закрепить gitlink сабмодуля на совместимый release/commit.
- [ ] Отдельно дополнить `specs.md`: ABI, версии DLL, ошибки, ownership
      MMU/DSS pages, resource format и package.
- [ ] Добавить тонкие wrappers, не дублируя графические функции в
      weather-forecast.
- [ ] Подготовку иконок и converter планировать только после фиксации формата
      ресурсов blitter.

## 15. Основные риски

| Риск | Снижение риска |
|---|---|
| ABI blitter ещё меняется | graphics не входит в text MVP; никаких provisional wrappers или форматов |
| сабмодуль недоступен без SSH key | понятная инструкция init и отдельный `submodule-check`; обычный text build не использует его код |
| код/BSS/stack не помещаются в окно 2 | явная memory map и compile-time ASSERT |
| TCP делит строки произвольно | streaming parser с fixtures всех chunk boundaries |
| повреждённый ответ портит память | жёсткие limits, checked arithmetic, commit model only at terminator |
| неверно выбран network backend | только явный marker `NET=WIFI/RTL` |
| DLL не находится при запуске через PATH | `APPINFO_EXE_HOMEDIR`, затем fallback cwd |
| ESP теряет bytes во время вывода | не вызывать `PCHARS` во время RECV; учитывать RXFLOW/data-lost |
| кириллица в LOCATION | рекомендовать coordinates/Latin; response UI остаётся CP866 |
| cleanup пропущен на редкой ошибке | одна stateful unwind routine и fault-injection tests |
