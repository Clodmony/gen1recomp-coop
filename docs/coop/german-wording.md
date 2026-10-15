# German wording for the owner to check

The German cartridges (Rote, Blaue and Gelbe Edition, #25, #40) bring almost all of their
text with them: dialogue, names, items, moves and menus come from the
cartridge ([german.md](german.md)). This list holds the German the project
writes itself, for the owner to check. Write the better German in the last
column and the next session puts it in.

## The launcher (#41)

The launcher shows these words when its LANGUAGE is DEUTSCH (decision G14 in
[design.md](design.md)). They live in `src/coop/launcher/TextDe.lua`, keyed by
the English, and the table below is made from that file
(`luajit tools/launcher_strings.lua --markdown`); `tests/coop/launcher_ui_test.lua`
fails when the two differ, when a launcher string has no German, or when a
German page falls back to English.

How they were chosen: the player is addressed with "du", as the cartridges
do; the cartridge's own spelling is kept where it has the word (POKéMON,
ROT, BLAU, ORDEN); a cartridge is a "Modul"; the game names on the cartridge
tiles stay as each cartridge spells them (RED, ROT). `%s` and `%d` are filled
in by the launcher (a game, a name, a number) in the same order as in
English. Capitals are kept where the English is in capitals (buttons, labels).
The credit line of upstream's licence is not translated.

<!-- made by: luajit tools/launcher_strings.lua --markdown -->
### Tabs, top bar, footer

| English | German now | Better German |
| --- | --- | --- |
| PLAY | SPIELEN | |
| CAMPAIGNS | KAMPAGNEN | |
| CONTROLS | STEUERUNG | |
| SETTINGS | OPTIONEN | |
| HELP | HILFE | |
| QUIT | BEENDEN | |
| UNOFFICIAL FORK | INOFFIZIELLER FORK | |
| ← BACK | ← ZURÜCK | |
| OK | OK | |
| ARROWS MOVE · ENTER OR Z CONFIRM · ESC OR X BACK | PFEILE WÄHLEN · ENTER ODER Z BESTÄTIGT · ESC ODER X ZURÜCK | |
| D-PAD MOVE · A CONFIRM · B BACK | STEUERKREUZ WÄHLT · A BESTÄTIGT · B ZURÜCK | |
| CLICK TO CHOOSE · RIGHT CLICK GOES BACK | KLICKEN WÄHLT · RECHTSKLICK GEHT ZURÜCK | |
| TAP TO CHOOSE | TIPPEN WÄHLT | |

### PLAY

| English | German now | Better German |
| --- | --- | --- |
| YOUR ADVENTURE HUB | DEIN ABENTEUER-TREFFPUNKT | |
| Local saves · Direct connections | Lokale Spielstände · Direkte Verbindungen | |
| THE SAME STORY. YOUR OWN TEAM. | DIESELBE GESCHICHTE. DEIN EIGENES TEAM. | |
| One story. | Eine Geschichte. | |
| Two journeys. | Zwei Reisen. | |
| A shared campaign, from the first step to the final badge. | Eine gemeinsame Kampagne, vom ersten Schritt bis zum letzten Orden. | |
| YOUR TEAM | DEIN TEAM | |
| THEIR TEAM | SEIN TEAM | |
| YOUR CARTRIDGE | DEIN MODUL | |
| %s · Verified imports | %s · Geprüfte Importe | |
| English | Englisch | |
| German | Deutsch | |
| Ready | Bereit | |
| Import ROM | ROM importieren | |
| PLAY SOLO | ALLEIN SPIELEN | |
| PLAY SOLO → | ALLEIN SPIELEN → | |
| %s → %s · Matching cartridge required today | %s → %s · Vorerst nur mit demselben Modul | |
| HOST A CAMPAIGN | KAMPAGNE HOSTEN | |
| Your save. Friends can join anytime. | Dein Spielstand. Freunde kommen jederzeit dazu. | |
| JOIN A FRIEND | BEI FREUNDEN MITSPIELEN | |
| Nearby games or a direct address. | Spiele in der Nähe oder eine Adresse. | |
| COUCH CO-OP | SOFA-KOOP | |
| Two players. One screen. Comes later. | Zwei Spieler. Ein Bildschirm. Kommt später. | |
| PLANNED | GEPLANT | |
| IMPORT ROM | ROM IMPORTIEREN | |
| %s has no imported cartridge on this device. | Für %s ist auf diesem Gerät kein Modul importiert. | |
| LAST SESSION | LETZTE SITZUNG | |
| HOST AGAIN | WIEDER HOSTEN | |
| REJOIN | WIEDER BEITRETEN | |
| %s · %s · Hosted on this device | %s · %s · Auf diesem Gerät gehostet | |
| no players yet | noch keine Spieler | |
| %s · Joined at %s | %s · Beigetreten bei %s | |
| %s is ready to play. | %s ist bereit. | |

### Solo

| English | German now | Better German |
| --- | --- | --- |
| Play %s solo | %s allein spielen | |
| Your own save, apart from every campaign. | Dein eigener Spielstand, getrennt von jeder Kampagne. | |
| CONTINUE | WEITER | |
| NEW GAME | NEUES SPIEL | |
| IMPORT AGAIN | NEU IMPORTIEREN | |
| BACK | ZURÜCK | |
| %s · BADGES %d · %s | %s · ORDEN %d · %s | |
| A new save slot. The old save stays on disk. | Ein neuer Speicherplatz. Der alte Spielstand bleibt erhalten. | |
| The game starts from its title screen. | Das Spiel beginnt mit seinem Titelbild. | |
| Import this cartridge's ROM again. | Das ROM dieses Moduls neu importieren. | |

### Controls

| English | German now | Better German |
| --- | --- | --- |
| Controls | Steuerung | |
| The game's buttons, and each player's device for couch co-op. | Die Knöpfe des Spiels und das Gerät jedes Spielers für den Sofa-Koop. | |
| IN THE GAME | IM SPIEL | |
| UP | OBEN | |
| DOWN | UNTEN | |
| LEFT | LINKS | |
| RIGHT | RECHTS | |
| A | A | |
| B | B | |
| START | START | |
| SELECT | SELECT | |
| RESET BINDINGS | BELEGUNG ZURÜCKSETZEN | |
| A key and a pad button for each. The game's own CONTROLS menu shows the same. | Je eine Taste und ein Controller-Knopf. Das STEUERUNG-Menü des Spiels zeigt dasselbe. | |
| Press a key or a pad button for %s. Esc cancels. | Drücke eine Taste oder einen Controller-Knopf für %s. Esc bricht ab. | |
| PLAYER DEVICES | GERÄTE DER SPIELER | |
| PLAYER %d | SPIELER %d | |
| KEYBOARD | TASTATUR | |
| PAD | CONTROLLER | |
| ANY DEVICE | JEDES GERÄT | |
| NO DEVICE | KEIN GERÄT | |
| CLEAR DEVICES | GERÄTE VERGESSEN | |
| Player %d: press A on your pad, or Enter for the keyboard. Esc cancels. | Spieler %d: drücke A auf deinem Controller oder Enter für die Tastatur. Esc bricht ab. | |
| CONNECTED PADS | VERBUNDENE CONTROLLER | |
| No pad connected. | Kein Controller verbunden. | |
| P%d | S%d | |
| Couch co-op seats each player at the device claimed here, remembered by pad. Without a claim, player 1 uses any device, as in solo play. | Beim Sofa-Koop spielt jeder an dem hier gewählten Gerät; der Launcher merkt sich den Controller. Ohne Wahl nutzt Spieler 1 jedes Gerät, wie beim Alleinspielen. | |
| IN THE LAUNCHER | IM LAUNCHER | |
| MOVE | WÄHLEN | |
| Arrows or WASD · D-pad or stick | Pfeile oder WASD · Steuerkreuz oder Stick | |
| CONFIRM | OK | |
| Z, Enter or Space · A or START | Z, Enter oder Leertaste · A oder START | |
| X, Esc or Backspace · B | X, Esc oder Rücktaste · B | |
| MOUSE | MAUS | |
| A click chooses, a right click goes back. | Ein Klick wählt, ein Rechtsklick geht zurück. | |
| TOUCH | TOUCH | |
| A tap chooses. | Tippen wählt. | |

