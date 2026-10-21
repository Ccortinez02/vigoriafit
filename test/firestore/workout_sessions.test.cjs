// Pruebas de reglas Firestore para workout_sessions
// Runner: node --test (Node.js >= 18)
// Emulador requerido: firebase emulators:start --only firestore (puerto 8080)

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, getDoc, getDocs, collection,
  updateDoc, deleteDoc, Timestamp, writeBatch,
} = require('firebase/firestore');

let env;

// ── Helpers ──────────────────────────────────────────────────────────────────

const db = (uid, claims) =>
  uid
    ? env.authenticatedContext(uid, claims).firestore()
    : env.unauthenticatedContext().firestore();

/** Crea un documento de sesión válido y finalizado. */
const validSession = (uid = 'alice', overrides = {}) => ({
  workoutId: 'home_fullbody',
  workoutTitle: 'Full body en casa',
  startedAt: Timestamp.fromMillis(1_700_000_000_000),
  status: 1,           // finished
  exercises: [],
  totalSeries: 3,
  ...overrides,
});

/** Ruta de una sesión para el uid dado. */
const sessRef = (client, uid = 'alice', sessId = 'sess-uuid-001') =>
  doc(client, `users/${uid}/workout_sessions/${sessId}`);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-vigoriafit',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync('firestore.rules', 'utf8'),
    },
  });
});

after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

// ── 1. Propietario puede crear y leer ────────────────────────────────────────

test('propietario crea sesión válida finished → permitido', async () => {
  const client = db('alice');
  await assertSucceeds(setDoc(sessRef(client), validSession()));
});

test('propietario lee su propia sesión → permitido', async () => {
  // Escribir directamente via admin para no depender de la regla de create.
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  const client = db('alice');
  await assertSucceeds(getDoc(sessRef(client)));
});

test('propietario lista sus sesiones → permitido', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  const client = db('alice');
  await assertSucceeds(getDocs(collection(client, 'users/alice/workout_sessions')));
});

// ── 2. Acceso denegado a otras cuentas y anónimos ────────────────────────────

test('usuario anónimo no puede leer sesiones ajenas → denegado', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  await assertFails(getDoc(sessRef(db(null))));
});

test('otra cuenta autenticada no puede leer sesión ajena → denegado', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  await assertFails(getDoc(sessRef(db('bob'))));
});

test('otra cuenta no puede crear sesión en path ajeno → denegado', async () => {
  // bob intenta crear una sesión bajo el uid de alice
  const client = db('bob');
  await assertFails(setDoc(sessRef(client, 'alice'), validSession('alice')));
});

test('otra cuenta no puede listar sesiones ajenas → denegado', async () => {
  await assertFails(
    getDocs(collection(db('bob'), 'users/alice/workout_sessions')),
  );
});

// ── 3. Entrenador sin acceso adicional ───────────────────────────────────────

test('entrenador no puede leer sesiones de sus alumnos → denegado', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  // Token con claim trainer:true, pero no es el propietario del path
  const trainerClient = db('trainer-uid', { trainer: true });
  await assertFails(getDoc(sessRef(trainerClient)));
  await assertFails(
    getDocs(collection(trainerClient, 'users/alice/workout_sessions')),
  );
});

// ── 4. Crear solo sesiones finalizadas ───────────────────────────────────────

test('crear sesión con status=0 (active) → denegado', async () => {
  const client = db('alice');
  await assertFails(setDoc(sessRef(client), validSession('alice', { status: 0 })));
});

test('crear sesión con status=2 (cancelled) → denegado', async () => {
  const client = db('alice');
  await assertFails(setDoc(sessRef(client), validSession('alice', { status: 2 })));
});

// ── 5. Validación de campos requeridos ───────────────────────────────────────

test('omitir workoutId → denegado', async () => {
  const data = validSession();
  delete data.workoutId;
  await assertFails(setDoc(sessRef(db('alice')), data));
});

test('omitir workoutTitle → denegado', async () => {
  const data = validSession();
  delete data.workoutTitle;
  await assertFails(setDoc(sessRef(db('alice')), data));
});

