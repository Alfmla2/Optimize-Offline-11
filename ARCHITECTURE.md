# Архитектура Optimize-Offline

## Назначение

Optimize-Offline — PowerShell-модуль для офлайн-оптимизации образов Windows 10/11
(включая 24H2+): удаление приложений/служб/компонентов, интеграция обновлений
(Dedup, Store, Edge, DeveloperMode), твики реестра и создание загрузочного ISO.
Управляется через консоль (`Start-Optimize.ps1`) или WPF GUI (`Src\GUI\Start.ps1`).

## Требования

- Windows PowerShell 5.1 (не PowerShell 7 без `-SkipEditionCheck`)
- DISM (Deployment Image Servicing and Management)
- WIMGAPI (Windows Imaging API, поставляется с Windows)
- Windows ADK (для `oscdimg.exe` — опционально, только при создании ISO)
- Права администратора (UAC) или TrustedInstaller

## Структура директорий

```
<ModuleRoot>\
├── Optimize-Offline.psm1          # Главный модуль: единственная функция Optimize-Offline
├── Start-Optimize.ps1             # Entry point (читает Configuration.json, вызывает модуль)
├── Start-GUI-BAU-TI.ps1           # (опц.) запуск GUI от TrustedInstaller
├── populateLists.bat              # Обёртка Start-Optimize.ps1 -populateLists
├── Configuration.json             # Основная конфигурация
├── Configuration_custom.json      # (опц.) пользовательская, переопределяет основную
├── Src\
│   ├── Offline-Resources.psm1     # Ресурсный модуль (функции, пути, алиасы, локализация)
│   ├── Public\                    # Публичные функции (AST-экспорт)
│   │   ├── Get-SystemPackages.ps1
│   │   ├── Get-ImageServices.ps1
│   │   ├── Get-OfflineHives.ps1   # + Get-OfflineCurrentControlSet
│   │   ├── Set-RegistryProperties.ps1
│   │   ├── Invoke-OptimizeDataDedup.ps1   # вынесенная интеграция
│   │   └── ... (остальные Get-*/Set-*/Import-*)
│   ├── Private\                   # Внутренние хелперы (не экспортируются)
│   │   ├── Get-DeploymentTool.ps1
│   │   ├── Get-DISMPath.ps1
│   │   ├── Grant-KeyAccess.ps1
│   │   └── Import-Win32API.ps1
│   ├── en-US\ , ru-RU\            # Локализация (.strings.psd1)
│   └── GUI\
│       ├── Start.ps1              # WPF GUI (главный скрипт интерфейса)
│       ├── XAML\                  # WPF-шаблоны (Layout, Tab, списки)
│       └── RemovalTemplates\      # JSON-снимки состояния списков для GUI
├── Content\
│   ├── Lists\                     # Пользовательские списки
│   │   ├── WindowsApps\ , SystemApps\ , Capabilities\ , Packages\
│   │   ├── FeaturesToEnable\ , FeaturesToDisable\
│   │   └── Services\ (ServicesList.json, ServicesAdvanced.json)
│   ├── Additional\                # Доп. контент (Setup, Wallpaper, Drivers, Unattend, ...)
│   └── CustomRegistry.reg         # Пользовательские твики реестра
├── Packages\                      # Интеграционные CAB/APPX (Dedup, Edge, Store, DeveloperMode)
├── Optimize-Offline_<timestamp>\  # Результат: логи, ISO/WIM, PackageSummary.log
└── OfflineTemp_<random>\          # Временная рабочая папка (удаляется при завершении)
```

## Ключевые компоненты

### `Optimize-Offline.psm1` (главный модуль)

- Одна экспортируемая функция `Optimize-Offline` (фасад).
- `Using module .\Src\Offline-Resources.psm1` — обязательный parse-time импорт
  (иначе алиасы `RegHives`, `RegKey`, `Log`, `GetPath` не разрешаются на парсинге).
- Регионы: Media Export → Image Preparation → Populate Lists → Removals
  (Apps/SystemApps/Capabilities/Packages/Features/Services) → Integrations
  (Dedup/Store/Edge/DeveloperMode) → Registry Tweaks → Finalization.
- `Begin`/`Process`/`End` + `try/finally` для гарантированной очистки
  (dismount, unload hives) даже при ошибке.
- `$DynamicParams` (Hashtable) — общее состояние между регионами.