### Settings

| English | German now | Better German |
| --- | --- | --- |
| Settings | Optionen | |
| The launcher's own settings, then the game's. A pressed value moves on; left and right step it. | Erst die Optionen des Launchers, dann die des Spiels. Drücken schaltet einen Wert weiter; links und rechts gehen Schritt für Schritt. | |
| LAUNCHER | LAUNCHER | |
| VIDEO | BILD | |
| AUDIO | TON | |
| GAME | SPIEL | |
| LANGUAGE | SPRACHE | |
| The language of the launcher. A game's text follows its cartridge. | Die Sprache des Launchers. Der Text eines Spiels folgt seinem Modul. | |
| THEME | FARBEN | |
| Light or dark colours for the launcher. | Helle oder dunkle Farben für den Launcher. | |
| LIGHT | HELL | |
| DARK | DUNKEL | |
| WINDOW | FENSTER | |
| A window, or the whole screen. | Ein Fenster oder der ganze Bildschirm. | |
| WINDOWED | FENSTER | |
| BORDERLESS | VOLLBILD | |
| INTEGER SCALE | GANZZAHLIGE SKALIERUNG | |
| Draw the game at an exact multiple of its pixels; OFF fits the window. | Zeichnet das Spiel in einem genauen Vielfachen seiner Pixel; AUS passt es ins Fenster. | |
| MUSIC | MUSIK | |
| SOUND | GERÄUSCHE | |
| 0 to 7. | 0 bis 7. | |
| TEXT SPEED | TEXT-TEMPO | |
| How fast text appears. | Wie schnell Text erscheint. | |
| FAST | SCHNELL | |
| MEDIUM | MITTEL | |
| SLOW | LANGSAM | |
| BATTLE ANIMATION | KAMPFANIMATION | |
| Attack animations in battle. | Angriffsanimationen im Kampf. | |
| BATTLE STYLE | KAMPFSTIL | |
| SHIFT asks before the next Pokemon; SET does not. | WECHSEL fragt vor dem nächsten POKéMON; FOLGEND nicht. | |
| SHIFT | WECHSEL | |
| SET | FOLGEND | |
| Video, sound and game options are in each game's own OPTIONS menu. | Bild, Ton und Spieloptionen findest du im Menü OPTIONEN jedes Spiels. | |
| The game's options are the ones its own OPTIONS menu shows; a change here is a change there. | Die Spieloptionen sind dieselben wie im Menü OPTIONEN des Spiels; eine Änderung hier gilt auch dort. | |

### Saves (#6)

| English | German now | Better German |
| --- | --- | --- |
| SAVES | SPIELSTÄNDE | |
| %s saves | Spielstände %s | |
| Each slot is one adventure. The game continues the active one. | Jeder Platz ist ein Abenteuer. Das Spiel setzt den aktiven fort. | |
| PLAY → | SPIELEN → | |
| EXPORT | EXPORTIEREN | |
| IMPORT | IMPORTIEREN | |
| + NEW SAVE | + NEUER SPIELSTAND | |
| IMPORT .SAV | .SAV IMPORTIEREN | |
| Empty slot | Leerer Platz | |
| ACTIVE | AKTIV | |
| BADGES %d · POKéDEX %d · TIME %s | ORDEN %d · POKéDEX %d · ZEIT %s | |
| No save yet: the game starts from its title screen. | Noch kein Spielstand: das Spiel beginnt bei seinem Titelbild. | |
| Campaign: %s (entered from CAMPAIGNS) | Kampagne: %s (Start über KAMPAGNEN) | |
| No saves for %s on this device yet. | Noch keine Spielstände für %s auf diesem Gerät. | |
| 1 save slot | 1 Speicherplatz | |
| %d save slots | %d Speicherplätze | |
| A .sav is the cartridge's own format, as an emulator or a cartridge reader writes it. Exports go to the exports folder of this device. | Eine .sav ist das Format des Moduls, wie ein Emulator oder ein Modul-Lesegerät es schreibt. Exporte landen im Ordner exports dieses Geräts. | |
| Delete this save? | Diesen Spielstand löschen? | |
| Delete %s? The save is removed from this device for good. | %s löschen? Der Spielstand wird endgültig von diesem Gerät entfernt. | |
| this empty slot | diesen leeren Platz | |
| A bigger file than expected | Eine größere Datei als erwartet | |
| %s is %d bytes; a cartridge save is %d. Import the first %d bytes? | %s hat %d Bytes; ein Modul-Spielstand hat %d. Die ersten %d Bytes importieren? | |
| Import a save | Spielstand importieren | |
| A .sav for %s becomes a new save slot. Nothing is uploaded. | Eine .sav für %s wird ein neuer Speicherplatz. Nichts wird hochgeladen. | |
| Drop the .sav file on this window, or type its path and press ENTER. | Zieh die .sav-Datei auf dieses Fenster oder tipp ihren Pfad ein und drück ENTER. | |
| Drop the .sav file on this window. | Zieh die .sav-Datei auf dieses Fenster. | |
| 32 KB in the cartridge's format (.sav, .srm). The save's trainer, team, items and progress come along; the slot it lands in is made the active one. | 32 KB im Format des Moduls (.sav, .srm). Trainer, Team, Items und Fortschritt kommen mit; der Platz, in dem sie landen, wird der aktive. | |
| This slot cannot be exported. | Dieser Platz kann nicht exportiert werden. | |
| This game has no room for another save. | Dieses Spiel hat keinen Platz für einen weiteren Spielstand. | |
| Exported %s to %s | %s exportiert nach %s | |
| Could not export: %s | Export fehlgeschlagen: %s | |
| Deleted %s. | %s gelöscht. | |
| Could not delete: %s | Löschen fehlgeschlagen: %s | |
| Imported %s into a new save slot. | %s in einen neuen Speicherplatz importiert. | |
| Could not import %s: %s | %s konnte nicht importiert werden: %s | |
| Import the %s ROM before its saves. | Importiere erst das ROM von %s, dann seine Spielstände. | |
| a campaign | eine Kampagne | |

### Help

| English | German now | Better German |
| --- | --- | --- |
| A little help before you go | Ein wenig Hilfe vor dem Start | |
| Co-op connects directly to the hosting device. | Koop verbindet direkt mit dem Gerät des Hosts. | |
| CONNECTING | VERBINDEN | |
| At home | Zu Hause | |
| Use Nearby or the host's home address. Both devices use the same network. | Nimm die Liste in der Nähe oder die Heimnetz-Adresse des Hosts. Beide Geräte sind im selben Netz. | |
| Over the internet | Übers Internet | |
| Use a VPN address, or forward UDP 24680 on the hosting network. | Nimm eine VPN-Adresse oder leite im Netz des Hosts UDP 24680 weiter. | |
| Cartridges | Module | |
| Both players need the same game, ROM and language. Red with Blue comes later. | Beide brauchen dasselbe Spiel, ROM und dieselbe Sprache. Rot mit Blau kommt später. | |
| SESSION LOGS | SITZUNGSPROTOKOLLE | |
| SHARE LOGS | PROTOKOLLE TEILEN | |
| ON | AN | |
| OFF | AUS | |
| Shared logs go to the players of a session. They hold trainer names and addresses: never post them. | Geteilte Protokolle gehen an die Spieler einer Sitzung. Sie enthalten Trainernamen und Adressen: nie veröffentlichen. | |
| OPEN LOGS FOLDER | PROTOKOLLORDNER ÖFFNEN | |
| The logs are in %s | Die Protokolle liegen in %s | |
| ABOUT | ÜBER | |
| Co-op fork: github.com/Clodmony/gen1recomp-coop | Koop-Fork: github.com/Clodmony/gen1recomp-coop | |
| The co-op fork is written by AI coding agents directed by the repository owner. | Der Koop-Fork wird von KI-Programmieragenten geschrieben, angeleitet vom Inhaber des Repositorys. | |
| Plain Pixel font by Douglas Vautour, CC BY 4.0. | Schrift Plain Pixel von Douglas Vautour, CC BY 4.0. | |
| Pokemon is a trademark of Nintendo, Creatures and GAME FREAK. This project is not affiliated with them. | POKéMON ist eine Marke von Nintendo, Creatures und GAME FREAK. Dieses Projekt steht in keiner Verbindung zu ihnen. | |

