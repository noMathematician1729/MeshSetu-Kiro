import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const phonePositions = [
  new THREE.Vector3(-6.2, 0.2, 1.8), new THREE.Vector3(-3.35, 0.9, -1.1), new THREE.Vector3(-0.25, 0.1, 1.05),
];
const beaconPosition = new THREE.Vector3(3.15, 0.8, 0);
const gatewayPositions = [
  new THREE.Vector3(7.25, 3.1, -2.15), new THREE.Vector3(8.1, 0.4, 0.05), new THREE.Vector3(7.15, -2.45, 2.2),
];

function makeLabel(text, color, scale = 1) {
  const canvas = document.createElement('canvas');
  canvas.width = 512; canvas.height = 128;
  const context = canvas.getContext('2d');
  context.font = '700 38px Arial'; context.textAlign = 'center'; context.textBaseline = 'middle';
  context.fillStyle = 'rgba(4, 13, 24, .78)'; context.beginPath();
  if (typeof context.roundRect === 'function') context.roundRect(18, 18, 476, 92, 28);
  else context.rect(18, 18, 476, 92);
  context.fill();
  context.strokeStyle = color; context.lineWidth = 3; context.stroke(); context.fillStyle = color; context.fillText(text, 256, 66);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: texture, transparent: true, depthWrite: false }));
  sprite.scale.set(3.15 * scale, .79 * scale, 1);
  return sprite;
}

function makePhone(label) {
  const group = new THREE.Group();
  group.add(new THREE.Mesh(new RoundedBoxGeometry(1.42, 2.65, .34, 8, .16), new THREE.MeshStandardMaterial({ color: 0x10243a, metalness: .55, roughness: .25 })));
  const screen = new THREE.Mesh(new RoundedBoxGeometry(1.18, 2.08, .08, 5, .11), new THREE.MeshStandardMaterial({ color: 0x06111d, emissive: 0x071d2a, emissiveIntensity: .45 }));
  screen.position.set(0, .12, .2); group.add(screen);
  const homeButton = new THREE.Mesh(new THREE.CylinderGeometry(.11, .11, .04, 24), new THREE.MeshStandardMaterial({ color: 0x29465f, metalness: .4 }));
  homeButton.rotation.x = Math.PI / 2; homeButton.position.set(0, -1.08, .23); group.add(homeButton);
  const tag = makeLabel(label, '#f6fbff', .72); tag.position.set(0, -1.85, 0); group.add(tag);
  const offline = new THREE.Group();
  offline.add(new THREE.Mesh(new THREE.TorusGeometry(.38, .035, 10, 48), new THREE.MeshBasicMaterial({ color: 0xff5368 })));
  const slash = new THREE.Mesh(new RoundedBoxGeometry(.94, .075, .05, 2, .025), new THREE.MeshBasicMaterial({ color: 0xff5368 }));
  slash.rotation.z = -Math.PI / 4; offline.add(slash);
  const status = makeLabel('NO INTERNET', '#ff5368', .58); status.position.y = -.72; offline.add(status);
  offline.position.set(0, 2.15, 0); group.add(offline);
  return group;
}

function makeBeacon(label = 'BEACON') {
  const group = new THREE.Group();
  group.add(new THREE.Mesh(new RoundedBoxGeometry(1.55, 2.9, 1, 8, .2), new THREE.MeshStandardMaterial({ color: 0x0d2632, emissive: 0x06352f, emissiveIntensity: .6, metalness: .42, roughness: .25 })));
  const core = new THREE.Mesh(new THREE.SphereGeometry(.28, 32, 32), new THREE.MeshBasicMaterial({ color: 0x3ee29c }));
  core.position.set(0, .52, .62); group.add(core);
  const tag = makeLabel(label, '#3ee29c', .72); tag.position.set(0, -2.05, 0); group.add(tag);
  const signal = new THREE.Group();
  for (let index = 0; index < 4; index += 1) {
    const bar = new THREE.Mesh(new RoundedBoxGeometry(.13, .32 + index * .2, .12, 3, .035), new THREE.MeshBasicMaterial({ color: 0x3ee29c }));
    bar.position.set(-.32 + index * .22, -.16 + index * .1, 0); signal.add(bar);
  }
  const status = makeLabel('CELLULAR UPLINK', '#3ee29c', .62); status.position.y = -.78; signal.add(status);
  signal.position.set(0, 2.45, 0); group.add(signal);
  return group;
}

