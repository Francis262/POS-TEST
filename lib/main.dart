import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PosSkenerApp());
}

class PosSkenerApp extends StatelessWidget {
  const PosSkenerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS Zaključek Izmene',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const PosDomovZaslon(),
    );
  }
}

class PosSlip {
  final String id;
  final double znesek;
  final String cas;
  final String nacin;

  PosSlip({
    required this.id,
    required this.znesek,
    required this.cas,
    required this.nacin,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'znesek': znesek,
        'cas': cas,
        'nacin': nacin,
      };

  factory PosSlip.fromJson(Map<String, dynamic> json) => PosSlip(
        id: json['id'],
        znesek: (json['znesek'] as num).toDouble(),
        cas: json['cas'],
        nacin: json['nacin'] ?? 'Kamera',
      );
}

class PosDomovZaslon extends StatefulWidget {
  const PosDomovZaslon({super.key});

  @override
  State<PosDomovZaslon> createState() => _PosDomovZaslonState();
}

class _PosDomovZaslonState extends State<PosDomovZaslon> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  List<PosSlip> _slipi = [];
  double _pricakovanZnesekBlagajne = 0.0;
  bool _procesiram = false;

  @override
  void initState() {
    super.initState();
    _naloziPodatke();
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // Nalaganje shranjenih slipov iz lokalnega pomnilnika telefona
  Future<void> _naloziPodatke() async {
    final prefs = await SharedPreferences.getInstance();
    final shranjeniSlipi = prefs.getString('pos_slipi_seznam');
    final shranjenCilj = prefs.getDouble('pos_pricakovan_znesek') ?? 0.0;

    if (shranjeniSlipi != null) {
      final List<dynamic> decoded = jsonDecode(shranjeniSlipi);
      setState(() {
        _slipi = decoded.map((item) => PosSlip.fromJson(item)).toList();
        _pricakovanZnesekBlagajne = shranjenCilj;
      });
    }
  }

  // Shranjevanje v telefon
  Future<void> _shraniPodatke() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_slipi.map((s) => s.toJson()).toList());
    await prefs.setString('pos_slipi_seznam', encoded);
    await prefs.setDouble('pos_pricakovan_znesek', _pricakovanZnesekBlagajne);
  }

  double get _skupniZnesek =>
      _slipi.fold(0.0, (vsota, item) => vsota + item.znesek);

  String _formatirajEvre(double vrednost) {
    return '${vrednost.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  // Slikanje s kamero in Google ML Kit OCR prepoznava
  Future<void> _slikajInPreberiSlip() async {
    try {
      final XFile? slika = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );

      if (slika == null) return;

      setState(() => _procesiram = true);

      final inputImage = InputImage.fromFilePath(slika.path);
      final RecognizedText prepoznanTekst =
          await _textRecognizer.processImage(inputImage);

      setState(() => _procesiram = false);

      final double? najdenZnesek = _izlusciZnesekIzPosTeksta(prepoznanTekst.text);

      HapticFeedback.mediumImpact();
      _odpriPotrditvenoOkno(
        predlaganZnesek: najdenZnesek,
        surovTekst: prepoznanTekst.text,
        nacin: 'Skenirano',
      );
    } catch (e) {
      setState(() => _procesiram = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Napaka pri branju kamere: $e')),
        );
      }
    }
  }

  // Pametni algoritem za slovenske POS izpiske
  double? _izlusciZnesekIzPosTeksta(String tekst) {
    final vrstice = tekst
        .split('\n')
        .map((v) => v.trim().toUpperCase())
        .where((v) => v.isNotEmpty)
        .toList();

    final kljucneBesede = [
      'ZNESEK',
      'SKUPAJ',
      'PLAČILO',
      'PLACILO',
      'ZA PLAČILO',
      'TOTAL',
      'AMOUNT',
      'EUR'
    ];

    // Regex za zneske (npr. 14,50 ali 14.50 ali 1.240,50)
    final znesekRegex = RegExp(r'(\d{1,4}[,\.]\d{2})\b');

    // 1. KORAK: Najprej iščemo v vrsticah s ključnimi besedami (npr. "ZNESEK EUR 24,50")
    for (int i = 0; i < vrstice.length; i++) {
      final vrstica = vrstice[i];
      if (kljucneBesede.any((k) => vrstica.contains(k))) {
        final zadetki = znesekRegex.allMatches(vrstica);
        if (zadetki.isNotEmpty) {
          final zadnji = zadetki.last.group(1)!.replaceAll(',', '.');
          final st = double.tryParse(zadnji);
          if (st != null && st > 0 && st < 5000) return st;
        }
        // Včasih je številka v naslednji vrstici takoj pod "ZNESEK:"
        if (i + 1 < vrstice.length) {
          final zadetkiNaslednja = znesekRegex.allMatches(vrstice[i + 1]);
          if (zadetkiNaslednja.isNotEmpty) {
            final zadnji = zadetkiNaslednja.last.group(1)!.replaceAll(',', '.');
            final st = double.tryParse(zadnji);
            if (st != null && st > 0 && st < 5000) return st;
          }
        }
      }
    }

    // 2. KORAK: Če je beseda ZNESEK zbledela, poiščemo vse dvodecimalne številke
    List<double> vsiZneski = [];
    for (final match in znesekRegex.allMatches(tekst)) {
      final st = double.tryParse(match.group(1)!.replaceAll(',', '.'));
      if (st != null && st >= 0.50 && st < 3000) {
        // Izločimo letnico (npr. 20.26)
        if (st != 20.25 && st != 20.26 && st != 20.27) {
          vsiZneski.add(st);
        }
      }
    }

    if (vsiZneski.isNotEmpty) {
      vsiZneski.sort();
      return vsiZneski.last; // Na POS slipu je znesek plačila največja decimalna številka
    }

    return null;
  }

  // Okno za hitro potrditev ali popravek prebranega zneska
  void _odpriPotrditvenoOkno({
    double? predlaganZnesek,
    String? surovTekst,
    required String nacin,
  }) {
    final TextEditingController controller = TextEditingController(
      text: predlaganZnesek != null ? predlaganZnesek.toStringAsFixed(2) : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    predlaganZnesek != null
                        ? '✓ Prepoznan znesek'
                        : 'Vnesi znesek slipa',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: predlaganZnesek != null
                          ? const Color(0xFF10B981)
                          : Colors.amber,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
              if (predlaganZnesek == null && surovTekst != null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Zneska ni bilo mogoče 100% prebrati. Vpiši ga spodaj ali slikaj bližje.',
                    style: TextStyle(color: Colors.amber, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  suffixText: '€',
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        final vnos =
                            controller.text.replaceAll(',', '.').trim();
                        final znesek = double.tryParse(vnos);
                        if (znesek != null && znesek > 0) {
                          _dodajSlipVSeznam(znesek, nacin);
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 24),
                      label: const Text(
                        'POTRDI IN PRIŠTEJ',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _dodajSlipVSeznam(double znesek, String nacin) {
    final cas = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() {
      _slipi.add(PosSlip(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        znesek: double.parse(znesek.toStringAsFixed(2)),
        cas: cas,
        nacin: nacin,
      ));
    });
    HapticFeedback.lightImpact();
    _shraniPodatke();
  }

  void _nastaviPricakovanZnesek() {
    final controller = TextEditingController(
      text: _pricakovanZnesekBlagajne > 0
          ? _pricakovanZnesekBlagajne.toStringAsFixed(2)
          : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Znesek kartic iz blagajne (X/Z)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'npr. 450.80',
            suffixText: '€',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Prekliči'),
          ),
          ElevatedButton(
            onPressed: () {
              final st = double.tryParse(
                      controller.text.replaceAll(',', '.').trim()) ??
                  0.0;
              setState(() => _pricakovanZnesekBlagajne = st);
              _shraniPodatke();
              Navigator.pop(context);
            },
            child: const Text('Shrani'),
          ),
        ],
      ),
    );
  }

  void _pocistiIzmeno() {
    if (_slipi.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Nova izmena?'),
        content: const Text(
            'Ali res želiš izbrisati vse skenirane slipe in začeti znova?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Prekliči'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              setState(() {
                _slipi.clear();
                _pricakovanZnesekBlagajne = 0.0;
              });
              _shraniPodatke();
              Navigator.pop(context);
            },
            child: const Text('Izbriši vse'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final razlika = _skupniZnesek - _pricakovanZnesekBlagajne;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'POS Zaključek Izmene',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        ),
        actions: [
          IconButton(
            tooltip: 'Primerjaj z blagajno',
            onPressed: _nastaviPricakovanZnesek,
            icon: const Icon(Icons.calculate_outlined, color: Colors.amber),
          ),
          IconButton(
            tooltip: 'Počisti izmeno',
            onPressed: _pocistiIzmeno,
            icon: const Icon(Icons.delete_sweep_outlined,
                color: Colors.redAccent),
          ),
        ],
      ),
      body: Column(
        children: [
          // Zgornja nadzorna plošča s skupnim seštevkom
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SKUPAJ POS SLIPOV',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatirajEvre(_skupniZnesek),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'ŠT. SLIPOV',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                          Text(
                            '${_slipi.length}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Prikaz ujemanja z X/Z zaključkom blagajne (če je vnesen)
                if (_pricakovanZnesekBlagajne > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: razlika.abs() < 0.01
                          ? Colors.green.withOpacity(0.15)
                          : Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: razlika.abs() < 0.01
                            ? Colors.greenAccent
                            : Colors.amber,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Blagajna (X/Z): ${_formatirajEvre(_pricakovanZnesekBlagajne)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          razlika.abs() < 0.01
                              ? '✓ TOČNO UJEMANJE'
                              : (razlika < 0
                                  ? 'Manjka: ${_formatirajEvre(razlika.abs())}'
                                  : 'Presežek: +${_formatirajEvre(razlika)}'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: razlika.abs() < 0.01
                                ? Colors.greenAccent
                                : Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (_procesiram)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Berem POS izpisek...'),
                ],
              ),
            ),

          // Seznam skeniranih slipov
          Expanded(
            child: _slipi.isEmpty
                ? const Center(
                    child: Text(
                      'Ni še skeniranih POS izpiskov.\nPritisni zeleni gumb spodaj za skeniranje.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _slipi.length,
                    itemBuilder: (context, index) {
                      // Prikaz od najnovejšega navzdol
                      final praviIndex = _slipi.length - 1 - index;
                      final slip = _slipi[praviIndex];

                      return Card(
                        color: const Color(0xFF1E293B),
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: const Color(0xFF10B981),
                            child: Text(
                              '#${praviIndex + 1}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          title: Text(
                            _formatirajEvre(slip.znesek),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'Čas: ${slip.cas} • ${slip.nacin}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white54),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                            onPressed: () {
                              setState(() => _slipi.removeAt(praviIndex));
                              _shraniPodatke();
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Spodnja akcijska vrstica (Kamera + Ročni vnos)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _slikajInPreberiSlip,
                      icon: const Icon(Icons.camera_alt_rounded, size: 28),
                      label: const Text(
                        'SLIKAJ POS SLIP',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () =>
                          _odpriPotrditvenoOkno(nacin: 'Ročni vnos'),
                      child: const Icon(Icons.dialpad, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