### Import

| English | German now | Better German |
| --- | --- | --- |
| Bring your cartridge | Bring dein Modul mit | |
| Import a verified ROM on this device. Nothing is uploaded. | Importiere ein geprüftes ROM auf diesem Gerät. Nichts wird hochgeladen. | |
| %s · NOT IMPORTED | %s · NICHT IMPORTIERT | |
| Drop the ROM file on this window, or type its path and press ENTER. | Zieh die ROM-Datei auf dieses Fenster oder tippe ihren Pfad und drücke ENTER. | |
| Importing a ROM on this device comes later. | ROMs auf diesem Gerät zu importieren kommt später. | |
| Clean dumps of Pokemon Red, Blue and Yellow (US) and of the German Rote, Blaue and Gelbe Edition; .zip and .7z where the system opens them. | Saubere Dumps von POKéMON Rot, Blau und Gelb (US) und der deutschen Roten, Blauen und Gelben Edition; .zip und .7z, wo das System sie öffnet. | |
| Importing %s | %s wird importiert | |
| Preparing | Vorbereitung | |
| Could not open %s | %s ließ sich nicht öffnen | |
| Import failed: %s | Import fehlgeschlagen: %s | |
| The dropped file could not be read. | Die Datei ließ sich nicht lesen. | |
| The file could not be read. | Die Datei ließ sich nicht lesen. | |
| That archive is too big to hold one Game Boy ROM. | Das Archiv ist zu groß für ein einzelnes Game-Boy-ROM. | |
| Expected a 1 MiB Game Boy ROM; this file is %.2f MiB. | Erwartet wird ein Game-Boy-ROM mit 1 MiB; diese Datei hat %.2f MiB. | |
| Unknown ROM. This needs a clean US Pokemon Red, Blue or Yellow dump, or a German Rote, Blaue or Gelbe Edition (SHA-1 %s). | Unbekanntes ROM. Nötig ist ein sauberer Dump von POKéMON Rot, Blau oder Gelb (US) oder der Roten, Blauen oder Gelben Edition (SHA-1 %s). | |
| %s is not playable here: this launcher plays Red, Blue and Yellow, in English or German. | %s läuft hier nicht: Dieser Launcher spielt Rot, Blau und Gelb, auf Englisch oder Deutsch. | |

### Campaigns

| English | German now | Better German |
| --- | --- | --- |
| Your campaigns | Deine Kampagnen | |
| A separate adventure for each group. Solo saves stay separate. | Ein eigenes Abenteuer für jede Gruppe. Solo-Spielstände bleiben getrennt. | |
| Choose your campaign | Wähle deine Kampagne | |
| Host %s with a matching cartridge. Your friends can join later. | Hoste %s mit passendem Modul. Deine Freunde kommen später dazu. | |
| HOST | HOSTEN | |
| HOST → | HOSTEN → | |
| RENAME | UMBENENNEN | |
| DELETE | LÖSCHEN | |
| %s · %s | %s · %s | |
| Last hosted %s | Zuletzt gehostet %s | |
| Never hosted | Noch nie gehostet | |
| No campaigns on this device yet. | Noch keine Kampagnen auf diesem Gerät. | |
| No campaigns for this cartridge yet. | Noch keine Kampagnen für dieses Modul. | |
| Deleted %s. A backup is kept. | %s gelöscht. Eine Sicherung bleibt. | |
| RESTORE BACKUP | SICHERUNG HOLEN | |
| Restored %s. | %s ist wieder da. | |
| The backup could not be restored. | Die Sicherung ließ sich nicht zurückholen. | |
| The campaign could not be deleted. | Die Kampagne ließ sich nicht löschen. | |

### #13: a campaign file the host refuses

| English | German now | Better German |
| --- | --- | --- |
| This campaign was saved by a newer build. Update to host it. | Diese Kampagne stammt aus einer neueren Version. Aktualisiere, um sie zu hosten. | |
| This campaign's file cannot be read. It was left as it is. | Die Datei dieser Kampagne ist nicht lesbar. Sie bleibt, wie sie ist. | |
| Its backup: %s | Ihre Sicherung: %s | |
| Your world from the campaign could not be read. | Deine Welt aus der Kampagne ist nicht lesbar. | |
| Your world could not be written: %s | Deine Welt ließ sich nicht schreiben: %s | |
| 1 campaign on this device | 1 Kampagne auf diesem Gerät | |
| %d campaigns on this device | %d Kampagnen auf diesem Gerät | |
| NEW CAMPAIGN | NEUE KAMPAGNE | |
| + NEW CAMPAIGN | + NEUE KAMPAGNE | |
| Start a shared adventure | Starte ein gemeinsames Abenteuer | |
| CAMPAIGN NAME | KAMPAGNENNAME | |
| TRAINER NAME | TRAINERNAME | |
| RIVAL NAME | NAME DES RIVALEN | |
| PLAYER 2 NAME | NAME VON SPIELER 2 | |
| ASK IN THE GAME | IM SPIEL FRAGEN | |
| Name the campaign, the trainer you will play and the rival. | Benenne die Kampagne, deinen Trainer und den Rivalen. | |
| EDIT | ÄNDERN | |
| CARTRIDGE | MODUL | |
| A new campaign uses a save slot of its own. Your solo progress stays separate. | Eine neue Kampagne hat einen eigenen Speicherplatz. Dein Solo-Fortschritt bleibt getrennt. | |
| Direct play · UDP 24680 | Direktes Spiel · UDP 24680 | |
| CREATE AND HOST | ERSTELLEN UND HOSTEN | |
| CREATE AND HOST → | ERSTELLEN UND HOSTEN → | |
| %s CO-OP | %s KOOP | |
| Delete this campaign? | Diese Kampagne löschen? | |
| The campaign leaves the list. Its last state is kept as a backup you can restore. | Die Kampagne verschwindet aus der Liste. Ihr letzter Stand bleibt als Sicherung, die du zurückholen kannst. | |
| CANCEL | ABBRECHEN | |
| DELETE AND KEEP BACKUP | LÖSCHEN, SICHERUNG BEHALTEN | |

### Hosting

| English | German now | Better German |
| --- | --- | --- |
| Hosting %s · %s · Direct connection | Du hostest %s · %s · Direkte Verbindung | |
| PLAYERS · %d / %d | SPIELER · %d / %d | |
| Host · this device | Host · dieses Gerät | |
| Connected trainer | Verbundener Trainer | |
| You can enter now. Friends can join later. | Du kannst jetzt los. Freunde kommen später dazu. | |
| FRIENDS JOIN AT | FREUNDE TRETEN BEI UNTER | |
| VPN | VPN | |
| HOME NETWORK | HEIMNETZ | |
| INTERNET | INTERNET | |
| THIS DEVICE | DIESES GERÄT | |
| NAME | NAME | |
| %s · LAST USED | %s · ZULETZT GENUTZT | |
| COPY | KOPIEREN | |
| Copied %s. | %s kopiert. | |
| Same network, VPN, or a forwarded game port. | Selbes Netz, VPN oder ein weitergeleiteter Spiel-Port. | |
| The network port is busy: only this device can join. | Der Netzwerk-Port ist belegt: Nur dieses Gerät kann beitreten. | |
| No network found: only this device can join. | Kein Netzwerk gefunden: Nur dieses Gerät kann beitreten. | |
| STOP HOSTING | HOSTEN BEENDEN | |
| ENTER THE WORLD | IN DIE WELT | |
| ENTER WITH 2 PLAYERS | ZU ZWEIT IN DIE WELT | |
| ENTER THE WORLD → | IN DIE WELT → | |
| Close this session? | Diese Sitzung beenden? | |
| 1 friend will return to their launcher. The session cannot pass to another player. | 1 Freund kehrt zu seinem Launcher zurück. Die Sitzung kann nicht an einen anderen Spieler gehen. | |
| %d friends will return to their launcher. The session cannot pass to another player. | %d Freunde kehren zu ihrem Launcher zurück. Die Sitzung kann nicht an einen anderen Spieler gehen. | |
| CLOSE SESSION | SITZUNG BEENDEN | |
| The session is closed. | Die Sitzung ist beendet. | |
| The session stopped. | Die Sitzung wurde beendet. | |

