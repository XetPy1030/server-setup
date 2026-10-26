# Синхронизация Obsidian через CouchDB

Личный блокнот синхронизируется между Mac, Windows и Android плагином [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) через CouchDB на web. Сервер поднят 2026-10-26, до этого блокнот синхронизировался через git.

## Как устроено

- [couchdb/](../couchdb/) — CouchDB 3.5.3. Снаружи `https://obsidian.xetpy.ru` через NPM → `http://couchdb:5984`, база `obsidian-xet`.
- **Шифрование на устройствах (E2EE)**, имена файлов тоже скрыты. На сервере и в бэкапах лежит только шифротекст. Пароль шифрования есть на устройствах и в менеджере паролей, больше нигде. **Потеряешь его — бэкап не расшифровать.**
- Без логина CouchDB отвечает только на `/_up`. Это healthcheck контейнера и проверка blackbox (`SiteDown`, [alerts.md](alerts.md)).
- Синхронизируются заметки и вложения. Плагины и настройки Obsidian — через **Customisation Sync**, выборочно: каждое устройство выкладывает свои, а применяет только то, что отмечено в окне Customisation Sync. Так на телефоне ставится меньший набор плагинов. Настройки самого LiveSync не синхронизируются. Hidden File Sync выключен: им нельзя управлять теми же файлами.
- Режим (Settings → Self-hosted LiveSync → Sync Settings → **Sync Mode**): **LiveSync** на всех устройствах, правки уходят сразу. На Android синхронизация идёт, только пока Obsidian открыт: в фоне система его усыпляет. Мастер первого устройства выключает всю автоматику, поэтому после подключения режим проверить руками.
- Устройства ходят под админом CouchDB: первое устройство при начальной заливке удаляет и заново создаёт базу, а это может только админ.
- Настройки сервера — в [couchdb/livesync.ini](../couchdb/livesync.ini), те же, что ставит скрипт из репозитория плагина. После правки `sv web deploy couchdb` перезапустит CouchDB ([couchdb/reload.sh](../couchdb/reload.sh)). Перезапуск рвёт синхронизацию на несколько секунд, устройства переподключатся сами.

Только на сервере (в `.gitignore`):

- `couchdb/.env` — логин и пароль админа. **Копия — в менеджере паролей.**
- `couchdb/etc/docker.ini` — пишет сам CouchDB: хеш пароля админа и uuid сервера. По uuid клиенты узнают сервер. Если он сменится, они заново сверят всю базу.
- `couchdb/data/` — база.

## Подключить новое устройство

1. Obsidian → Настройки → Сторонние плагины → Обзор → **Self-hosted LiveSync** → установить и включить.
2. Хранилище — **новое пустое**, а не старая копия из git или из другого места: иначе LiveSync начнёт сливать две версии.
3. На уже подключённом устройстве (Mac): палитра команд → `Self-hosted LiveSync: Copy settings as a new Setup URI`. Придумать пароль для ссылки, скопировать ссылку. Ссылку и пароль передавать разными путями.
4. На новом устройстве: уведомление `Welcome to Self-hosted LiveSync` → `I am adding a device to an existing synchronisation setup` → `Use a Setup URI` → вставить ссылку и её пароль → `Restart and Fetch Data` → `Overwrite all with remote files`.
5. Дождаться, пока пропадут индикаторы прогресса LiveSync. Выставить Sync Mode (см. выше).
6. Плагины и настройки: LiveSync → вкладка Customisation Sync:
   - **Device name** — уникальное (`mac`, `windows`, `android`);
   - включить **Enable customisation sync** и **Scan customisation automatically**;
   - **Open**, в колонке `mac` отметить нужное, применить, перезапустить Obsidian;
   - в том же окне у `workspace.json` (на телефоне — `workspace-mobile.json`) выбрать режим **Ignore** (значок слева от имени). Это раскладка вкладок: она меняется при каждом открытии заметки и иначе постоянно улетает на сервер.

   На компьютер — всё, кроме самого Self-hosted LiveSync и `workspace.json`. На телефон — Tasks, Kanban, Excalidraw и `app.json` (папка вложений и прочие настройки «Файлы и ссылки»).

   «Scan customisation periodically» не нужен: плагин следит за файлами `.obsidian` сам и при включённом слежении периодическую проверку не запускает.
7. Проверить: заметка с Mac на месте, новая заметка отсюда дошла до Mac.

Старую копию хранилища на устройстве удалить, только когда новая синхронизировалась.

## Бэкап

База входит в ночной restic-бэкап web вместе со всем `server-setup/` ([backup.md](backup.md)). Файлы CouchDB только дописываются, поэтому копировать их на ходу безопасно (так советует документация CouchDB). Снимки 7 дней, 4 недели, 6 месяцев.

Плюс у каждого устройства своя полная копия заметок.

Проверено 2026-10-26: база из снимка поднята во временном контейнере. Все 2979 документов совпали с живой базой по id и ревизии, uuid сервера тот же.

## Восстановление

**Сервер умер, устройства целы.** Проще всего поднять CouchDB с пустой базой и залить её с Mac: в настройках LiveSync → Maintenance → **Overwrite Server Data with This Device's Files**. Остальные устройства потом — **Reset Synchronisation on This Device**. Перед этим убедиться, что на Mac есть всё, что было на других устройствах.

**Заметки испорчены или удалены на всех устройствах.** Синхронизацию на устройствах остановить (выключить плагин), базу на сервере вернуть из снимка до порчи. Потом на каждом устройстве LiveSync → Maintenance → **Reset Synchronisation on This Device**: устройство перекачает всё с сервера.

База из снимка (на web):

```sh
cd ~/server-setup
backup/backup.sh snapshots                              # выбрать снимок
backup/backup.sh restore <снимок> --target /restore --include /root/server-setup/couchdb
cd couchdb && docker compose down
mv data data.broken && mv etc etc.broken                 # удалить, когда всё заработает
cp -a /root/restore/root/server-setup/couchdb/data /root/restore/root/server-setup/couchdb/etc .
docker compose up -d --wait
```

`etc/` берём вместе с `data/`: там uuid сервера и пароль админа, который был в момент снимка.

Проверить базу без устройств (число документов):

```sh
. ./.env && curl -s -u "$COUCHDB_USER:$COUCHDB_PASSWORD" http://127.0.0.1:5984/obsidian-xet | python3 -m json.tool
```

## Сменить пароль CouchDB

`COUCHDB_PASSWORD` в `.env` используется только при самом первом старте, дальше пароль живёт в `etc/docker.ini`. Поэтому так:

```sh
cd ~/server-setup/couchdb && . ./.env
new=$(openssl rand -hex 24)
curl -s -u "$COUCHDB_USER:$COUCHDB_PASSWORD" -X PUT \
    "http://127.0.0.1:5984/_node/_local/_config/admins/$COUCHDB_USER" -d "\"$new\""
sed -i "s/^COUCHDB_PASSWORD=.*/COUCHDB_PASSWORD=$new/" .env
```

Затем новый пароль — в менеджер паролей и в настройки LiveSync на каждом устройстве (Remote Configuration → пароль).
