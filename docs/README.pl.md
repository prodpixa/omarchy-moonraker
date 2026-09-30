# Moonraker Printer dla Omarchy (PL)

Widget do bara [Omarchy](https://omarchy.org), który pokazuje stan drukarki 3D
z Klipperem i [Moonrakerem](https://github.com/Arksine/moonraker). Działa
z każdą taką drukarką: Qidi (testowane na Q2), Voron, RatRig, Creality
K-series z Klipperem i innymi.

<p align="center"><img src="screenshots/08-printing.png" width="400"></p>

## Co potrafi

- **W barze** do wyboru trzy style:
  - sama ikonka,
  - procent i czas do końca,
  - procent, czas i wybrane temperatury (dysza, stół, komora).
- **Popup** po kliknięciu:
  - miniatura modelu,
  - czas wydruku, czas do końca i godzina zakończenia,
  - warstwa i zużyty filament,
  - temperatury: aktualna i docelowa.
- **Sterowanie**: pauza, wznowienie i anulowanie. Anulowanie trzeba kliknąć drugi raz, żeby potwierdzić.
- **Obsługa wszystkich stanów**:
  - brak konfiguracji, brak połączenia, brak lub zły API key,
  - Klipper uruchamia się, jest rozłączony albo w stanie shutdown,
  - bezczynność, nagrzewanie, druk, pauza, koniec, anulowanie, błąd.
  
  Zrzuty ekranu wszystkich stanów są w [STATES.md](STATES.md).
- **API key**: dzięki niemu działa przez VPN i z innych sieci.
- **Wygląd jak natywny**: kolory, czcionka i kontrolki pochodzą z Omarchy,
  więc widget zmienia się razem z `omarchy theme set`.
- **Zero zależności**: zapytania HTTP idą prosto z QML, bez curla i skryptów.

## Instalacja

```bash
omarchy plugin add https://github.com/prodpixa/omarchy-moonraker.git --enable
```

Potem kliknij ikonkę drukarki. Popup otworzy się na ustawieniach: wpisz adres
(np. `http://192.168.1.50`), opcjonalnie API key, i kliknij **Save & connect**.

## Obsługa

| Akcja | Efekt |
|-------|-------|
| Lewy klik | popup ze szczegółami |
| Prawy klik | zmiana stylu w barze: ikonka → postęp → postęp + temperatury |
| Środkowy klik | otwiera panel WWW drukarki (Fluidd/Mainsail) |
| `r` / `s` / `o` w popupie | odśwież / ustawienia / otwórz WWW |

## Ustawienia

Zapisują się we wpisie widgetu w `~/.config/omarchy/shell.json`:

| Klucz | Opis |
|-------|------|
| `url` | adres Moonrakera, np. `http://192.168.1.50` albo `http://drukarka.local:7125` |
| `apiKey` | klucz API wysyłany jako nagłówek `X-Api-Key` |
| `display` | styl w barze: `icon`, `progress` albo `full` |
| `temps` | temperatury w stylu `full`: `nozzle`, `bed`, `chamber` |
| `pollInterval` | co ile sekund odświeżać (domyślnie 5; w trakcie druku i przy otwartym popupie co najwyżej 3 s) |
| `hideWhenIdle` | ukryj widget, gdy nic się nie drukuje |
| `hideWhenOffline` | ukryj widget, gdy drukarka jest niedostępna |
| `chamberObject` | obiekt Klippera z temperaturą komory; pusty oznacza automatyczne wykrywanie |

Klucz API jest zapisany w `shell.json` otwartym tekstem, tak jak inne ustawienia widgetów Omarchy.

## Sterowanie ze skryptów

```bash
omarchy-shell pixa.moonraker status          # stan w JSON (bez API key)
omarchy-shell pixa.moonraker refresh
omarchy-shell pixa.moonraker cycleDisplay
omarchy-shell pixa.moonraker showSettings
omarchy-shell pixa.moonraker configure '{"display":"full"}'
```

## Dla deweloperów

- `dev/install.sh`: instaluje kopię roboczą i restartuje shell.
- `dev/mock_moonraker.py`: atrapa drukarki ze scenariuszami (`/mock/scenario/<nazwa>`).
- `dev/screenshots.sh`: przechodzi przez wszystkie stany i robi zrzuty do `docs/screenshots/`.

Więcej informacji:

- [ARCHITECTURE.md](ARCHITECTURE.md): jak to działa w środku,
- [TESTING.md](TESTING.md): testowanie, w tym lista kontrolna na prawdziwej drukarce.
