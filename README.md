# ColorOSCC — Control Center в стиле ColorOS 16 для iOS 15–17

## Сборка
1. Установи Theos (https://theos.dev).
2. Для rootless-джейлбрейка (Dopamine и т.п.) раскомментируй `THEOS_PACKAGE_SCHEME = rootless` в Makefile.
3. `make package install THEOS_DEVICE_IP=<ip устройства>` (или `make package` и поставь .deb вручную).

## Настройка кнопок
Карандаш вверху (или ⋯ → Edit buttons): удалить / добавить / перетащить кнопки. Хранится в NSUserDefaults (`OPCC_buttons`).
Чтобы добавить свою кнопку: допиши id в `OPCCActions.m` (+meta, +tap).

## Шрифт
В оригинале OPlusSans; положи шрифт в систему и замени `systemFontOfSize` на `fontWithName:`.

## Что нужно проверить на устройстве
Эти вызовы используют приватные API и могут отличаться по версиям iOS: DND, запись экрана, режимы звука (вибро/без звука),
скриншот, Eye Comfort, режим энергосбережения. Если что-то не срабатывает — смотри `log stream` / Console для SpringBoard.

## GitHub Actions
Workflow `.github/workflows/build.yml` собирает два .deb (rootful и rootless) при каждом push.
Скачать: вкладка Actions → последний запуск → Artifacts → `ColorOSCC-deb`.
Релиз: `git tag v1.0.0 && git push origin v1.0.0` — .deb появятся в Releases.
