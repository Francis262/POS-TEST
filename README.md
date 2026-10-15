# POS-TEST — POS Zaključek Izmene

Android Flutter aplikacija za OCR skeniranje POS listkov in seštevanje zneskov. Vir je priložena originalna koda. **`lib/main.dart` je prekopiran brez sprememb logike ali funkcionalnosti.**

## Izdelaj APK brez lokalne namestitve Flutterja

1. Odpri [Actions → Build Android APK](https://github.com/Francis262/POS-TEST/actions/workflows/build-apk.yml).
2. Izberi **Run workflow** → **runner: ubuntu-latest** → **Run workflow**.
3. Odpri sproženi workflow run. Ko uspešno zaključi, spodaj pod **Artifacts** prenesi `pos-skener-apk`.
4. Razširi ZIP in datoteko `app-release.apk` prenesi na Android telefon (USB, Drive, ...).
5. Na telefonu odpri APK in po potrebi dovoli namestitev iz tega vira.

**Opomba glede kvote GitHub Actions:** gradnja na `ubuntu-latest` uporablja GitHub Actions minute. Če so izčrpane, je na voljo `self-hosted`, ki pa mora imeti ustrezno konfiguriran Flutter/Android SDK, Java in Android dovoljenja. Workflow ne zažene gradnje samodejno; potreben je ročni **Run workflow**.

## Vsebina

| Datoteka | Namen |
| --- | --- |
| `lib/main.dart` | Izvirna koda aplikacije — **nespremenjena** |
| `pubspec.yaml` | Originalne odvisnosti in osnovni Flutter metapodatki |
| `.github/workflows/build-apk.yml` | Ročno sprožena gradnja Android APK |
| `scripts/configure_android.py` | Nastavi dovoljenje CAMERA, oznako aplikacije in Android minSdk 24 |
| `.gitignore` | Ignorira ustvarjene Flutter/Android build datoteke |

Workflow namesti **Flutter 3.29.3** in **Java 17**, ustvari standardno Android ogrodje z `flutter create`, nastavi Android konfiguracijo in izvede `flutter build apk --release`. Android ogrodje je generirano med gradnjo, da v repozitoriju ostane izvorna aplikacijska koda brez nepotrebnih predlog.

## Lokalna izdelava (neobvezno)

Če imaš že nameščena Flutter in Android SDK, iz korenske mape projekta zaženi:

```bash
flutter create --platforms=android --project-name=pos_skener --org=si.lacantina --no-pub .
python scripts/configure_android.py
flutter pub get
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`

## Pomembne omejitve izvirne kode

To je prototip in ni finančno preverjena aplikacija. Izvirni algoritem lahko napačno prepozna zneske, zlasti zneske nad 999,99 EUR; ni opozarjanja na podvojene skene. Podatki se hranijo v `SharedPreferences`, zato nimajo zanesljive varnostne kopije. Pred prištevanjem vedno **preveri znesek na potrditvenem zaslonu**.

Gradnja uporablja privzeto podpisovanje Flutter Android predloge, ki je namenjeno testiranju. APK ni pripravljen za distribucijo prek Google Play; pri nadgradnjah z drugega runnerja lahko Android zaradi drugačnega podpisa zahteva odstranitev prejšnje različice in s tem izgubo lokalnih podatkov.