test('omitir startedAt → denegado', async () => {
  const data = validSession();
  delete data.startedAt;
  await assertFails(setDoc(sessRef(db('alice')), data));
});

test('omitir exercises → denegado', async () => {
  const data = validSession();
  delete data.exercises;
  await assertFails(setDoc(sessRef(db('alice')), data));
});

test('omitir totalSeries → denegado', async () => {
  const data = validSession();
  delete data.totalSeries;
  await assertFails(setDoc(sessRef(db('alice')), data));
});

// ── 6. Validación de tipos y límites ─────────────────────────────────────────

test('workoutId más largo de 128 caracteres → denegado', async () => {
  const client = db('alice');
  await assertFails(
    setDoc(sessRef(client), validSession('alice', { workoutId: 'x'.repeat(129) })),
  );
});

test('workoutTitle más largo de 200 caracteres → denegado', async () => {
  const client = db('alice');
  await assertFails(
    setDoc(sessRef(client), validSession('alice', { workoutTitle: 'x'.repeat(201) })),
  );
});

test('startedAt no es timestamp → denegado', async () => {
  const client = db('alice');
  await assertFails(
    setDoc(sessRef(client), validSession('alice', { startedAt: '2026-01-01' })),
  );
});

test('exercises con más de 30 elementos → denegado', async () => {
  const client = db('alice');
  await assertFails(
    setDoc(sessRef(client), validSession('alice', { exercises: Array(31).fill({}) })),
  );
});

test('totalSeries negativo → denegado', async () => {
  const client = db('alice');
  await assertFails(
    setDoc(sessRef(client), validSession('alice', { totalSeries: -1 })),
  );
});

test('totalSeries mayor de 500 → denegado', async () => {
  const client = db('alice');
  await assertFails(
    setDoc(sessRef(client), validSession('alice', { totalSeries: 501 })),
  );
});

test('status no es entero → denegado', async () => {
  const client = db('alice');
  await assertFails(
    setDoc(sessRef(client), validSession('alice', { status: 'finished' })),
  );
});

// ── 7. Inmutabilidad: no update, no delete ───────────────────────────────────

test('propietario no puede actualizar sesión existente → denegado', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  const client = db('alice');
  await assertFails(
    updateDoc(sessRef(client), { totalSeries: 10 }),
  );
});

test('propietario no puede sobreescribir sesión con setDoc → denegado', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  const client = db('alice');
  // Una segunda llamada a setDoc sobre un documento existente es un update/merge.
  // Con allow update: if false, debe ser denegado.
  await assertFails(
    setDoc(sessRef(client), validSession('alice', { totalSeries: 10 })),
  );
});

test('propietario no puede eliminar sesión → denegado', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  const client = db('alice');
  await assertFails(deleteDoc(sessRef(client)));
});

// ── 8. Reintento de sync: doc ya existe con mismo contenido ──────────────────

test('reintento de sync: doc ya existe → no se intenta update (verificado en cliente)', async () => {
  // Las reglas bloquean update. El cliente verifica existencia antes de tx.set.
  // Este test confirma que la regla rechaza cualquier update, garantizando
  // que el cliente no puede actualizar silenciosamente aunque lo intente.
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(sessRef(ctx.firestore()), validSession());
  });
  const client = db('alice');
  // Verificar que el documento existe y tiene el contenido esperado
  const snap = await getDoc(sessRef(client));
  assert.ok(snap.exists());
  assert.equal(snap.data().workoutId, 'home_fullbody');
  assert.equal(snap.data().totalSeries, 3);
  assert.equal(snap.data().status, 1);
  // Intentar update → denegado (garantía de inmutabilidad para el cliente)
  await assertFails(updateDoc(sessRef(client), { totalSeries: 99 }));
});

// ── 9. Anónimo no puede crear sesiones ───────────────────────────────────────

test('usuario anónimo no puede crear sesiones → denegado', async () => {
  await assertFails(setDoc(sessRef(db(null)), validSession()));
});
