# Оборона Моста — Bridge Defense MVP

Кооперативная PvE-игра для Roblox (Luau). Два place: **Лобби** и **Бой** (Reserved Server).

## Структура проекта

```
roblox_game/
├── lobby.project.json      # Rojo-проект лобби
├── battle.project.json     # Rojo-проект боевой локации
├── aftman.toml             # Rojo 7.x
└── src/
    ├── Shared/             # Конфиги и общие модули
    ├── Server/             # Серверные сервисы (общие)
    ├── Client/             # Клиентский UI
    ├── Lobby/              # Place-специфичный код лобби
    └── Battle/             # Place-специфичный код боя
```

## Быстрый старт (Roblox Studio + Rojo)

### 1. Установка инструментов

```powershell
# Aftman (менеджер инструментов)
# https://github.com/LPGhatguy/aftman — установите, затем:
aftman install

# Или установите Rojo вручную: https://github.com/rojo-rbx/rojo
```

### 2. Сборка place'ов

Используется **только заказная карта** (`Commission_place`). Старая procedural-карта удалена.

**Быстрый запуск (рекомендуется):**
```powershell
cd c:\Users\armian\Desktop\Works\Freelance\roblox_game
.\open-studio.ps1
```
Откроется `BridgeDefense_Commission.rbxl` + Rojo serve.

**Вручную:**
```powershell
rojo build lobby.project.json -o BridgeDefense_Commission.rbxl
rojo serve lobby.project.json
```

**Бой (отдельный place, продакшен):**
```powershell
rojo serve battle.project.json
```

### 3. Публикация

1. Опубликуйте **Lobby** place → скопируйте PlaceId.
2. Опубликуйте **Battle** place → скопируйте PlaceId.
3. В `src/Shared/Config/GameConfig.lua` укажите:
   ```lua
   PlaceIds = {
       Lobby = ВАШ_LOBBY_PLACE_ID,
       Battle = ВАШ_BATTLE_PLACE_ID,
   },
   ```
4. В `src/Shared/Config/AdminConfig.lua` добавьте UserId стримера:
   ```lua
   AdminUserIds = { 123456789 },
   ```
5. В Game Settings → Security: включите **Enable Studio Access to API Services**.
6. В Game Settings → Max Players: **100** для лобби.

### 4. DataStore

Игра использует DataStoreService. Для тестов в Studio включите API Services. В продакшене данные сохраняются автоматически.

## Архитектура

| Слой | Описание |
|------|----------|
| **Лобби** | До 100 игроков, пати, магазин, прокачка, промокоды, лидерборд |
| **Бой** | Reserved Server на 1–4 игроков, волны врагов, боты-тиммейты |

### Серверные сервисы (`src/Server/Services/`)

- `DataService` — профиль игрока (DataStore)
- `PartyService` — пати до 4 человек
- `TeleportService` — Reserved Server телепорт
- `WaveService` — волны, чекпоинты, рестарт
- `EnemyService` / `BotService` / `CombatService` — бой
- `RewardService` — XP/Gold + кооп-множитель
- `ShopService` / `UpgradeService` — магазин и прокачка
- `PromocodeService` / `AdminService` — промокоды и админ-панель
- `LeaderboardService` — OrderedDataStore топ
- `DailyRewardService` — ежедневные награды
- `GlobalConfigService` — режим волн (бесконечный / фиксированный)

### Конфиги (`src/Shared/Config/`)

Все балансовые данные вынесены в ModuleScript'ы — правьте без изменения логики:

- `GameConfig.lua` — кооп-множитель, волны, чекпоинты, PlaceId
- `WeaponsConfig.lua` — 4 типа × 5 тиров
- `ArmorConfig.lua` — броня × 5 тиров
- `EnemiesConfig.lua` — статы и скалирование врагов
- `UpgradesConfig.lua` — прокачка HP/точность/перезарядка
- `AdminConfig.lua` — whitelist админов

## Ключевые формулы

**Кооп-множитель наград:**
```
M = 1.0                          — соло (3 бота)
M = 1.1 + 0.1 × (друзья в пати)  — макс. 1.4 при 3 друзьях
```

**Чекпоинты:** каждые 5 волн. При wipe — возврат в лобби; следующий бой стартует с сохранённого чекпоинта (прогресс не понижается).

**Боты:** `BotsInheritHostUpgrades = true` в GameConfig — наследуют прокачку хоста.

## Точки карты

Все механики привязаны к `Workspace.MapPoints`:

| Имя | Назначение |
|-----|------------|
| `DefenseSpawn1..4` | Позиции отряда |
| `EnemySpawn` | Спавн врагов |
| `BridgePath` | Цель движения врагов |
| `LobbyTeleportBattle` | Телепорт в бой (лобби) |

При получении финальной карты — создайте Folder `MapPoints` с Part'ами с этими именами.

## Критерии приёмки MVP

- [x] Лобби до 100 игроков, пати, телепорт на Reserved Server
- [x] Соло = 3 бота с авто-огнём
- [x] Волны с растущими статами, чекпоинт каждые 5 волн
- [x] XP/Gold с кооп-множителем (1.0–1.4)
- [x] Магазин: 4 оружия + броня × 5 тиров; прокачка за XP
- [x] Промокоды (админ создаёт, игрок активирует)
- [x] Лидерборд, сохранение прогресса
- [x] UI для ПК и мобильных (touch-кнопка «ОГОНЬ»)
- [x] Бесконечные волны по умолчанию; админ переключает на фиксированное число

## Ассеты

MVP использует placeholder-модели (Part'ы). После публикации замените модели оружия/окружения из Creator Store (поиск «PUBG», military) — логика не зависит от мешей.

## Поддержка

45 дней техподдержки по договору. Контакт исполнителя — см. договор.
