import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NfcDemoApp());
}

class NfcDemoApp extends StatelessWidget {
  const NfcDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC Reader Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const NfcDemoPage(),
    );
  }
}

class NfcDemoPage extends StatefulWidget {
  const NfcDemoPage({super.key});

  @override
  State<NfcDemoPage> createState() => _NfcDemoPageState();
}

class _NfcDemoPageState extends State<NfcDemoPage> {
  bool _isReading = false;
  String _status = 'NFCタグをかざしてください';
  String _payload = 'まだ読み取っていません';

  Future<void> _startRead() async {
    setState(() {
      _isReading = true;
      _status = '読み取り中...';
      _payload = 'タグをかざしてください';
    });

    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.enabled) {
        throw StateError('この端末はNFCに対応していないか、NFCが無効です');
      }

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        alertMessageIos: 'NFCタグをかざしてください',
        onDiscovered: (tag) async {
          final ndef = Ndef.from(tag);

          if (ndef == null) {
            if (!mounted) return;
            setState(() {
              _status = 'NDEF非対応のタグです';
              _payload = 'このタグにはNDEFデータがありません';
              _isReading = false;
            });
            await NfcManager.instance.stopSession();
            return;
          }

          final message = ndef.cachedMessage;
          if (message == null || message.records.isEmpty) {
            if (!mounted) return;
            setState(() {
              _status = 'タグを確認しました';
              _payload = 'NDEFレコードが見つかりませんでした';
              _isReading = false;
            });
            await NfcManager.instance.stopSession();
            return;
          }

          final payloads = message.records
              .map(_decodeNdefRecord)
              .where((value) => value.isNotEmpty)
              .toList();

          final combinedPayload = payloads.isEmpty
              ? 'NDEFレコードが見つかりませんでした'
              : payloads.join('\n');

          if (!mounted) return;

          setState(() {
            _status = '読み取り完了';
            _payload = combinedPayload;
            _isReading = false;
          });

          await NfcManager.instance.stopSession();
        },
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = 'エラー: $error';
        _payload = '読み取りに失敗しました';
        _isReading = false;
      });
    }
  }

  String _decodeNdefRecord(NdefRecord record) {
    if (record.payload.isEmpty) {
      return '';
    }

    final payload = record.payload;

    if (record.typeNameFormat == TypeNameFormat.wellKnown &&
        record.type.isNotEmpty &&
        record.type.first == 0x54) {
      final languageCodeLength = payload.first & 0x1F;
      if (payload.length > languageCodeLength + 1) {
        return utf8.decode(payload.sublist(1 + languageCodeLength), allowMalformed: true);
      }
    }

    return utf8.decode(payload, allowMalformed: true);
  }

  @override
  void dispose() {
    unawaited(NfcManager.instance.stopSession());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFCタグ読み取り'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '状態',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '値',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _payload,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _isReading ? null : _startRead,
              icon: const Icon(Icons.nfc_rounded),
              label: Text(_isReading ? '読み取り中...' : 'NFCを読み取る'),
            ),
          ],
        ),
      ),
    );
  }
}
