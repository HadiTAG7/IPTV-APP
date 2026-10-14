/// Large-guide benchmark, skipped unless `RUN_BENCH` is set:
/// `RUN_BENCH=1 flutter test --tags bench test/unit/epg`. The tag also lets
/// `--exclude-tags bench` leave the file out entirely.
@Tags(['bench'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/xmltv_parser.dart';

const _targetBytes = 200 * 1024 * 1024;
const _channels = 5000;
const _slot = Duration(minutes: 30);
final _base = DateTime.utc(2026, 10, 14);

String _two(int v) => v.toString().padLeft(2, '0');

String _ts(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}'
    '${_two(t.hour)}${_two(t.minute)}00 +0300';

/// Writes a synthetic guide of about [_targetBytes] to [file] in 1 MB slices,
/// returning the number of programmes.
Future<int> _generate(File file) async {
  final out = await file.open(mode: FileMode.write);
  final buf = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<tv generator-info-name="synthetic-bench">\n',
  );
  for (var c = 0; c < _channels; c++) {
    buf.write(
      '  <channel id="ch$c.example">'
      '<display-name lang="ar">قناة تجريبية $c</display-name>'
      '<display-name lang="en">Bench Channel $c HD</display-name>'
      '<icon src="http://127.0.0.1/logos/$c.png"/></channel>\n',
    );
  }
  var written = 0;
  var i = 0;
  while (written < _targetBytes) {
    final c = i % _channels;
    final start = _base.add(_slot * (i ~/ _channels));
    // Every 10th programme omits stop to exercise the held-back path.
    final stop = i % 10 == 0 ? '' : ' stop="${_ts(start.add(_slot))}"';
    buf.write(
      '  <programme start="${_ts(start)}"$stop channel="ch$c.example">\n'
      '    <title lang="en">Bench Show $i &amp; Friends</title>\n'
      '    <title lang="ar">برنامج تجريبي $i</title>\n'
      '    <sub-title lang="en">Episode ${i % 30}</sub-title>\n'
      '    <desc lang="ar"><![CDATA[وصف تجريبي للحلقة $i مع نص أطول قليلاً <مباشر>]]></desc>\n'
      '    <desc lang="en">Synthetic description $i for the streaming benchmark, padded with a little more text.</desc>\n'
      '    <credits><director>Director $c</director><actor>Actor $i</actor></credits>\n'
      '    <category lang="en">Bench</category>\n'
      '    <icon src="http://127.0.0.1/img/$i.jpg"/>\n'
      '    <rating system="bench"><value>PG</value></rating>\n'
      '  </programme>\n',
    );
    i++;
    if (buf.length >= 1 << 20) {
      final chunk = buf.toString();
      buf.clear();
      written += chunk.length;
      await out.writeString(chunk);
    }
  }
  buf.write('</tv>\n');
  await out.writeString(buf.toString());
  await out.close();
  return i;
}

/// Skips the group, and so its 200 MB setUpAll, in default runs.
final Object _skip = Platform.environment['RUN_BENCH'] == null
    ? 'set RUN_BENCH=1 to run (writes a ~200 MB temp file)'
    : false;

void main() {
  group('XMLTV bench', _bench, skip: _skip);
}

void _bench() {
  late Directory dir;
  late File plain;
  late int total;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('xmltv_bench');
    plain = File('${dir.path}/guide.xml');
    total = await _generate(plain);
  });

  tearDownAll(() async {
    await dir.delete(recursive: true);
  });

  Future<void> run(File file) async {
    final rssBefore = ProcessInfo.currentRss;
    var peakRss = rssBefore;
    var channels = 0;
    var programmes = 0;
    var batches = 0;
    var maxBatch = 0;
    final sw = Stopwatch()..start();
    await for (final b in const XmltvParser().parse(
      file.openRead(),
      windowStart: _base.add(const Duration(hours: 6)),
      windowEnd: _base.add(const Duration(hours: 12)),
    )) {
      channels += b.channels.length;
      programmes += b.programmes.length;
      batches++;
      final size = b.channels.length + b.programmes.length;
      if (size > maxBatch) maxBatch = size;
      final rss = ProcessInfo.currentRss;
      if (rss > peakRss) peakRss = rss;
    }
    sw.stop();
    final mb = file.lengthSync() / (1 << 20);
    stdout.writeln(
      '${file.path.split('/').last}: ${mb.toStringAsFixed(1)} MB, '
      '$total programmes in file, $programmes kept, $batches batches, '
      '${sw.elapsedMilliseconds} ms, '
      'RSS +${(peakRss - rssBefore) >> 20} MB',
    );

    expect(channels, _channels);
    // Six hours of 30-minute slots per channel overlap the window.
    expect(programmes, _channels * 12);
    expect(maxBatch, lessThanOrEqualTo(5000));
    expect(sw.elapsed, lessThan(const Duration(seconds: 120)));
    // Streaming: memory does not grow with the 200 MB input.
    expect(peakRss - rssBefore, lessThan(256 << 20));
  }

  test('parses a ~200 MB plain guide', () async {
    expect(plain.lengthSync(), greaterThan(_targetBytes));
    await run(plain);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('parses the same guide gzipped', () async {
    final gz = File('${dir.path}/guide.xml.gz');
    await plain.openRead().transform(gzip.encoder).pipe(gz.openWrite());
    await run(gz);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
