import type { EmergencyType } from './triage.js'

type OverpassElement = { lat?: number; lon?: number; center?: { lat: number; lon: number }; tags?: Record<string, string> }
export type NearbyAuthority = { name: string; phone: string; distance_m: number; latitude: number; longitude: number; address: string | null }

const cache = new Map<string, { expiresAt: number; value: NearbyAuthority[] }>()
const amenityFor: Record<EmergencyType, string> = {
  fire: 'fire_station', crime: 'police', kidnap: 'police', medical: 'hospital', natural_disaster: 'police', general: 'police',
}
const distanceMetres = (latitudeA: number, longitudeA: number, latitudeB: number, longitudeB: number) => {
  const radians = (value: number) => value * Math.PI / 180
  const latitudeDistance = radians(latitudeB - latitudeA)
  const longitudeDistance = radians(longitudeB - longitudeA)
  const value = Math.sin(latitudeDistance / 2) ** 2 + Math.cos(radians(latitudeA)) * Math.cos(radians(latitudeB)) * Math.sin(longitudeDistance / 2) ** 2
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value))
}

export async function findNearbyAuthorities(latitude: number, longitude: number, type: EmergencyType): Promise<NearbyAuthority[]> {
  const key = `${type}:${latitude.toFixed(3)}:${longitude.toFixed(3)}`
  const cached = cache.get(key)
  if (cached && cached.expiresAt > Date.now()) return cached.value
  const amenity = amenityFor[type]
  const query = `[out:json][timeout:12];nwr(around:25000,${latitude},${longitude})["amenity"="${amenity}"];out center tags;`
  const response = await fetch('https://overpass-api.de/api/interpreter', { method: 'POST', headers: { 'user-agent': 'MeshSetu/1.0 (emergency directory)' }, body: query, signal: AbortSignal.timeout(15_000) })
  if (!response.ok) throw new Error('local authority directory unavailable')
  const payload = await response.json() as { elements?: OverpassElement[] }
  const authorities = (payload.elements ?? []).flatMap(element => {
    const tags = element.tags ?? {}
    const phone = tags['contact:phone'] || tags.phone || tags['contact:mobile'] || tags.mobile
    const elementLatitude = element.lat ?? element.center?.lat
    const elementLongitude = element.lon ?? element.center?.lon
    if (!phone || elementLatitude == null || elementLongitude == null) return []
    const address = [tags['addr:housenumber'], tags['addr:street'], tags['addr:suburb'], tags['addr:city'], tags['addr:postcode']].filter(Boolean).join(', ') || null
    return [{ name: tags.name || tags['name:en'] || `Local ${amenity.replace('_', ' ')}`, phone, distance_m: Math.round(distanceMetres(latitude, longitude, elementLatitude, elementLongitude)), latitude: elementLatitude, longitude: elementLongitude, address }]
  }).sort((a, b) => a.distance_m - b.distance_m).slice(0, 3)
  cache.set(key, { expiresAt: Date.now() + 5 * 60_000, value: authorities })
  return authorities
}