### Join

| English | German now | Better German |
| --- | --- | --- |
| Join a friend | Bei Freunden mitspielen | |
| Find a nearby campaign or use the host's address. | Finde eine Kampagne in der Nähe oder nimm die Adresse des Hosts. | |
| NEARBY | IN DER NÄHE | |
| %s · %s · %s | %s · %s · %s | |
| 1 player | 1 Spieler | |
| %d players | %d Spieler | |
| Your cartridge fits | Dein Modul passt | |
| Joins with %s | Tritt mit %s bei | |
| Needs %s | Braucht %s | |
| CHECK | PRÜFEN | |
| Nearby search is off on this device. | Die Suche in der Nähe ist auf diesem Gerät aus. | |
| Searching the network... | Suche im Netzwerk... | |
| RECENT ADDRESSES | LETZTE ADRESSEN | |
| BY ADDRESS | PER ADRESSE | |
| A host name or address, with an optional :port. The default port is 24680. | Ein Hostname oder eine Adresse, wahlweise mit :Port. Der Standard-Port ist 24680. | |
| ENTER ADDRESS → | ADRESSE EINGEBEN → | |
| HOST NAME OR ADDRESS | HOSTNAME ODER ADRESSE | |
| Your cartridge: %s | Dein Modul: %s | |
| %s plays %s. Import %s on PLAY to join. | %s spielt %s. Importiere %s unter SPIELEN, um beizutreten. | |
| The host | Der Host | |

### Connecting

| English | German now | Better German |
| --- | --- | --- |
| Calling the host | Der Host wird gerufen | |
| Could not reach the host | Host nicht erreichbar | |
| You found your friend | Freund gefunden | |
| The cartridge does not fit | Das Modul passt nicht | |
| The host said no | Der Host hat abgelehnt | |
| The session ended | Die Sitzung ist vorbei | |
| Host found | Host gefunden | |
| Co-op protocol matches | Koop-Protokoll passt | |
| Cartridge fits | Modul passt | |
| Cartridge fits · %s / %s | Modul passt · %s / %s | |
| Cartridge does not fit | Modul passt nicht | |
| Calling the host... | Rufe den Host... | |
| No answer yet. Trying again in %d s. | Noch keine Antwort. Neuer Versuch in %d s. | |
| Gives up in %d:%02d | Gibt auf in %d:%02d | |
| No host answered within a minute. | Innerhalb einer Minute hat kein Host geantwortet. | |
| Joining... | Trete bei... | |
| This device is %s in that campaign. | Dieses Gerät ist %s in dieser Kampagne. | |
| TRY NOW | JETZT VERSUCHEN | |
| TRY AGAIN | NOCHMAL VERSUCHEN | |
| NEW NAME | NEUER NAME | |
| JOIN AS %s | ALS %s BEITRETEN | |
| JOIN WITH 2 PLAYERS | ZU ZWEIT BEITRETEN | |
| USE %s | %s NEHMEN | |
| The host plays %s in %s, this game is %s in %s. Both need the same language. | Der Host spielt %s auf %s, dieses Spiel ist %s auf %s. Beide brauchen dieselbe Sprache. | |
| The host plays %s. This game is %s. | Der Host spielt %s. Dieses Spiel ist %s. | |
| The host's %s ROM is another dump than this one. | Das %s-ROM des Hosts ist ein anderer Dump als dieses. | |
| The host runs another version of this co-op game. Both need the same one. | Der Host hat eine andere Version dieses Koop-Spiels. Beide brauchen dieselbe. | |
| The session is full. | Die Sitzung ist voll. | |
| The host is closing the session. | Der Host beendet gerade die Sitzung. | |
| The host dropped this game: it sent too much at once. | Der Host hat dieses Spiel getrennt: Es hat zu viel auf einmal gesendet. | |
| The host turned this game away (%s). | Der Host hat dieses Spiel abgewiesen (%s). | |
| The host closed the session. | Der Host hat die Sitzung beendet. | |
| The link was lost (%s). | Die Verbindung ist abgerissen (%s). | |
| You left the session. | Du hast die Sitzung verlassen. | |
| You closed the session. | Du hast die Sitzung beendet. | |
| The connection to the host was lost. | Die Verbindung zum Host ist abgerissen. | |
| Is the VPN on, on both devices? | Ist das VPN auf beiden Geräten an? | |
| Are both in the same VPN network? | Sind beide im selben VPN-Netz? | |
| Is the host still hosting? | Hostet der Host noch? | |
| Are both on the same Wi-Fi or network? | Sind beide im selben WLAN oder Netz? | |
| Does the host's firewall let UDP %d in? | Lässt die Firewall des Hosts UDP %d herein? | |
| Does the host's router forward UDP %d to the host? | Leitet der Router des Hosts UDP %d an den Host weiter? | |
| Is the address the host's current one? | Ist das die aktuelle Adresse des Hosts? | |
| Is a game on this device hosting? | Hostet ein Spiel auf diesem Gerät? | |
| Is the address spelled right? | Ist die Adresse richtig geschrieben? | |

### Text entry

| English | German now | Better German |
| --- | --- | --- |
| Type on the keyboard, or pick the letters with a pad or a tap. START or END finishes. | Tippe auf der Tastatur oder wähle die Zeichen mit Controller oder Finger. START oder ENDE schließt ab. | |
| SPACE | LEER | |
| DEL | LÖSCH | |
| END | ENDE | |
<!-- end of the made part -->

## The games (#25)

A German game shows the engine's own lines in the cartridge's words where the
cartridge has them and in the fork's wording for the rest
([german.md](german.md), decision G15). Upstream already prints most battle,
item and field lines from the cartridge's text labels; the list below is what
`src/coop/game/German.lua` adds on top. Keys with a `context|` prefix are the
same English word on a screen where the cartridge uses another word.

Lines the cartridge has but the engine spells differently are composed from
the cartridge's labels (an EXP gain from `_GainedText` + `_ExpPointsText`);
their German is the cartridge's and is not reproduced here. "greatly rose"
and the boosted EXP line have no German label and use the fork's wording.
`PP` is written `AP` on the German cartridge, which keeps no label for it.

<!-- made by: luajit tools/game_strings.lua --markdown -->
### From the cartridge

These come from the player's own cartridge at import: nothing to check,
listed so the owner sees which lines are the cartridge's.

