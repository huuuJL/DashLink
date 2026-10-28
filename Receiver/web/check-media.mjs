import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const root = process.env.MEDIA_SOURCE_DIR
  ? pathToFileURL(`${process.env.MEDIA_SOURCE_DIR}/`)
  : new URL('./src/', import.meta.url);
function moduleUrl(name, protocolUrl) {
  let source = readFileSync(new URL(name, root), 'utf8');
  if (protocolUrl) source = source.replaceAll("'./protocol'", JSON.stringify(protocolUrl));
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
  });
  return `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`;
}
const protocol = moduleUrl('protocol.ts');
const { AudioEngine } = await import(moduleUrl('audio.ts', protocol));
const { VideoPlayer } = await import(moduleUrl('video.ts', protocol));

const contexts = [];
class FakeContext {
  currentTime = 0;
  state = 'suspended';
  destination = {};
  sources = [];
  constructor() { contexts.push(this); }
  async resume() { this.state = 'running'; }
  createGain() { return { gain: { value: 1 }, connect() {}, disconnect() {} }; }
  createBuffer(channels, frames, rate) {
    return { duration: frames / rate, copyToChannel() {}, channels };
  }
  createBufferSource() {
    const source = {
      onended: null, stopped: false, disconnected: false, startTime: null,
      connect() {}, disconnect() { this.disconnected = true; },
      start(time) { this.startTime = time; }, stop() { this.stopped = true; },
    };
    this.sources.push(source);
    return source;
  }
}
globalThis.AudioContext = FakeContext;
const errors = [];
const engine = new AudioEngine((error) => errors.push(error));
assert.equal(engine.isUnlocked, false, 'Suspended audio must not be reported as enabled');
await engine.unlock();
const context = contexts.at(-1);
const config = {
  kind: 'audio-config', streamType: 100, codec: 3, sampleRate: 48000,
  channels: 2, name: 'telephony', description: new Uint8Array(),
};
engine.handleConfig(config);
const packet = { kind: 'audio-packet', streamType: 100, timestampUs: 0, data: new Uint8Array(3840) };
context.state = 'suspended';
engine.handlePacket(packet);
assert.equal(context.sources.length, 0, 'Suspended output must not accumulate queued music');
context.state = 'running';
assert.equal(engine.isUnlocked, true, 'An already-running native output needs no extra gesture flag');
engine.handlePacket(packet); // 20 ms of stereo PCM, with a startup buffer.
assert.equal(context.sources[0].startTime, 0.12, 'Voice routes must retain a short startup buffer');
for (let index = 1; index < 100; index++) {
  context.currentTime = index * 0.020 + (index % 2 ? 0.010 : -0.005);
  engine.handlePacket(packet);
  const previous = context.sources[index - 1];
  const current = context.sources[index];
  assert.ok(Math.abs(current.startTime - (previous.startTime + 0.020)) < 1e-9,
    'Ordinary packet jitter must not insert silence between scheduled buffers');
}
context.currentTime = 3; // Actual underrun: rebuild the startup buffer once.
engine.handlePacket(packet);
assert.ok(context.sources.at(-1).startTime > 3);
engine.stopStream(100);
assert.ok(context.sources.every((source) => source.stopped && source.disconnected),
  'Stopping a stream must cancel queued playback');

engine.handleConfig(config);
const burstStart = context.sources.length;
for (let index = 0; index < 30; index++) engine.handlePacket(packet);
const burst = context.sources.slice(burstStart);
assert.ok(burst.length < 30, 'Excessive decode bursts must not grow the playback queue indefinitely');
assert.ok(burst.every((source) => !source.stopped), 'Bursts must preserve sound already queued for the speakers');
const live = burst.filter((source) => !source.stopped);
assert.ok(live.length > 0);
assert.ok(live.every((source) => source.startTime <= context.currentTime + 0.35 + 1e-9));
const firstQueued = live[0];
for (let batch = 1; batch < 6; batch++) {
  context.currentTime += 0.08;
  for (let index = 0; index < 20; index++) engine.handlePacket(packet);
}
assert.equal(firstQueued.stopped, false, 'Repeated bursts must not postpone/cancel playback before its start time');
engine.stopAll();
assert.deepEqual(errors, []);

