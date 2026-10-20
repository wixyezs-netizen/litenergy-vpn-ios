# LitEnergy VPN для iOS

Клиент сервиса LitEnergy VPN: добавьте подписку (ссылка, QR-код, вход по почте или через Telegram),
выберите сервер и подключайтесь одной кнопкой. Срок и трафик подписки видны на главном экране.

- iOS 15+, SwiftUI, туннель — NetworkExtension (Packet Tunnel).
- Ядро — [sing-box](https://github.com/SagerNet/sing-box) (libbox), GPL-3.0.
- Сборка — GitHub Actions: ядро → приложение → IPA → скриншоты в симуляторе → релиз по тегу `v*`.

## Подпись

Для работы VPN приложение и расширение `PacketTunnel` должны быть подписаны профилем с возможностью
**Network Extensions → Packet Tunnel** (платный аккаунт Apple Developer). Bundle ID: `com.litenergy.vpn`
и `com.litenergy.vpn.tunnel`.

Автоподпись в CI включается, если в Secrets репозитория заданы:
`IOS_P12_B64`, `IOS_P12_PASSWORD`, `IOS_PROFILE_APP_B64`, `IOS_PROFILE_TUNNEL_B64`.
Иначе выпускается неподписанный IPA. В приложении есть «Настройки → Диагностика VPN».

## Лицензия

GPL-3.0-or-later. Основано на sing-box и sing-box-for-apple (© SagerNet, GPL-3.0).
LitEnergy VPN не связан с проектом sing-box и не использует его название.