| English | Read from |
|---|---|
| %s's NEST | MonsNestText, row 1 |
| %s's PC | PlayersPCText, row 1 |
| <PK><MN>LEAGUE | PKMNLeaguePCText, row 1 |
| ACCURACY | StatModTextStrings, row 5 |
| AREA | PokedexMenuItemsText, row 3 |
| AREA UNKNOWN | AreaUnknownText, row 1 |
| ATTACK | StatModTextStrings, row 1 |
| BACK | OptionMenuCancelText, row 1 |
| BADGES | SaveScreenInfoText, row 2 |
| BAIT | SafariZoneBattleMenuText, row 1, word 2 |
| BALLx | SafariZoneBattleMenuText, row 1, word 1 |
| BATTLE ANIMATION | BattleAnimationOptionText, row 1; Yellow: AllOptionsText, row 2 |
| BATTLE STYLE | BattleStyleOptionText, row 1; Yellow: AllOptionsText, row 3 |
| BILL'S PC | BillsPCText, row 1 |
| BOX No. | BoxNoText, row 1 |
| BOX No.%d | BoxNoText, row 1 |
| BUY | BuySellQuitText, row 1 |
| CANCEL | ListMenuCancelText, row 1 |
| CHANGE BOX | BillsPCMenuText, row 4 |
| COIN | PrintPrizePrice.CoinString, row 1 |
| CONTENTS | PokedexContentsText, row 1 |
| CONTINUE | ContinueText, row 1 |
| CRY | PokedexMenuItemsText, row 2 |
| CUT | the import's own data (an item, a move, a preset name) |
| Congrats! This | DiplomaCongrats, row 1 |
| DATA | PokedexMenuItemsText, row 1 |
| DEFENSE | StatModTextStrings, row 2 |
| DEPOSIT | DepositPCText, row 1 |
| DEPOSIT <PK><MN> | BillsPCMenuText, row 2 |
| DEPOSIT ITEM | PlayersPCMenuEntries, row 2 |
| DIG | the import's own data (an item, a move, a preset name) |
| EVADE | StatModTextStrings, row 6 |
| EXP POINTS | StatusScreenExpText, row 1 |
| Enemy %s | EnemyText, row 1 |
| FAST | TextSpeedOptionText, row 2, word 1; Yellow: OptionsMenu_TextSpeed.Fast, word 2 |
| FIGHT | BattleMenuText, row 1, word 1 |
| FLASH | the import's own data (an item, a move, a preset name) |
| FLY | the import's own data (an item, a move, a preset name) |
| HALL OF FAME | HallOfFameText, row 1 |
| HALL OF FAME No | HallOfFameNoText, row 1 |
| HEAL | TwoOptionMenuStrings.HealCancelMenu, row 1 |
| ITEM | BattleMenuText, row 2, word 1 |
| LEVEL UP | StatusScreenExpText, row 2 |
| LEVEL/ | HoFMonInfoText, row 1 |
| LOG OFF | PlayersPCMenuEntries, row 4 |
| MEDIUM | TextSpeedOptionText, row 2, word 2; Yellow: OptionsMenu_TextSpeed.Mid, word 2 |
| MONEY | MoneyText, row 1 |
| MONEY/¥%d | TrainerInfo_NameMoneyTimeText, row 2 |
| NAME/%s | TrainerInfo_NameMoneyTimeText, row 1 |
| NEW GAME | NewGameText, row 1 |
| NEW NAME | the import's own data (an item, a move, a preset name) |
| NICKNAME? | NicknameTextString, row 1 |
| NO | TwoOptionMenuStrings.YesNoMenu, row 2 |
| Now saving... | NowSavingString, row 1; Yellow: no such row |
| OFF | BattleAnimationOptionText, row 2, word 2; Yellow: OptionsMenu_BattleAnimations.Off, word 2 |
| ON | BattleAnimationOptionText, row 2, word 1; Yellow: OptionsMenu_BattleAnimations.On, word 2 |
| OPTION | StartMenuOptionText, row 1 |
| OT/ | TypesIDNoOTText, row 4 |
| OT/%s | TypesIDNoOTText, row 4 |
| OWN | PokedexOwnText, row 1 |
| PLAY TIME | HoFPlayTimeText, row 1 |
| PLAYER | SaveScreenInfoText, row 1 |
| POKé BALL | the import's own data (an item, a move, a preset name) |
| POKéDEX | StartMenuPokedexText, row 1 |
| POKéDEX. | the import's own data (an item, a move, a preset name) |
| POKéMON | StartMenuPokemonText, row 1 |
| PRINT BOX | Yellow: BillsPCMenuText, row 5 |
| PRNT | Yellow: PokedexMenuItemsText, row 4 |
| PROF.OAK's PC | OaksPCText, row 1 |
| RELEASE <PK><MN> | BillsPCMenuText, row 3 |
| RIVAL's NAME? | RivalsTextString, row 1 + NameTextString, row 1 |
| RUN | BattleMenuText, row 2, word 2 |
| SAVE | StartMenuSaveText, row 1 |
| SEE YA! | BillsPCMenuText, row 5; Yellow: BillsPCMenuText, row 6 |
| SEEN | PokedexSeenText, row 1 |
| SEEN %3d  OWN %3d | PokedexSeenText, row 1 + PokedexOwnText, row 1 |
| SELL | BuySellQuitText, row 2 |
| SET | BattleStyleOptionText, row 2, word 2; Yellow: OptionsMenu_BattleStyle.Set, word 2 |
| SHIFT | BattleStyleOptionText, row 2, word 1; Yellow: OptionsMenu_BattleStyle.Shift, word 2 |
| SLOW | TextSpeedOptionText, row 2, word 3; Yellow: OptionsMenu_TextSpeed.Slow, word 2 |
| SOFTBOILED | the import's own data (an item, a move, a preset name) |
| SOMEONE'S PC | SomeonesPCText, row 1 |
| SPECIAL | StatModTextStrings, row 4 |
| SPEED | StatModTextStrings, row 3 |
| STATS | PokemonMenuEntries, row 1 |
| STATUS/ | StatusText, row 1 |
| STRENGTH | the import's own data (an item, a move, a preset name) |
| SURF | the import's own data (an item, a move, a preset name) |
| SWITCH | PokemonMenuEntries, row 2 |
| TELEPORT | the import's own data (an item, a move, a preset name) |
| TEXT SPEED | TextSpeedOptionText, row 1; Yellow: AllOptionsText, row 1 |
| THROW ROCK | SafariZoneBattleMenuText, row 2, word 1 |
| TIME | SaveScreenInfoText, row 4 |
| TIME/  %d:%02d | TrainerInfo_NameMoneyTimeText, row 3 |
| TOSS | UseTossText, row 2 |
| TOSS ITEM | PlayersPCMenuEntries, row 3 |
| TRADE | TwoOptionMenuStrings.TradeCancelMenu, row 1 |
| TYPE/ | TypeText, row 1 |
| TYPE1/ | TypesIDNoOTText, row 1 |
| TYPE2/ | TypesIDNoOTText, row 2 |
| The trade was / cancelled. | TradeCanceled |
| USE | UseTossText, row 1 |
| WHICH TECHNIQUE? | WhichTechniqueString, row 1 |
| WITHDRAW | WithdrawPCText, row 1 |
| WITHDRAW <PK><MN> | BillsPCMenuText, row 1 |
| WITHDRAW ITEM | PlayersPCMenuEntries, row 1 |
| Waiting...! | WaitingText, row 1 |
| YES | TwoOptionMenuStrings.YesNoMenu, row 1 |
| YOUR NAME? | YourTextString, row 1 + NameTextString, row 1 |
| cableclub\|CANCEL | CancelTextString, row 1 |
| completed your | DiplomaCongrats, row 4 |
| diploma certifies | DiplomaCongrats, row 2 |
| disabled! | DisabledText, row 1 |
| pokedex\|QUIT | PokedexMenuItemsText, row 4; Yellow: PokedexMenuItemsText, row 5 |
| shop\|QUIT | BuySellQuitText, row 3 |
| status\|ATTACK | PrintStatsBox.StatsText, row 1 |
| status\|DEFENSE | PrintStatsBox.StatsText, row 2 |
| status\|SPECIAL | PrintStatsBox.StatsText, row 4 |
| status\|SPEED | PrintStatsBox.StatsText, row 3 |
| that you have | DiplomaCongrats, row 3 |
|  / For some people, / POKéMON are / pets. Others use / them for fights. / Myself... / I study POKéMON / as a profession. | _OakSpeechText2B |
| %s / dug a hole! | _DugAHoleText |
| %s / flew up high! | _FlewUpHighText |
| %s / is glowing! | _SkyAttackGlowingText |
| %s / lowered its head! | _LoweredItsHeadText |
| %s / made a whirlwind! | _MadeWhirlwindText |
| %s / took in sunlight! | _TookInSunlightText |
| %s blacked / out! | _PlayerBlackedOutText, page 2 |
| %s found / %d coins! | _FoundHiddenCoinsText |
| %s gained / %d EXP. Points! | _GainedText + _ExpPointsText |
| %s gained / with EXP.ALL, / %d EXP. Points! | _GainedText + _WithExpAllText + _ExpPointsText |
| %s got off / the BICYCLE. | _GotOffBicycleText1 + _GotOffBicycleText2 |
| %s got on / the BICYCLE! | _GotOnBicycleText1 + _GotOnBicycleText2 |
| %s grew / to level %d! | _GrewLevelText |
| %s has no / moves left! | _NoMovesLeftText |
| %s is / about to use / %s! | _TrainerAboutToUseText, page 1 |
| %s is / already out! | _AlreadyOutText |
| %s is / taken out. / Got %s. | _MonIsTakenOutText |
| %s is out of / useable POKéMON! | _PlayerBlackedOutText, page 1 |
| %s is too / scared to move! | _ScaredText |
| %s learned / %s! | _LearnedMove1Text |
| %s saved / the game! | _GameSavedText |
| %s sent / out %s! | _TrainerSentOutText |
| %s wants / to fight! | _TrainerWantsToFightText |
| %s was / released outside. / Bye %s! | _MonWasReleasedText |
| %s was / stored in Box %s. | _MonWasStoredText |
| %s's / %s fell! | _MonsStatsRoseText + _FellText |
| %s's / %s rose! | _MonsStatsRoseText + _RoseText |
| %s's / %s rose. | _VitaminStatRoseText |
| %s's / dream was eaten! | _DreamWasEatenText |
| %s's / hurt by poison! | _HurtByPoisonText |
| %s's / hurt by the burn! | _HurtByBurnText |
| A blinding FLASH / lights the area! | _FlashLightsAreaText |
| Accessed PROF. / OAK's PC. / Accessed POKéDEX / Rating System. | _AccessedOaksPCText |
| An elevator! | _ElevatorText |
| BILL's favorite / POKéMON list! | _BillsHousePokemonListText1 |
| Bingo! | _CardKeySuccessText1 |
| Bring out which / POKéMON? | _PartyMenuBattleText |
| Choose a / <PK><MN> BOX. | _ChooseABoxText |
| Choose a POKéMON. | _PartyMenuNormalText |
| Closed link to / PROF.OAK's PC. | _ClosedOaksPCText |
| Crammed full of / POKéMON books! | _PokemonBooksText |
| Darn! / Ran out of coins! | _OutOfCoinsSlotMachineText |
| Darn! The POKéMON / broke free! | _ItemUseBallText02 |
| Do it! %s! | _DoItText |
| Do you want to / give a nickname / to %s? | _DoYouWantToNicknameText |
| First, what is / your name? | _IntroducePlayerText |
| GHOST: Get out... / Get out... | _GetOutText |
| Get'm! %s! | _GetmText |
| Go! %s! | _GoText |
| Gyaoo! | _VictoryRoad2FMoltresBattleText |
| Hello there! / Welcome to the / world of POKéMON! / My name is OAK! / People call me / the POKéMON PROF! | _OakSpeechText1 |
| Here you are! / Thank you! | _PokemartBoughtItemText |
| Hey! There's a / switch under the / trash! / The 1st electric / lock opened! | _VermilionGymTrashSuccessText1 |
| Hi there! / May I help you? | _PokemartGreetingText |
| How many? | _WithdrawHowManyText |
| I can't put a / price on that. | _PokemartUnsellableItemText |
| I like shorts! / They're comfy and / easy to wear! | _Route3Youngster2BattleText |
| Is it OK to toss / %s? | _IsItOKToTossItemText |
| Is there anything / else I can do? | _PokemartAnythingElseText |
| Move POKéMON / where? | _PartyMenuSwapMonText |
| No cycling / allowed here. | _NoCyclingAllowedHereText |
| No room left to / store items. | _NoRoomToStoreText |
| No! A new BADGE / is required. | _NewBadgeRequiredText |
| No! There's no / running from a / trainer battle! | _NoRunningText |
| Nope! ITEMFINDER / isn't responding. | _ItemfinderFoundNothingText |
| Nope! There's / only trash here. / Hey! The electric / locks were reset! | _VermilionGymTrashFailText |
| Not enough / coins! | _NotEnoughCoinsSlotMachineText |
| Now saving... | Yellow: _SavingText |
| OAK: %s! / This isn't the / time to use that! | _ItemUseNotTimeText |
| OK. We'll need / your POKéMON. | _NeedYourPokemonText |
| Once released, / %s is / gone forever. OK? | _OnceReleasedText |
| Oops! This Box is / full of POKéMON. | _BoxFullText |
| PA: You're out of / SAFARI BALLs! | _OutOfSafariBallsText, page 2 |
| PA: You're out of / SAFARI BALLs! / Game over! | _OutOfSafariBallsText |
| POKéDEX   Seen:{NUM:wDexRatingNumMonsSeen, 1, 3} /          Owned:{NUM:wDexRatingNumMonsOwned, 1, 3} | _DexSeenOwnedText |
| POKéDEX Rating{COLON} | _DexRatingText |
| Right! So your / name is {PLAYER}! | _YourNameIsText |
| SILPH SCOPE / unveiled the / GHOST's identity! | _UnveiledGhostText |
| Shall we heal your / POKéMON? | _ShallWeHealYourPokemonText |
| Sucked health from / %s! | _SuckedHealthText |
| That's right! I / remember now! His / name is {RIVAL}! | _HisNameIsText |
| That's too impor- / tant to toss! | _TooImportantToTossText |
| The 2nd electric / lock opened! / The motorized door / opened! | _VermilionGymTrashSuccessText3 |
| The link was / broken. | _LinkCanceledText; Yellow: _ColosseumCanceledText |
| There's no more / room for POKéMON! / %s was / sent to POKéMON / BOX %s on PC! | _SentToBoxText |
| There's no will / to fight! | _NoWillText |
| This is my grand- / son. He's been / your rival since / you were a baby. / ...Erm, what is / his name again? | _IntroduceRivalText |
| This world is / inhabited by / creatures called / POKéMON! | _OakSpeechText2A |
| Threw away / %s. | _ThrewAwayItemText |
| Use TM on which / POKéMON? | _PartyMenuUseTMText |
| Use item on which / POKéMON? | _PartyMenuItemUseText |
| Use next POKéMON? | _UseNextMonText |
| Want to get your / POKéDEX rated? | _GetDexRatedText |
| Welcome to our / POKéMON CENTER! | _PokemonCenterWelcomeText, page 1 |
| What would you / like to sell? | _PokemonSellingGreetingText |
| What? | _WhatText |
| What? There are / no POKéMON here! | _NoMonText |
| When you change a / POKéMON BOX, data / will be saved. / Is that okay? | _WhenYouChangeBoxText |
| Will %s / change POKéMON? | _TrainerAboutToUseText, page 2 |
| Would you like to / SAVE the game? | _WouldYouLikeToSaveText |
| Yes! ITEMFINDER / indicates there's / an item nearby. | _ItemfinderFoundItemText |
| You can't carry / any more items! | _CantCarryMoreText |
| You can't carry / any more items. | _CantCarryMoreText |
| You can't deposit / the last POKéMON! | _CantDepositLastMonText |
| You can't get off / here. | _CannotGetOffHereText |
| You can't take / any more POKéMON. / Deposit POKéMON / first. | _CantTakeMonText |
| You don't have / anything to sell. | _PokemartItemBagEmptyText |
| You don't have / enough money. | _PokemartNotEnoughMoneyText |
| You don't have the / BOULDERBADGE yet! | _Route22GateGuardNoBoulderbadgeText, page 2 |
| You missed the / POKéMON! | _ItemUseBallText01 |
| Your POKéMON are / fighting fit! | _PokemonFightingFitText |
| {PLAYER} got / %s! | _GotMonText |
| {PLAYER} got on / {RAM:wNameBuffer}! | _SurfingGotOnText |
| {PLAYER} initiated / TELEPORTER's Cell / Separator! | _BillsHouseInitiatedText |
| {PLAYER}! / Your very own / POKéMON legend is / about to unfold! / A world of dreams / and adventures / with POKéMON / awaits! Let's go! | _OakSpeechText3 |
| {RAM:wNameBuffer} can / move boulders. | _CanMoveBouldersText |
| {RAM:wNameBuffer} can't / FLY here. | _CannotFlyHereText |
| {RAM:wNameBuffer} can't / use TELEPORT now. | _CannotUseTeleportNowText |
| {RAM:wNameBuffer} hacked / away with CUT! | _UsedCutText |
| {RAM:wNameBuffer} used / STRENGTH. | _UsedStrengthText |
| {RIVAL}: Yeah! Am / I great or what? | _Rival1WinText |