function makeGateway(label, controlRoom = false) {
  const group = new THREE.Group();
  const width = controlRoom ? 2 : 1.58;
  const height = controlRoom ? 1.12 : .34;
  const depth = controlRoom ? .85 : 1.08;
  group.add(new THREE.Mesh(new RoundedBoxGeometry(width, height, depth, controlRoom ? 7 : 6, controlRoom ? .16 : .08), new THREE.MeshStandardMaterial({ color: 0x16354c, metalness: .42, roughness: .34 })));
  if (controlRoom) {
    const light = new THREE.Mesh(new THREE.SphereGeometry(.09, 18, 18), new THREE.MeshBasicMaterial({ color: 0x3ee29c }));
    light.position.set(-.67, .25, .49); group.add(light);
  } else {
    const top = new THREE.Mesh(new RoundedBoxGeometry(1.18, .08, .78, 4, .04), new THREE.MeshStandardMaterial({ color: 0x214f6b, emissive: 0x11303e, emissiveIntensity: .38 }));
    top.position.set(0, .15, 0); group.add(top);
    [-.4, 0, .4].forEach((x) => { const antenna = new THREE.Mesh(new THREE.CylinderGeometry(.025, .025, .13, 16), new THREE.MeshBasicMaterial({ color: 0x83fff7 })); antenna.position.set(x, .31, .08); group.add(antenna); });
    [-.38, -.19, 0, .19, .38].forEach((x, index) => { const port = new THREE.Mesh(new RoundedBoxGeometry(.09, .045, .04, 2, .01), new THREE.MeshBasicMaterial({ color: index < 3 ? 0x6effb8 : 0x83fff7 })); port.position.set(x, -.03, .55); group.add(port); });
  }
  const tag = makeLabel(label, controlRoom ? '#83fff7' : '#f6fbff', controlRoom ? .62 : .58); tag.position.set(0, controlRoom ? -.95 : -.82, 0); group.add(tag);
  return group;
}

function makeRoute(start, end, color) {
  const midpoint = start.clone().lerp(end, .5);
  midpoint.y += .55; midpoint.z += (end.x - start.x) * .06;
  const curve = new THREE.CatmullRomCurve3([start, midpoint, end], false, 'centripetal');
  const material = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: .3 });
  return { curve, material, tube: new THREE.Mesh(new THREE.TubeGeometry(curve, 52, .035, 8, false), material) };
}

function makePacket(scene) {
  const packet = new THREE.Mesh(new THREE.IcosahedronGeometry(.2, 2), new THREE.MeshBasicMaterial({ color: 0x83fff7 }));
  packet.add(new THREE.Mesh(new THREE.SphereGeometry(.36, 20, 20), new THREE.MeshBasicMaterial({ color: 0x32d4cc, transparent: true, opacity: .16 })));
  scene.add(packet);
  return packet;
}

