/**
 * fake-clamd.mjs
 *
 * A minimal stand-in for clamd, implementing enough of the INSTREAM protocol to
 * exercise the QMS ClamAV adapter for real:
 *
 *   client -> "zINSTREAM\0"
 *   client -> [4-byte big-endian length][chunk]...  terminated by a zero length
 *   server -> "stream: OK\0"  or  "stream: <Signature> FOUND\0"
 *
 * It deliberately speaks the wire format rather than being stubbed out, so the
 * adapter's framing, NUL handling and verdict parsing are all genuinely tested.
 *
 * Every connection logs one JSON line to stdout with the byte count it received,
 * which lets the test assert that the upload arrived intact.
 *
 * Usage:
 *   node fake-clamd.mjs --port=3310 --verdict=ok|found [--delay-ms=0] [--close-after=0]
 *
 *   --verdict=found        always report a detection
 *   --close-after=<bytes>  close the connection after N bytes instead of replying
 *                          (simulates a daemon that dies mid-transfer)
 */
import net from 'node:net'

const argv = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, '').split('=')
    return [key, rest.join('=')]
  })
)

const port = Number(argv.port ?? 3310)
const verdict = argv.verdict ?? 'ok'
const delayMs = Number(argv['delay-ms'] ?? 0)
const closeAfter = Number(argv['close-after'] ?? 0)

const PREFIX = Buffer.from('zINSTREAM\0', 'ascii')

function logLine(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

const server = net.createServer((socket) => {
  let buffer = Buffer.alloc(0)
  let sawPrefix = false
  let received = 0
  let done = false

  socket.on('data', (chunk) => {
    if (done) return
    buffer = Buffer.concat([buffer, chunk])

    if (!sawPrefix) {
      if (buffer.length < PREFIX.length) return
      const head = buffer.subarray(0, PREFIX.length)
      if (!head.equals(PREFIX)) {
        logLine({ event: 'bad-prefix', got: head.toString('latin1') })
        socket.destroy()
        done = true
        return
      }
      buffer = buffer.subarray(PREFIX.length)
      sawPrefix = true
    }

    // Read length-prefixed chunks until the zero-length terminator arrives.
    for (;;) {
      if (buffer.length < 4) return
      const size = buffer.readUInt32BE(0)
      if (size === 0) {
        buffer = buffer.subarray(4)
        done = true
        logLine({ event: 'scan', received, verdict })
        respond()
        return
      }
      if (buffer.length < 4 + size) return
      const payload = buffer.subarray(4, 4 + size)
      received += payload.length
      buffer = buffer.subarray(4 + size)

      if (closeAfter > 0 && received >= closeAfter) {
        done = true
        logLine({ event: 'closed-mid-transfer', received })
        socket.destroy()
        return
      }
    }
  })

  function respond() {
    const send = () => {
      const text = verdict === 'found' ? 'stream: Eicar-Test-Signature FOUND' : 'stream: OK'
      socket.write(Buffer.concat([Buffer.from(text, 'ascii'), Buffer.from([0])]), () => {
        socket.end()
      })
    }
    if (delayMs > 0) setTimeout(send, delayMs)
    else send()
  }

  socket.on('error', () => {
    /* client gone; nothing to do */
  })
})

server.listen(port, '127.0.0.1', () => {
  logLine({ event: 'listening', port, verdict })
})