### The fork's own wording

Write the better German in the last column; a box row holds 18
characters, a menu row fewer.

#### co-op (START > CO-OP, notices)

| English | German | Better German |
|---|---|---|
| CO-OP | KOOP | |
| NO PARTNERS YET | NOCH KEINE PARTNER | |
| AWAY | WEG | |
| TOWN MAP | KARTE | |
| LEAVE SESSION | SITZUNG VERLASSEN | |
| LEAVE THE CO-OP / SESSION? | KOOP-SITZUNG / VERLASSEN? | |
| END THE SESSION / FOR EVERYONE? | SITZUNG FÜR ALLE / BEENDEN? | |
| %s joined the session. | %s ist der Sitzung beigetreten. | |
| %s left the session. | %s hat die Sitzung verlassen. | |
| Campaign saved. | Alles gespeichert. | |
| %s saved the campaign. | %s hat die Kampagne gespeichert. | |
| The campaign was not saved. | Die Kampagne wurde nicht gespeichert. | |
| A battle is in / progress! / It can't be saved / right now. | Ein Kampf läuft / noch! / Speichern geht / gerade nicht. | |
| NOT SAVED YET | NOCH NICHT GESP. | |
| SAVED JUST NOW | GERADE GESPEICHERT | |
| SAVED %d MIN AGO | VOR %d MIN GESP. | |
| SAVED %d H AGO | VOR %d H GESP. | |
| AUTOSAVE: ON | AUTO-SPEICHERN: AN | |
| %s shared %s. | %s teilt %s. | |
| %s went to the PC. | %s liegt jetzt im PC. | |
| %s handed over %s. | %s hat %s abgegeben. | |
| No room for %s! | Kein Platz: %s! | |
| Got %s. | %s erhalten. | |
| JOIN %s | %s HELFEN | |
| Joining %s... | Zu %s... | |
| The battle is full. | Der Kampf ist voll. | |
| %s was already beaten. | %s ist schon besiegt. | |
| The battle is over. | Der Kampf ist vorbei. | |
| Could not join the battle. | Beitritt zum Kampf ging nicht. | |
| %s caught / %s! | %s hat / %s gefangen! | |
| %s joined / the battle! | %s hilft / im Kampf! | |
| decides | wählt | |
| %s suggests | %s rät zu | |
| IN A BATTLE | IM KAMPF | |
| Lost the host: reconnecting... | Host weg: verbinde neu... | |
| Back in the session. | Wieder in der Sitzung. | |
| The host closed the session. | Der Host hat die Sitzung beendet. | |
| The host turned this game away. | Der Host hat dieses Spiel abgewiesen. | |
| The connection to the host was lost. | Die Verbindung zum Host ist weg. | |
| Leave the battle? / Your team stays. | Kampf verlassen? / Dein Team bleibt. | |
| %s is away. / TAKE OVER? | %s ist weg. / ÜBERNEHMEN? | |
| FOR %s | FÜR %s | |
| is away | ist weg | |
| REJOIN | ZURÜCK | |
| Your battle against | Dein Kampf gegen | |
| %s goes on... | %s läuft... | |
| Your battle against / %s goes on. / REJOIN? | Dein Kampf gegen / %s läuft noch. / ZURÜCK IN DEN KAMPF? | |
| The battle against %s was won. | Der Kampf gegen %s ist gewonnen. | |
| The battle against %s was lost. | Der Kampf gegen %s ist verloren. | |
| The battle against %s is over. | Der Kampf gegen %s ist vorbei. | |
| %s was caught. | %s gefangen. | |
| %s is in a battle against wild %s. START > CO-OP to join. | %s kämpft gegen ein wildes %s. START > KOOP zum Helfen. | |
| %s is in a battle against %s. START > CO-OP to join. | %s kämpft gegen %s. START > KOOP zum Helfen. | |
| %s joined the session in the opening. | %s ist der Sitzung beigetreten und spielt den Anfang. | |
| IN THE OPENING | IM SPIELANFANG | |
| The opening can't / be saved. / Leave OAK's LAB / first! | Der Anfang wird / nicht gesichert. / Verlasse erst / EICHs LABOR! | |
| BATTLE %s | KAMPF %s | |
| TRADE %s | TAUSCH %s | |
| for %s? | gegen %s? | |
| VS %s | GEGEN %s | |
| TRADING | TAUSCHT | |
| Invitation sent. | Anfrage gesendet. | |
| %s wants / to battle! | %s / möchte kämpfen! | |
| %s wants / to trade! | %s / möchte tauschen! | |
| %s declined. | %s sagt NEIN. | |
| %s did not answer. | %s hat nicht geantwortet. | |
| %s is busy. | %s hat zu tun. | |
| %s is away. | %s ist weg. | |
| %s left. | %s ist fort. | |
| Waiting for %s... | Warte auf %s... | |
| %s forfeited / the match! | %s gibt / den Kampf auf! | |
| %s left the battle. | %s hat den Kampf verlassen. | |

