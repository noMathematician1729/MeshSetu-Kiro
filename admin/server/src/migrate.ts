import 'dotenv/config'
import { store } from './store.js'
await store.init()
await store.pool?.end()
console.log('MeshSetu database ready')