### `Src\Offline-Resources.psm1` (ресурсный модуль)

- Dot-source всех `Src\Public\*.ps1` и `Src\Private\*.ps1`.
- Инициализирует пути (`$OptimizeOffline`), загружает локализацию (`$OptimizeData`).
- Создаёт алиасы: `Create`, `Purge`, `Log`, `RegHives`, `RegKey`, `GetPath`, `StartExe`.
- **AST-экспорт**: `Export-ModuleMember` перечисляет ВСЕ функции из `Public\*.ps1`
  (не по basename, а по AST — критично для файлов с несколькими функциями,
  например `Get-OfflineHives.ps1` содержит ещё `Get-OfflineCurrentControlSet`).

### `Start-Optimize.ps1` (entry point)

- Читает `Configuration.json` (или `Configuration_custom.json`, если существует).
- Парсит в `$ConfigParams` (Ordered hashtable), добавляет флаги `-populateLists`/`-populateTemplates`.
- Импортирует `Optimize-Offline.psm1` и вызывает `Optimize-Offline @ConfigParams` (splatting).
- Параметры: `-populateLists`, `-populateTemplates`, `-GUI`, `-FlashUSBDriveNumber`.

### `Src\GUI\Start.ps1` (WPF GUI)

- Редактирует `Configuration.json`, `Content\Lists\*`, `Src\GUI\RemovalTemplates\*`.
- **Не импортирует** `Optimize-Offline.psm1` — запускает `Start-Optimize.ps1 -GUI` как
  дочерний процесс (`Start-Process powershell -WindowStyle Hidden`), перенаправляя
  stdout в `ConsoleOut.txt`. Таймер (`System.Windows.Forms.Timer`, 3 с) читает
  `ConsoleOut.txt` и проверяет `ExitCode` завершения.
- `Save-All` — принудительно сохраняет всё перед Process/закрытием окна.

## Конфигурация

| Файл | Назначение |
|---|---|
| `Configuration.json` | Основные параметры (SourcePath, WindowsApps, Registry, Dedup и т.д.) |
| `Configuration_custom.json` | Пользовательская (переопределяет основную, если существует) |
| `Content\Lists\*\*List.json` | Источник истины для выделений (Select/Whitelist/Blacklist) |
| `Src\GUI\RemovalTemplates\*Template.json` | Снимок состояния для GUI (синхронизируется из Content\Lists) |

**Форматы:**

- WindowsApps/Capabilities/Packages: `{ "DisplayName"|"Name"|"PackageName": [ ... ] }`
- SystemApps: `{ "SystemApps": [{"PackageName": "...", "DisplayName": "..."}] }`
- Services Advanced: `{ "__Info": [...], "Services": [{"name","start","description"}] }`

## Логи

Пишутся в `Optimize-Offline_<timestamp>\LogOffline\`:

| Файл | Что содержит |
|---|---|
| `Optimize-Offline.log` | Общий ход (INFO/ERROR) |
| `OptimizeErrors.log` | ErrorRecord из `Catch`-блоков |
| `DISM.log` | DISM-операции (свой `-LogPath`) |
| `RegistrySettings.log` | Список применённых твиков реестра |
| `PackageSummary.log` | Итог интеграций (Dedup/Store/Edge/Drivers) |

## Процесс работы

```
1. Start-Optimize.ps1  →  читает Configuration.json  →  $ConfigParams
2. Import-Module Optimize-Offline.psm1 (parse-time using module Offline-Resources)
3. Optimize-Offline @ConfigParams
   ├── Begin: Test-Requirement, dismount залипших, очистка
   ├── Process:
   │   ├── Media Export (ISO→temp, WIM/SWM/ESD→install.wim)
   │   ├── Image Metadata Validation (build, arch, LTSC)
   │   ├── Image Preparation (Mount-WindowsImage, RegHives -Load, $CCS)
   │   ├── Populate Lists (если -populateLists / -populateTemplates)
   │   ├── Removals (Apps/SystemApps/Capabilities/Packages/Features/Services)
   │   ├── Integrations (Dedup/Store/Edge/DeveloperMode)
   │   ├── Registry Tweaks + Additional Content + SelectiveRegistry
   │   ├── ComponentCleanup, Start Menu, W11 HW bypass
   │   └── PackageSummary
   ├── Image Finalization (dismount, export WIM/ESD/ISO, save, cleanup)
   └── End: восстановление $ErrorActionPreference, очистка temp