#### battle

| English | German | Better German |
|---|---|---|
| FOE | GEGNER | |
| But every BOX / is full! | Aber jede BOX / ist voll! | |
| %s used / SAFARI BALL! | %s setzt / SAFARIBALL ein! | |
| %s / is charging up! | %s / lädt sich auf! | |
| %s is / protected by MIST! | %s wird / durch WEISSNEBEL / geschützt! | |
| %s / was afflicted / by %s! | %s / leidet an / %s! | |
| HEALTH | KP | |
| PP | AP | |
| %s gained / a boosted / %d EXP. Points! | %s erhält / einen Bonus: / %d EP! | |
| %s's / %s / greatly rose! | %ss / %s / steigt stark! | |
| %s's / %s / greatly fell! | %ss / %s / sinkt stark! | |
| What will | Was soll | |
|  do? |  tun? | |
| %s is out of / POKéMON! / %s wins! | %s hat keine / POKéMON mehr! / %s gewinnt! | |
| %s left the / battle. | %s hat den / Kampf verlassen. | |
| %s ran from / the battle! | %s ist aus dem / Kampf geflohen! | |
| %s ran out of / time! | %s hat keine / Zeit mehr! | |
| %s vs %s! | %s gegen %s! | |
| %s's %s can't / battle on this / game. | %s: %s kann / in diesem Spiel / nicht kämpfen. | |
| %s's %s can't / battle on this / game. / (%s) | %s: %s kann / in diesem Spiel / nicht kämpfen. / (%s) | |
| Items can't be / used in a link / battle! | Im Link-Kampf / sind keine Items / erlaubt! | |
| Link battle needs / the same version / and mods. | Link-Kampf nur / mit gleicher / Version und Mods. | |
| Link desync! / %s differs. / Are both games / the same version / and mods? | Link gestört! / %s weicht ab. / Haben beide Spiele / dieselbe Version / und Mods? | |
| Their %s isn't / in this game. / (%s) | Das %s gibt es / in diesem Spiel / nicht. (%s) | |
| Time's up! You / forfeit the match. | Zeit um! Du gibst / den Kampf auf. | |
| Your %s can't / battle on the / other game. | Dein %s kann / im anderen Spiel / nicht kämpfen. | |

#### field

