# Оборона Моста — установка и запуск

Архив для проверки в Roblox Studio: исходники, карта и готовые place-файлы.

| Файл | Назначение |
|---|---|
| `BridgeDefense_Commission.rbxl` | **Лобби** — основной файл для Play в Studio |
| `BridgeDefense_Battle.rbxl` | Боевой place (для публикации в Roblox) |
| `INSTALL.md` / `INSTALL.txt` | Эта инструкция |
| `src/` | Код игры (Luau) |
| `map/` | Карта и освещение |

Roblox Studio есть только на **Windows** и **macOS**. С телефона играют уже **после публикации**.

---

## Быстрый старт (рекомендуется, Windows)

1. Распакуйте архив, например в `C:\Games\BridgeDefense`.
2. Установите [Roblox Studio](https://create.roblox.com/) (войдите в аккаунт → Create → Install Studio).
3. В PowerShell из папки проекта:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\install-tools.ps1
.\open-studio.ps1
```

4. Дождитесь открытия Studio и нажмите **F5** (Play).

`open-studio.ps1` сам:
- собирает актуальный `BridgeDefense_Commission.rbxl` со скриптами и картой;
- поднимает локальную БД прогресса (Gold/XP);
- ставит плагин сохранения.

**Rojo Connect не нужен** в этом режиме.

Остановка Play: **Shift+F5**.

---

## Ещё проще (без скриптов)

1. Распакуйте архив.
2. Установите Roblox Studio.
3. Дважды откройте `BridgeDefense_Commission.rbxl`.
4. File → Game Settings → Security → включите:
   - **Allow HTTP Requests**
   - **Enable Studio Access to API Services**
5. Нажмите **F5**.

Если прогресс (золото/опыт) не сохраняется между запусками Play — используйте вариант с `.\open-studio.ps1` выше.

### macOS

1. Распакуйте zip.
2. Установите Studio с [create.roblox.com](https://create.roblox.com/).
3. File → Open → `BridgeDefense_Commission.rbxl`.
4. Game Settings → Security → Allow HTTP Requests + API Services.
5. Play (**F5**).

Если macOS блокирует файл: ПКМ → Open → Open.

---

## Что нажимать в игре (Studio)

**Верхняя строка кнопок**

| Кнопка | Действие |
|---|---|
| Меню | Вкладки: Отряд, Ежедневка, Пати, Гайд… |
| Прокачка | Окно прокачки за XP |
| Шоп | Телепорт к магазину на карте |

**Вторая строка**

| Кнопка | Действие |
|---|---|
| Бой | Старт миссии / переход к мосту |
| Обнул. | Сброс прогресса (**нажать два раза**) |

**В бою:** Выход | Волна x10.

На карте подойдите к зоне и нажмите **E** (магазин, прокачка, промокод, лидерборд, «В бой»).

---

## Режим разработки (правки кода)

Нужен, если меняете файлы в `src/` и хотите live-синк.

### Windows

```powershell
.\install-tools.ps1
.\open-studio.ps1 -Live
```

В Studio: **Plugins → Rojo → Connect** (`localhost:34872`) → **F5**.

После правки в `src\`: Stop → снова Play.

### macOS

```bash
brew install rojo
# плагин Rojo: Studio → Toolbox → Rojo, или Rojo.rbxm в ~/Documents/Roblox/Plugins/

rojo build lobby.project.json -o BridgeDefense_Commission.rbxl
rojo serve lobby.project.json
```

Откройте `BridgeDefense_Commission.rbxl` → Rojo Connect → Play.

Боевой place отдельно:

```text
rojo build battle.project.json -o BridgeDefense_Battle.rbxl
```

Для проверки в Studio достаточно лобби: бой запускается кнопкой **Бой**.

---

## Публикация в Roblox (телефон / другие игроки)

Studio на телефон не ставится. Нужно опубликовать Experience.

1. Откройте `BridgeDefense_Commission.rbxl` → File → **Publish to Roblox**.
2. Откройте `BridgeDefense_Battle.rbxl` и опубликуйте как **второй Place** того же Experience.
3. Впишите PlaceId в `src/Shared/Config/GameConfig.lua`:

```lua
PlaceIds = {
    Lobby = 0000000000,  -- PlaceId лобби
    Battle = 0000000000, -- PlaceId боя
},
```

4. В `src/Shared/Config/AdminConfig.lua` добавьте свой UserId:

```lua
AdminUserIds = { 123456789 },
```

5. Пересоберите / заново опубликуйте оба place.
6. Game Settings: API Services **On**, Max Players лобби **100**, доступ Public/Friends.

Ссылка для игроков: `https://www.roblox.com/games/PLACE_ID_ЛОББИ/...`

| Устройство | Как зайти |
|---|---|
| ПК | roblox.com или приложение Roblox |
| iPhone / iPad | App Store → Roblox |
| Android | Google Play → Roblox |

Пока `PlaceIds = 0`, отдельный боевой сервер в опубликованной игре не телепортирует. Локальный бой в Studio работает и без ID.

---

## Если что-то не работает

| Проблема | Решение |
|---|---|
| Пустая карта / нет скриптов | Откройте `BridgeDefense_Commission.rbxl` или запустите `.\open-studio.ps1` |
| Gold/XP сбрасываются | Запускайте через `.\open-studio.ps1`; в Studio включите HTTP + API Services |
| «API Services» серое | Сначала Publish to Roblox, затем снова Game Settings |
| Rojo Connect не коннектится | Должен работать `rojo serve`, порт `34872` свободен |
| На телефоне игры нет | Experience не опубликован или Private |
| Плагина Rojo нет | `.\install-tools.ps1`, перезапуск Studio |

---

## Состав архива

```
BridgeDefense/
├── INSTALL.md / INSTALL.txt     ← инструкция
├── README.md                    ← описание проекта
├── BridgeDefense_Commission.rbxl
├── BridgeDefense_Battle.rbxl
├── lobby.project.json
├── battle.project.json
├── commission-place.project.json
├── install-tools.ps1            ← Windows: Rojo + плагины
├── open-studio.ps1              ← Windows: сборка + Play
├── aftman.toml
├── src/                         ← код
├── map/                         ← карта
└── tools/                       ← LogServer, плагин Persist и утилиты
```
