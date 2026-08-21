import { afterAll, beforeAll, expect, test } from 'vitest'
import WebSocket from 'ws'

process.env.NODE_ENV = 'test'
process.env.DATABASE_URL = ''
process.env.MESHSETU_GATEWAY_SECRET = 'room-test-key'
const { server } = await import('./server.js')

let base = ''
const sockets: WebSocket[] = []

beforeAll(async () => {
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  const address = server.address() as { port: number }
  base = `ws://127.0.0.1:${address.port}/v1/rooms/stream`
})

afterAll(async () => {
  for (const socket of sockets) socket.close()
  await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
})

function connect() {
  return new Promise<WebSocket>((resolve, reject) => {
    const socket = new WebSocket(base)
    sockets.push(socket)
    socket.once('open', () => resolve(socket))
    socket.once('error', reject)
  })
}

function nextMessage(socket: WebSocket, type: string) {
  return new Promise<any>((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off('message', onMessage)
      reject(new Error(`timed out waiting for ${type}`))
    }, 2000)
    const onMessage = (raw: WebSocket.RawData) => {
      const message = JSON.parse(raw.toString())
      if (message.type !== type) return
      clearTimeout(timer)
      socket.off('message', onMessage)
      resolve(message)
    }
    socket.on('message', onMessage)
  })
}

async function join(socket: WebSocket, memberId: string) {
  const joined = nextMessage(socket, 'room-joined')
  socket.send(JSON.stringify({
    type: 'join-room',
    siteId: 'site',
    roomId: 'room',
    memberId,
    displayName: memberId,
    gatewayKey: 'room-test-key',
  }))
  await joined
}

test('acknowledges a room message only with remote internet recipients', async () => {
  const sender = await connect()
  await join(sender, 'sender')

  const noRemoteAck = nextMessage(sender, 'room-message-accepted')
  sender.send(JSON.stringify({ type: 'room-message', messageId: 'solo', text: 'solo', sentAtMs: Date.now() }))
  expect((await noRemoteAck).data.recipientCount).toBe(0)

  const receiver = await connect()
  await join(receiver, 'receiver')
  const accepted = nextMessage(sender, 'room-message-accepted')
  const received = nextMessage(receiver, 'room-message')
  sender.send(JSON.stringify({ type: 'room-message', messageId: 'shared', text: 'hello', sentAtMs: Date.now() }))

  expect((await accepted).data).toMatchObject({ messageId: 'shared', recipientCount: 1 })
  expect((await received).data).toMatchObject({ messageId: 'shared', text: 'hello', memberId: 'sender' })
})