```

## Взаимодействие GUI ↔ модуль

```
┌──────────────────────────────────────────────────────────────┐
│ Src\GUI\Start.ps1 (WPF)                                      │
│  • редактирует Configuration.json, Content\Lists\*,          │
│    Src\GUI\RemovalTemplates\*                                │
│  • НЕ импортирует Optimize-Offline.psm1                      │
│  • Start-Process powershell -ArgumentList "...Start-Optimize"│
│  • таймер: читает ConsoleOut.txt, проверяет ExitCode         │
└────────────────────────────┬─────────────────────────────────┘
                             ▼ Start-Process (отдельный процесс)
┌──────────────────────────────────────────────────────────────┐
│ Start-Optimize.ps1 -GUI                                      │
│  • Import-Module Optimize-Offline.psm1                       │
│  • Optimize-Offline @ConfigParams                            │
└────────────────────────────┬─────────────────────────────────┘
                             ▼
┌──────────────────────────────────────────────────────────────┐
│ Optimize-Offline.psm1 → Offline-Resources.psm1               │
│  • монтирует, применяет, размонтирует                        │
└──────────────────────────────────────────────────────────────┘
```

Изоляция процессов = падение модуля не убивает GUI; модуль можно тестировать
из консоли независимо.

## Принципы модульности

- **`using module`** (не `Import-Module`) — обязателен для Offline-Resources:
  алиасы и переменные должны быть видны на этапе парсинга Optimize-Offline.psm1.
- **AST-экспорт функций** — поддерживает несколько функций в одном .ps1.
- **Hashtable/StringBuilder передаются по ссылке** — helper-функции могут
  мутировать `$DynamicParams`, `$RemovedPackages`, `$Visibility` без `[ref]`.
- **`$PSCmdlet` не выносится** в helper’ы (кроме случаев, где это критично) —
  иначе ломается `-WarningAction`/`-Verbose` родителя.
- **Не выносить**: Image Preparation/Finalization, Media Export, Removed
  Package Clean-up (слишком связаны с глобальным состоянием).

## Известные особенности

- **`Get-SystemPackages.ps1` не размонтирует hive** — caller (System App Removal)
  сам делает `RegHives -Load` до и `RegHives -Unload` после. Это исправило баг
  «Failed to Remove System App» (hive размонтировался до `reg delete`).
- **`populateLists` размонтирует hive после SystemApps** — иначе DISM
  (`Get-CapabilityPackages`, `Get-OtherWindowsPackages`, `Get-OptionalEnabledFeatures`)
  получает «file is being used by another process».
- **Permanent packages** (например, `WMIC-FoD` на 24H2) — ошибка `0x800f0825`
  ожидаема, обрабатывается в `Try/Catch` с `Log "Skipped ..."`.
- **`-populateLists` перезаписывает** `Content\Lists\*`;
  **`Refresh Lists` в GUI (`-populateTemplates`)** — не трогает их (сохраняет выделения).
- **`Out-GridView` требует ISE-компонент** (`Microsoft.PowerShell.GraphicalHost`),
  иначе молча возвращает `$null` — пре-флайт `Test-InteractiveGridView`.
- **`SourcePath`**, не `ImagePath` — параметр модуля называется именно так.

## Рекомендуемый порядок выноса интеграций

2. `Invoke-OptimizeWindowsStore.ps1`
3. `Invoke-OptimizeEdge.ps1` + `Invoke-OptimizeEdgePolicy.ps1`

Каждый вынос: параметры (`$InstallMount`, `$ScratchFolder`, `$DISMLog`,
`$DynamicParams`, `$OptimizeData`), прогон с флагом, проверка ключевых
`[INFO]`-сообщений в `Optimize-Offline.log`.

## Примеры использования

**Консоль (через Configuration.json):**

```powershell
# отредактировать Configuration.json → SourcePath = "W:\install.wim"
.\Start-Optimize.ps1
```

**Populate списков (Out-GridView):**

```powershell
.\populateLists.bat
```

**GUI (WPF):**

```powershell
.\Src\GUI\Start.ps1
```

**Только шаблоны (без GridView, для GUI):**

```powershell
.\Start-Optimize.ps1 -populateTemplates
```

**От TrustedInstaller (если нужно монтировать системные образы):**

```powershell
.\Start-GUI-BAU-TI.ps1
```