const audioDecoders = [];
globalThis.EncodedAudioChunk = class { constructor(options) { Object.assign(this, options); } };
function decodedAudio() {
  return { numberOfChannels: 2, numberOfFrames: 1024, sampleRate: 48000,
    copyTo() {}, closed: false, close() { this.closed = true; } };
}
globalThis.AudioDecoder = class {
  constructor(callbacks) { this.callbacks = callbacks; audioDecoders.push(this); }
  configure(config) { this.config = config; }
  decode() { this.callbacks.output(decodedAudio()); }
  close() {}
};
engine.handleConfig({ ...config, codec: 1, streamType: 102 });
const aacStart = context.sources.length;
engine.handlePacket({ ...packet, streamType: 102 });
assert.equal(context.sources.length, aacStart + 1, 'Decoded AAC music must reach Web Audio scheduling');
engine.stopStream(102);
const retired = decodedAudio();
audioDecoders.at(-1).callbacks.output(retired);
assert.equal(context.sources.length, aacStart + 1, 'Retired decoder output must not restart a closed stream');
assert.equal(retired.closed, true);

// Replay the observed wireless music cadence: 18 AAC packets, then ~400 ms
// without data. Packet timestamps carry a continuous 48 kHz sample clock.
const music = new AudioEngine((error) => errors.push(error));
await music.unlock();
const musicContext = contexts.at(-1);
music.handleConfig({ ...config, codec: 1, streamType: 102, name: 'media' });
for (let batch = 0; batch < 40; batch++) {
  musicContext.currentTime = batch * 18 * 1024 / 48000 + (batch % 2 ? 0.033 : 0);
  for (let index = 0; index < 18; index++) {
    music.handlePacket({ ...packet, streamType: 102, timestampUs: (batch * 18 + index) * 1024 / 48000 * 1e6 });
  }
}
assert.equal(musicContext.sources.length, 40 * 18,
  'The observed 400 ms wireless bursts must play every AAC buffer without dropping music');
for (let index = 1; index < musicContext.sources.length; index++) {
  const previous = musicContext.sources[index - 1];
  assert.ok(Math.abs(musicContext.sources[index].startTime - previous.startTime - 1024 / 48000) < 1e-8,
    'Wireless music bursts must remain gapless across packet-free intervals');
}
const musicStats = music.takePlaybackStats();
assert.equal(musicStats.underruns, 0);
assert.equal(musicStats.dropped, 0);
assert.equal(musicStats.scheduled, 720);
assert.ok(musicStats.maxQueuedMs <= 1200);
music.stopAll();

let nextFrame = 0;
const callbacks = new Map();
globalThis.window = {
  requestAnimationFrame(callback) { callbacks.set(++nextFrame, callback); return nextFrame; },
  cancelAnimationFrame(id) { callbacks.delete(id); },
  setTimeout() { return 1; }, clearTimeout() {},
};
const decoders = [];
globalThis.VideoDecoder = class {
  decodeQueueSize = 0;
  constructor(callbacks) { this.callbacks = callbacks; decoders.push(this); }
  configure(config) { this.config = config; }
  close() { this.closed = true; }
};
const painted = [];
const canvas = { width: 0, height: 0, getContext: () => ({ drawImage(frame) { painted.push(frame.id); } }) };
const player = new VideoPlayer(canvas, () => {}, () => {}, () => {});
player.configure({ kind: 'video-config', streamType: 110, codec: 1, width: 1280, height: 720,
  codecData: new Uint8Array([1, 100, 0, 31, 255]) });
const decoder = decoders.at(-1);
assert.equal(decoder.config.optimizeForLatency, true);
function frame(id) {
  return { id, displayWidth: 1280, displayHeight: 720, closed: false, close() { this.closed = true; } };
}
const first = frame(1), second = frame(2);
decoder.callbacks.output(first); decoder.callbacks.output(second);
assert.equal(first.closed, true, 'Superseded decoded frames must release their GPU resources');
assert.equal(callbacks.size, 1, 'A decode burst must schedule just one display paint');
for (const [id, callback] of callbacks) { callbacks.delete(id); callback(); }
assert.deepEqual(painted, [2], 'Render the latest decoded frame, without dropping encoded dependencies');
assert.equal(second.closed, true);
const third = frame(3);
decoder.callbacks.output(third);
player.close();
assert.equal(third.closed, true);
assert.equal(callbacks.size, 0, 'Closing must cancel a pending display paint');
console.log('Media checks passed: jitter continuity, underrun recovery, bounded burst playback without cancellation, stream cleanup, and latest-frame rendering.');