export default function MeshSimulation() {
  const mountRef = useRef(null);
  const pausedRef = useRef(false);
  const restartRef = useRef(() => undefined);
  const resetViewRef = useRef(() => undefined);
  const addPhoneRef = useRef(() => undefined);
  const addBeaconRef = useRef(() => undefined);
  const [activeStage, setActiveStage] = useState(-1);
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return undefined;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a1626); scene.fog = new THREE.FogExp2(0x0a1626, .017);
    const camera = new THREE.PerspectiveCamera(42, mount.clientWidth / mount.clientHeight, .1, 100);
    camera.position.set(.6, 9.4, 18.5); camera.lookAt(1, .2, 0);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2)); renderer.outputColorSpace = THREE.SRGBColorSpace; renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.42;
    mount.appendChild(renderer.domElement);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true; controls.target.set(1, .1, 0); controls.minDistance = 11; controls.maxDistance = 30; controls.maxPolarAngle = Math.PI * .7;
    const resetCamera = () => { camera.position.set(.6, 9.4, 18.5); controls.target.set(1, .1, 0); controls.update(); };
    resetViewRef.current = resetCamera;
    scene.add(new THREE.HemisphereLight(0xbffcff, 0x0d2432, 1.45));
    const key = new THREE.DirectionalLight(0xffffff, 2.85); key.position.set(-4, 10, 8); scene.add(key);
    const cyan = new THREE.PointLight(0x61efe7, 54, 19, 2); cyan.position.set(-1.5, 2, 2.5); scene.add(cyan);
    const green = new THREE.PointLight(0x6effb8, 48, 17, 2); green.position.copy(beaconPosition).add(new THREE.Vector3(0, 2, 2)); scene.add(green);
    const lift = new THREE.PointLight(0x8fd6ff, 16, 28, 2); lift.position.set(1.8, 5.8, 10); scene.add(lift);
    const floor = new THREE.GridHelper(30, 30, 0x1d6f75, 0x153344); floor.position.y = -2.15; floor.material.transparent = true; floor.material.opacity = .42; scene.add(floor);
    const phoneNodes = [];
    const beaconNodes = [];
    const graph = new Map();
    const meshConnections = [];
    const dynamicConnections = [];
    const dynamicNodes = [];
    const addGraphNode = (node) => { graph.set(node.id, []); };
    const addConnection = (from, to, color, dynamic = false) => {
      const route = makeRoute(from.position.clone().add(new THREE.Vector3(0, .2, 0)), to.position.clone().add(new THREE.Vector3(0, .2, 0)), color);
      const connection = { fromId: from.id, toId: to.id, route, packet: makePacket(scene) };
      connection.packet.visible = false;
      graph.get(from.id).push({ id: to.id, connection, reverse: false });
      graph.get(to.id).push({ id: from.id, connection, reverse: true });
      meshConnections.push(connection); scene.add(route.tube);
      if (dynamic) dynamicConnections.push(connection);
    };
    const addPhoneNode = (position, index, dynamic = false) => {
      const phone = makePhone(`PHONE ${index}`);
      phone.position.copy(position); phone.rotation.y = -.2 + (index % 3) * .14; phone.userData.networkId = `phone-${index}`;
      const node = { id: phone.userData.networkId, position: position.clone(), object: phone, kind: 'phone' };
      phoneNodes.push(node); addGraphNode(node); scene.add(phone);
      if (dynamic) dynamicNodes.push(node);
      return node;
    };
    phonePositions.forEach((position, index) => addPhoneNode(position, index + 1));
    const primaryBeacon = { id: 'beacon-1', position: beaconPosition.clone(), kind: 'beacon' };
    addGraphNode(primaryBeacon); beaconNodes.push(primaryBeacon);
    const beacon = makeBeacon(); beacon.position.copy(beaconPosition); beacon.rotation.y = -.16; scene.add(beacon);
    addConnection(phoneNodes[0], phoneNodes[1], 0x32d4cc);
    addConnection(phoneNodes[1], phoneNodes[2], 0x32d4cc);
    addConnection(phoneNodes[0], phoneNodes[2], 0x32d4cc);
    addConnection(phoneNodes[2], primaryBeacon, 0x32d4cc);
    gatewayPositions.forEach((position, index) => { const destination = makeGateway(index === 0 ? 'EDGE GATEWAY 1' : index === 1 ? 'EDGE GATEWAY 2' : 'CONTROL ROOM', index === 2); destination.position.copy(position); destination.rotation.y = index < 2 ? -.22 : -.32; scene.add(destination); });
    const gatewayRoutes = gatewayPositions.map((point) => makeRoute(beaconPosition, point, 0x3ee29c));
    gatewayRoutes.forEach((route) => scene.add(route.tube));
    let phoneCount = phonePositions.length;
    let beaconCount = 1;
    addPhoneRef.current = () => {
      const index = phoneCount;
      const addedIndex = index - phonePositions.length;
      const ring = Math.floor(addedIndex / 4) + 1;
      const angle = -.75 + (addedIndex % 4) * (Math.PI / 2) + (ring % 2) * .22;
      const radius = 4.2 + (ring - 1) * 2.15;
      const position = new THREE.Vector3(-1.7 + Math.cos(angle) * radius, .2 + (addedIndex % 2) * .35, Math.sin(angle) * radius * .72);
      const phone = addPhoneNode(position, index + 1, true);
      phoneNodes.filter((node) => node.id !== phone.id).sort((a, b) => phone.position.distanceTo(a.position) - phone.position.distanceTo(b.position)).slice(0, 2).forEach((peer) => addConnection(phone, peer, 0x32d4cc, true));
      phoneCount += 1;
    };
    addBeaconRef.current = () => {
      const index = beaconCount;
      const angle = .5 + (index - 1) * 1.35;
      const position = new THREE.Vector3(1.8 + Math.cos(angle) * 3.6, .45, Math.sin(angle) * 3.4);
      const extraBeacon = makeBeacon(`BEACON ${index + 1}`);
      extraBeacon.position.copy(position); extraBeacon.rotation.y = -.16; scene.add(extraBeacon);
      const node = { id: `beacon-${index + 1}`, position: position.clone(), kind: 'beacon' };
      node.object = extraBeacon; addGraphNode(node); beaconNodes.push(node); dynamicNodes.push(node);
      [...phoneNodes].sort((a, b) => position.distanceTo(a.position) - position.distanceTo(b.position)).slice(0, 2).forEach((phone) => addConnection(phone, node, 0x3ee29c, true));
      addConnection(node, primaryBeacon, 0x3ee29c, true); beaconCount += 1;
    };
    const branchPackets = gatewayRoutes.map(() => { const branch = makePacket(scene); branch.visible = false; return branch; });
    const rings = [0, 1, 2].map(() => { const ring = new THREE.Mesh(new THREE.TorusGeometry(.7, .035, 10, 80), new THREE.MeshBasicMaterial({ color: 0x3ee29c, transparent: true, opacity: 0 })); ring.position.copy(beaconPosition); ring.rotation.x = Math.PI / 2; scene.add(ring); return ring; });
    const sosMarker = makeLabel('SOS', '#ff5368', .62);
    sosMarker.visible = false; scene.add(sosMarker);
    const message = { active: false, broadcast: false, delivered: false, plan: new Map(), meshDuration: 0, elapsed: 0, selectedId: null };
    const buildFloodPlan = (startId) => {
      const queue = [startId]; const hops = new Map([[startId, 0]]);
      while (queue.length) { const current = queue.shift(); graph.get(current).forEach((edge) => { if (!hops.has(edge.id)) { hops.set(edge.id, hops.get(current) + 1); queue.push(edge.id); } }); }
      const plan = new Map(); let lastArrival = 0;
      meshConnections.forEach((connection) => {
        const fromHop = hops.get(connection.fromId); const toHop = hops.get(connection.toId);
        if (fromHop === undefined || toHop === undefined) return;
        const start = Math.min(fromHop, toHop) * .9;
        plan.set(connection, { start, reverse: toHop < fromHop });
        lastArrival = Math.max(lastArrival, start + 1.15);
      });
      return { plan, duration: lastArrival };
    };
    const startMessage = (phoneId) => {
      const flood = buildFloodPlan(phoneId);
      if (!flood.plan.size) return;
      const source = phoneNodes.find((node) => node.id === phoneId);
      if (source) { sosMarker.position.copy(source.position).add(new THREE.Vector3(0, 3.45, 0)); sosMarker.visible = true; }
      message.active = true; message.broadcast = false; message.delivered = false; message.plan = flood.plan; message.meshDuration = flood.duration; message.elapsed = 0; message.selectedId = phoneId;
      setActiveStage(0);
    };
    const disposeObject = (object) => {
      object.traverse((child) => {
        if (child.geometry) child.geometry.dispose();
        if (child.material) {
          const materials = Array.isArray(child.material) ? child.material : [child.material];
          materials.forEach((material) => { if (material.map) material.map.dispose(); material.dispose(); });
        }
      });
    };
    const resetNetwork = () => {
      dynamicConnections.splice(0).forEach((connection) => {
        scene.remove(connection.route.tube, connection.packet);
        disposeObject(connection.route.tube); disposeObject(connection.packet);
        [connection.fromId, connection.toId].forEach((id) => {
          const edges = graph.get(id);
          if (edges) graph.set(id, edges.filter((edge) => edge.connection !== connection));
        });
        const connectionIndex = meshConnections.indexOf(connection);
        if (connectionIndex >= 0) meshConnections.splice(connectionIndex, 1);
      });
      dynamicNodes.splice(0).forEach((node) => {
        scene.remove(node.object); disposeObject(node.object); graph.delete(node.id);
        const phoneIndex = phoneNodes.indexOf(node); if (phoneIndex >= 0) phoneNodes.splice(phoneIndex, 1);
        const beaconIndex = beaconNodes.indexOf(node); if (beaconIndex >= 0) beaconNodes.splice(beaconIndex, 1);
      });
      phoneCount = phonePositions.length; beaconCount = 1;
      message.active = false; message.broadcast = false; message.delivered = false; message.plan = new Map(); message.meshDuration = 0; message.elapsed = 0; message.selectedId = null;
      sosMarker.visible = false; pausedRef.current = false; setPaused(false); setActiveStage(-1);
    };
    resetViewRef.current = () => { resetCamera(); resetNetwork(); };
    const raycaster = new THREE.Raycaster(); const pointer = new THREE.Vector2();
    const onCanvasClick = (event) => {
      const bounds = renderer.domElement.getBoundingClientRect();
      pointer.x = ((event.clientX - bounds.left) / bounds.width) * 2 - 1; pointer.y = -((event.clientY - bounds.top) / bounds.height) * 2 + 1;
      raycaster.setFromCamera(pointer, camera);
      const hit = raycaster.intersectObjects(phoneNodes.map((node) => node.object), true)[0];
      if (!hit) return;
      let target = hit.object;
      while (target && !target.userData.networkId) target = target.parent;
      if (target?.userData.networkId) startMessage(target.userData.networkId);
    };
    renderer.domElement.addEventListener('click', onCanvasClick);
    const clock = new THREE.Clock(); let simulationTime = 0; let frame = 0;
    restartRef.current = () => { if (message.plan.size) { message.active = true; message.broadcast = false; message.delivered = false; message.elapsed = 0; setActiveStage(0); } };
    const animate = () => {
      frame = requestAnimationFrame(animate);
      const delta = Math.min(clock.getDelta(), .05); if (!pausedRef.current) simulationTime += delta;
      const pulse = 1 + Math.sin(simulationTime * 8) * .16;
      meshConnections.forEach((connection, index) => { connection.route.material.opacity = .24 + Math.sin(simulationTime * 2.5 + index) * .08; connection.packet.visible = false; }); gatewayRoutes.forEach((route) => { route.material.opacity = .16; }); branchPackets.forEach((branch) => { branch.visible = false; }); rings.forEach((ring) => { ring.material.opacity = 0; });
      phoneNodes.forEach((node) => { node.object.scale.setScalar(1); });
      if (message.active && !pausedRef.current) message.elapsed += delta;
      if (message.active && !message.broadcast) {
        message.plan.forEach((step, connection) => {
          const progress = THREE.MathUtils.clamp((message.elapsed - step.start) / 1.15, 0, 1);
          if (progress <= 0 || progress >= 1) return;
          connection.packet.visible = true; connection.packet.scale.setScalar(pulse); connection.packet.position.copy(connection.route.curve.getPoint(step.reverse ? 1 - progress : progress)); connection.route.material.opacity = .98;
        });
        if (message.elapsed > 1.5) setActiveStage(2); else if (message.elapsed > .65) setActiveStage(1);
        if (message.elapsed >= message.meshDuration) { message.broadcast = true; message.elapsed = 0; setActiveStage(3); }
      } else if (message.active && message.broadcast) {
        rings.forEach((ring, index) => { const progress = THREE.MathUtils.clamp((message.elapsed - index * .32) / 1.8, 0, 1); ring.scale.setScalar(.45 + progress * 3.1); ring.material.opacity = (1 - progress) * .72; });
        gatewayRoutes.forEach((route, index) => { const progress = THREE.MathUtils.clamp((message.elapsed - .7 - index * .16) / 2.1, 0, 1); route.material.opacity = .25 + progress * .72; const branch = branchPackets[index]; branch.visible = progress > 0 && progress < 1; branch.position.copy(route.curve.getPoint(progress)); branch.scale.setScalar(pulse); });
        if (message.elapsed > 3.8) { message.active = false; message.delivered = true; setActiveStage(4); }
      }
      controls.update(delta); renderer.render(scene, camera);
    };
    animate();
    const resize = () => { const { width, height } = mount.getBoundingClientRect(); if (!width || !height) return; camera.aspect = width / height; camera.updateProjectionMatrix(); renderer.setSize(width, height, false); };
    resize();
    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(mount);
    window.addEventListener('resize', resize);
    return () => { restartRef.current = () => undefined; resetViewRef.current = () => undefined; addPhoneRef.current = () => undefined; addBeaconRef.current = () => undefined; resizeObserver.disconnect(); cancelAnimationFrame(frame); window.removeEventListener('resize', resize); renderer.domElement.removeEventListener('click', onCanvasClick); controls.dispose(); renderer.dispose(); renderer.domElement.remove(); scene.traverse((object) => { if (object instanceof THREE.Mesh) { object.geometry.dispose(); const materials = Array.isArray(object.material) ? object.material : [object.material]; materials.forEach((material) => material.dispose()); } }); };
  }, []);

  const togglePaused = () => { const next = !pausedRef.current; pausedRef.current = next; setPaused(next); };

  return <section className="mesh-simulation" id="simulation">
    <div className="container">
      <div className="mesh-simulation__heading"><div><p className="section-label">Live relay simulation</p><h2>Click a phone to send an SOS <em>through the mesh.</em></h2></div><p>Add phones and beacons to grow the network. Then select any phone to route its signed emergency message to help.</p></div>
      <div className="mesh-simulation__stage">
        <nav className="mesh-simulation__timeline" aria-label="Message route progress">{['PHONE 1', 'PHONE 2', 'PHONE 3', 'BEACON', 'RESPONSE HUB'].map((item, index) => <span key={item} className={index <= activeStage ? 'active' : ''}><b>{String(index + 1).padStart(2, '0')}</b>{item}</span>)}</nav>
        <div ref={mountRef} className="mesh-simulation__canvas" aria-label="Interactive 3D MeshSetu message relay simulation" />
        <div className="mesh-simulation__legend"><span><i className="offline" />Phones offline</span><span><i className="relay" />BLE relay</span><span><i className="gateway" />Gateway broadcast</span></div>
        <div className="mesh-simulation__controls" aria-label="Simulation controls"><button type="button" onClick={() => addPhoneRef.current()}>+ Add phone</button><button type="button" onClick={() => addBeaconRef.current()}>+ Add beacon</button><button type="button" onClick={togglePaused} aria-pressed={paused}>{paused ? 'Resume' : 'Pause'}</button><button type="button" onClick={() => { restartRef.current(); if (pausedRef.current) togglePaused(); }}>Restart</button><button type="button" onClick={() => resetViewRef.current()}>Reset view</button></div>
      </div>
    </div>
  </section>;
}