| English | German | Better German |
|---|---|---|
| %s received / %s! | %s erhält / %s! | |
| %s received / the %s! | %s erhält / %s! | |
| Go right ahead! | Geh ruhig weiter! | |
| Oh! That is the / {RAM}! | Oh! Das ist der / {RAM}! | |
| You don't have the / {RAM} yet! | Du hast den / {RAM} noch nicht! | |
| Keep it up! | Weiter so! | |
| PIKACHU looks / content. | PIKACHU sieht / zufrieden aus. | |
| POKéMON LEAGUE HQ | POKéMON-LIGA-SITZ | |
| There's a slew of / POKéMON stuff! | Hier ist jede / Menge POKéMON- / Kram! | |
| You need a / BICYCLE for the / Cycling Road! | Für die Radstraße / brauchst Du ein / FAHRRAD! | |
| POKéDEX comp- / letion is: / {NUM:hDexRatingNumMonsSeen} POKéMON seen / {NUM:hDexRatingNumMonsOwned} POKéMON owned / PROF.OAK's / Rating: | Stand des / POKéDEX: / {NUM:hDexRatingNumMonsSeen} POKéMON / gesehen, / {NUM:hDexRatingNumMonsOwned} POKéMON / gefangen. / PROF.EICHS / Urteil: | |
| {RAM} / POKéMON GYM / LEADER: {RAM} | {RAM} / POKéMON-ARENA / LEITER: {RAM} | |
| To %s | Nach %s | |
| FLY TO? | WOHIN? | |
| ABLE | OK | |
| NOT ABLE | NEIN | |
| FNT | BSG | |
| No POKéMON! | Kein POKéMON! | |
| No SURFing here! | Hier kein SURFEN! | |
| Nothing to CUT! | Nichts zu / ZERSCHNEIDEN! | |
| No good! It's not / even near water. | Geht nicht! Kein / Wasser in der / Nähe. | |
| The TOWN MAP is / unreadable here. | Die KARTE ist / hier nicht / lesbar. | |
| There isn't any / response... | Keine / Reaktion... | |
| Empty. | Leer. | |
| Nothing here. | Nichts da. | |
| %s looks / unhappy about it! | %s sieht / unglücklich aus! | |
| The party is full! | Das Team ist voll! | |
| You need at least / one POKéMON! | Du brauchst / mindestens ein / POKéMON! | |
| BOX %d is full! | BOX %d voll! | |
| PRINT BOX | BOX DRUCKEN | |
| Printed BOX %d! /  | BOX %d / gedruckt! /  | |
| Printed %s's / data! /  | Daten von %s / gedruckt! /  | |
| Printer error! / %s | Druckerfehler! / %s | |
| PRNT | DRCK | |
| Toss %s? | %s / wegwerfen? | |
| NO THANKS | NEIN DANKE | |
| SLOT MACHINE | SPIELAUTOMAT | |
| COINS %4d | MÜNZEN %4d | |
| RETURN TO MAIN / MENU? | ZURÜCK ZUM / HAUPTMENÜ? | |
| QUIT | BEENDEN | |
| EXIT GAME | SPIEL BEENDEN | |
| Diploma | Diplom | |
| Player | Spieler | |
| IDNo.%05d | IDNr.%05d | |
| No.%03d | Nr.%03d | |
| No. | Nr. | |
| :L%d No.%03d | :L%d Nr.%03d | |
| Trade completed! / %s received / %s! | Tausch vollzogen! / %s erhält / %s! | |
| The trade stopped: / %s. | Der Tausch wurde / abgebrochen: / %s. | |

#### the engine's own options (START > OPTION)

| English | German | Better German |
|---|---|---|
| %d OPTIONS | %d OPTIONEN | |
| options\|SPEED | TEMPO | |
| GRAPHICS | GRAFIK | |
| %d INSTALLED | %d INSTALLIERT | |
| AUDIO MODE | AUDIO-MODUS | |
| AUTO (FILL HUD) | AUTO (HUD FÜLLEN) | |
| BATTLE BG | KAMPF-HINTERGRUND | |
| BATTLE HUD | KAMPF-HUD | |
| BATTLE LAYOUT | KAMPF-LAYOUT | |
| BATTLE SIZE | KAMPF-GRÖSSE | |
| BATTLE SPEED | KAMPF-TEMPO | |
| BLACK | SCHWARZ | |
| BOTH | BEIDE | |
| CENTERED | ZENTRIERT | |
| COLORS | FARBEN | |
| CONTROLS | STEUERUNG | |
| DATE FORMAT | DATUMSFORMAT | |
| DISPLAY | ANZEIGE | |
| DISPLAY (%dHZ) | ANZEIGE (%dHZ) | |
| DYNAMIC | DYNAMISCH | |
| EXTENDED | ERWEITERT | |
| FAITHFUL RATIO | ORIGINALFORMAT | |
| FILL | FÜLLEN | |
| FIT | EINPASSEN | |
| FIXED | FEST | |
| KEY BAR | TASTENLEISTE | |
| LOGIC CLOCK | LOGIKTAKT | |
| MAX FPS | MAX. FPS | |
| MENU SPEED | MENÜ-TEMPO | |
| MUSIC FILTER | MUSIKFILTER | |
| MUSIC VOL | MUSIK-LAUTST. | |
| OG | ORIGINAL | |
| ORIENTATION | AUSRICHTUNG | |
| OVERWORLD SPEED | WELT-TEMPO | |
| PERFORMANCE | LEISTUNG | |
| PIKACHU VOL | PIKACHU-LAUTST. | |
| RULESET | REGELWERK | |
| SCREEN POS | BILDPOSITION | |
| SFX VOL | EFFEKT-LAUTST. | |
| SHADER FX | SHADER-EFFEKTE | |
| SHADER FX 2 | SHADER-EFFEKTE 2 | |
| TILT | NEIGUNG | |
| TIME FORMAT | ZEITFORMAT | |
| TOUCH PAD | TOUCH-PAD | |
| UI LAYOUT | UI-LAYOUT | |
| UI LETTERBOX | UI-LETTERBOX | |
| UNAVAILABLE | NICHT VERFÜGBAR | |
| VIDEO MODE | VIDEO-MODUS | |
| VOID FILL | RANDFÜLLUNG | |
| WHITE | WEISS | |
| WIDE | BREIT | |
| WORLD | WELT | |

#### link play (upstream's Cable Club over the network)

| English | German | Better German |
|---|---|---|
| HOST A GAME | SPIEL ERÖFFNEN | |
| JOIN A GAME | SPIEL BEITRETEN | |
| BATTLE | KAMPF | |
| Calling... | Rufe an... | |
| Waiting for join... | Warte auf Gast... | |
| Waiting for the | Warte auf das | |
| other game... | andere Spiel... | |
| host to choose... | Wahl des Hosts... | |
| Checking the | Prüfe das | |
| Exchanging data... | Datenaustausch... | |
| Friend joins at: | Freund wählt: | |
| Port: %s | Port: %s | |
| UDP port %s | UDP-Port %s | |
| LEVELS: | LEVEL: | |
| A: connect  B: back | A: start  B: zurück | |
| A: continue  B: back | A: weiter  B: zurück | |
| A: trade anyway | A: trotzdem | |
| Not an IP address. | Keine IP-Adresse. | |
| Link battle / can't start. | Link-Kampf kann / nicht starten. | |
| Link error: / %s | Link-Fehler: / %s | |
| The other side / sent bad data. | Die Gegenseite / sendet Unsinn. | |
| The relay stopped / answering. | Das Relay / antwortet nicht. | |
| can't reach relay %s:%d / (%s) | Relay %s:%d nicht / erreichbar (%s) | |
| no answer from / %s | Keine Antwort von / %s | |
| Something broke / during the link. | Beim Link ist / etwas kaputt- / gegangen. | |
| Names are 3 to 16 characters. | Namen haben 3 bis 16 Zeichen. | |
| Sign-in didn't work: %s | Anmeldung fehlgeschlagen: %s | |
| The server kept your old name. | Der Server behält Deinen alten Namen. | |
| This build is too old for online play. Please update. | Dieser Build ist zu alt für Online-Spiel. Bitte aktualisieren. | |

### Kept in English

Names, codes and values that are no words: `GAME FREAK inc.`, `GAME FREAK`, `Creatures inc.`, `Nintendo`, `GENGAR VS NIDORINO`, `T H E  E N D`, `POKéMON RED`, `POKéMON BLUE`, `POKéMON YELLOW`, `ITEMS`, `MODS`, `BALL`, `NAME`, `NORMAL`, `STANDARD`, `VSYNC`, `ZOOM`, `VIBRATION`, `OG`, `%dX`, `IN%d`, `OUT%d`, `Level %d`, `POKéDEX`, `POKéMON`, `ITEM`, `OPTION`, `OT/`, `STATUS/`, `TYPE1/`, `TYPE2/`, `LEVEL/`, `HT`, `WT`, `lb`, `GR. %.1fm`, `GR. ???m`, `GEW. %.1fkg`, `GEW. ???kg`, `BOX%2d`, `:L%d`, `Printer error! / %s`, ` [%s %s.%s]`, `contribution is not a table`, `AUDIO`, `VIDEO`.
<!-- end of the games part -->
