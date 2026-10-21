const { test, before, after, beforeEach } = require('node:test');
const { readFileSync } = require('node:fs');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, collection, updateDoc, deleteDoc, serverTimestamp, Timestamp, writeBatch, query, where } = require('firebase/firestore');
let env;
const basic = () => ({name:'Alice',goal:3,level:0,daysPerWeek:3,hasGym:false,onboarded:false,createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
const health = () => ({age:25,heightCm:170,weightKg:70,targetWeightKg:70,conditions:[0],allergies:[1],updatedAt:serverTimestamp()});
const db = (uid, claims) => uid ? env.authenticatedContext(uid, claims).firestore() : env.unauthenticatedContext().firestore();
before(async () => { env = await initializeTestEnvironment({projectId:'demo-vigoriafit',firestore:{host:'127.0.0.1',port:8080,rules:readFileSync('firestore.rules','utf8')}}); });
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });
async function createUser(uid='alice') {
  const client = db(uid); const batch = writeBatch(client);
  batch.set(doc(client,`users/${uid}`),basic());
  batch.set(doc(client,`users/${uid}/private/health_profile`),health());
  await assertSucceeds(batch.commit());
}
async function createGroup() {
  const client = db('trainer',{trainer:true}); const batch = writeBatch(client);
  batch.set(doc(client,'groups/g1'), {trainerId:'trainer',trainerName:'Trainer',code:'123456',createdAt:serverTimestamp(),assignedWorkoutId:null,assignedWorkoutTitle:null});
  batch.set(doc(client,'groupInvites/123456'), {groupId:'g1',trainerId:'trainer',createdAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
}
async function join(uid='alice',code='123456') {
  return setDoc(doc(db(uid),`groups/g1/members/${uid}`), {name:uid,joinedAt:serverTimestamp(),inviteCode:code});
}
test('owner creates and reads both profile documents', async()=>{
  await createUser();
  await assertSucceeds(getDoc(doc(db('alice'),'users/alice')));
  await assertSucceeds(getDoc(doc(db('alice'),'users/alice/private/health_profile')));
});
test('anonymous and other users cannot read, write, delete or list private data',async()=>{
  await createUser();
  for(const uid of [null,'bob']) {
    const client=db(uid);
    for(const path of ['users/alice','users/alice/private/health_profile']) {
      await assertFails(getDoc(doc(client,path)));
      await assertFails(setDoc(doc(client,path),path.endsWith('health_profile')?health():basic()));
      await assertFails(deleteDoc(doc(client,path)));
    }
    await assertFails(getDocs(collection(client,'users')));
    await assertFails(getDocs(collection(client,'users/alice/private')));
  }
});
test('trainer role grants no access to student health profile',async()=>{
  await createUser(); await createGroup(); await join();
  await assertFails(getDoc(doc(db('trainer',{trainer:true}),'users/alice/private/health_profile')));
});
test('cannot self-assign roles or pollute schema on create and update',async()=>{
  await assertFails(setDoc(doc(db('alice'),'users/alice'),{...basic(),roles:['trainer']}));
  await createUser();
  await assertFails(updateDoc(doc(db('alice'),'users/alice'),{trainer:true,updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db('alice'),'users/alice/private/anything'),health()));
});
test('validate types, ranges, size and immutable timestamps on updates',async()=>{
  await createUser();
  for(const patch of [{name:'a'.repeat(121)},{goal:99},{level:'beginner'},{daysPerWeek:0},{createdAt:Timestamp.fromMillis(1)}]) {
    await assertFails(updateDoc(doc(db('alice'),'users/alice'),{...patch,updatedAt:serverTimestamp()}));
  }
  for(const patch of [{age:10},{weightKg:-1},{allergies:['wrong']},{conditions:Array(10).fill(0)},{heightCm:'170'}]) {
    await assertFails(updateDoc(doc(db('alice'),'users/alice/private/health_profile'),{...patch,updatedAt:serverTimestamp()}));
  }
  await assertFails(setDoc(doc(db('alice'),'users/alice'),{name:'missing required fields'}));
  await assertSucceeds(updateDoc(doc(db('alice'),'users/alice'),{name:'New name',updatedAt:serverTimestamp()}));
});
test('orphan health documents cannot be created',async()=>{
  await assertFails(setDoc(doc(db('alice'),'users/alice/private/health_profile'),health()));
});
test('ordinary user cannot create a trainer group or impersonate its owner',async()=>{
  const data={trainerId:'alice',trainerName:'Fake',code:'123456',createdAt:serverTimestamp(),assignedWorkoutId:null,assignedWorkoutTitle:null};
  await assertFails(setDoc(doc(db('alice'),'groups/g1'),data));
  await assertFails(setDoc(doc(db('trainer',{trainer:true}),'groups/g1'),data));
});
test('invitation lookup allows join without exposing group/member listings',async()=>{
  await createGroup();
  await assertSucceeds(getDoc(doc(db('alice'),'groupInvites/123456')));
  await assertFails(getDocs(collection(db('alice'),'groupInvites')));
  await assertFails(getDoc(doc(db('alice'),'groups/g1')));
  await assertFails(join('bob','999999'));
  await assertSucceeds(join());
  await assertSucceeds(getDoc(doc(db('alice'),'groups/g1')));
  await assertFails(getDocs(collection(db('alice'),'groups/g1/members')));
  await assertSucceeds(getDocs(collection(db('trainer',{trainer:true}),'groups/g1/members')));
});
test('only group trainer assigns routine; ownership cannot change',async()=>{
  await createGroup(); await join();
  const patch={assignedWorkoutId:'w1',assignedWorkoutTitle:'Routine',assignedAt:serverTimestamp()};
  await assertFails(updateDoc(doc(db('alice'),'groups/g1'),patch));
  await assertFails(updateDoc(doc(db('other',{trainer:true}),'groups/g1'),patch));
  await assertSucceeds(updateDoc(doc(db('trainer',{trainer:true}),'groups/g1'),patch));
  await assertFails(updateDoc(doc(db('trainer',{trainer:true}),'groups/g1'),{trainerId:'alice',assignedAt:serverTimestamp()}));
});
test('only group owner can create and update assignments; members can read',async()=>{
  await createGroup(); await join();
  const now = Timestamp.now();
  const asgn = {
    groupId:'g1', trainerId:'trainer', workoutId:'w1', workoutTitle:'Routine',
    exercisesSnapshot:[], startAt:serverTimestamp(), daysPerWeek:3,
    timezone:'America/Santiago', status:'active', createdAt:serverTimestamp(),
  };
  // Alumno no puede crear
  await assertFails(setDoc(doc(db('alice'),'groups/g1/assignments/a1'),asgn));
  // Otro entrenador no puede crear
  await assertFails(setDoc(doc(db('other',{trainer:true}),'groups/g1/assignments/a1'),asgn));
  // Dueño puede crear
  await assertSucceeds(setDoc(doc(db('trainer',{trainer:true}),'groups/g1/assignments/a1'),asgn));
  // Alumno puede leer la asignación
  await assertSucceeds(getDoc(doc(db('alice'),'groups/g1/assignments/a1')));
  // Entrenador puede listar asignaciones
  await assertSucceeds(getDocs(collection(db('trainer',{trainer:true}),'groups/g1/assignments')));
  // Solo status puede cambiar en update
  await assertSucceeds(updateDoc(doc(db('trainer',{trainer:true}),'groups/g1/assignments/a1'),{status:'inactive'}));
  // No puede cambiar otro campo en update
  await assertFails(updateDoc(doc(db('trainer',{trainer:true}),'groups/g1/assignments/a1'),{daysPerWeek:5}));
  // No puede borrar
  await assertFails(deleteDoc(doc(db('trainer',{trainer:true}),'groups/g1/assignments/a1')));
});
test('assignment validation rejects missing or out-of-range fields',async()=>{
  await createGroup();
  const base = {
    groupId:'g1', trainerId:'trainer', workoutId:'w1', workoutTitle:'Routine',
    exercisesSnapshot:[], startAt:serverTimestamp(), daysPerWeek:3,
    timezone:'America/Santiago', status:'active', createdAt:serverTimestamp(),
  };
  // daysPerWeek fuera de rango
  await assertFails(setDoc(doc(db('trainer',{trainer:true}),'groups/g1/assignments/bad1'),{...base,daysPerWeek:0}));
  await assertFails(setDoc(doc(db('trainer',{trainer:true}),'groups/g1/assignments/bad2'),{...base,daysPerWeek:8}));
  // status inválido al crear
  await assertFails(setDoc(doc(db('trainer',{trainer:true}),'groups/g1/assignments/bad3'),{...base,status:'inactive'}));
  // campo extra
  await assertFails(setDoc(doc(db('trainer',{trainer:true}),'groups/g1/assignments/bad4'),{...base,extra:'oops'}));
});
test('completion ownership and leaving a group enforce access',async()=>{
  await createGroup(); await join();
  // El doc ID debe coincidir con sessionId (idempotencia garantizada por reglas).
  const sid = 'sess-uuid-001';
  const completion={sessionId:sid,userId:'alice',userName:'Alice',workoutId:'w1',workoutTitle:'Routine',completedAt:serverTimestamp()};
  // No-miembro no puede crear
  await assertFails(setDoc(doc(db('bob'),'groups/g1/completions/'+sid),completion));
  // No puede declarar userId ajeno
  await assertFails(setDoc(doc(db('alice'),'groups/g1/completions/'+sid),{...completion,userId:'bob'}));
  // Doc ID != sessionId → denegado
  await assertFails(setDoc(doc(db('alice'),'groups/g1/completions/wrong-id'),completion));
  // Crear válida → permitido
  await assertSucceeds(setDoc(doc(db('alice'),'groups/g1/completions/'+sid),completion));
  // Reintento con mismo doc → denegado (update: if false)
  await assertFails(setDoc(doc(db('alice'),'groups/g1/completions/'+sid),completion));
  // Entrenador puede listar completions
  await assertSucceeds(getDocs(query(collection(db('trainer',{trainer:true}),'groups/g1/completions'),where('completedAt','>',Timestamp.fromMillis(0)))));
  await assertSucceeds(deleteDoc(doc(db('alice'),'groups/g1/members/alice')));
  await assertFails(getDoc(doc(db('alice'),'groups/g1')));
});

// ── Sprint 5: food_records y water_records ────────────────────────────────

// Timestamp fijo para createdAt: permite que el valor se repita entre create y update.
const FIXED_CREATED = Timestamp.fromMillis(1700000000000);
const foodRecord = (uid='alice', rid='fr1', overrides={}) => ({
  id:rid, uid, foodId:'pollo_pechuga_cocida', foodName:'Pollo pechuga cocida',
  refQty:100, refUnit:'g', kcalRef:165, proteinRef:31, carbsRef:0, fatRef:3.57,
  qty:150, unit:'g', meal:1,
  consumedAt:serverTimestamp(), createdAt:FIXED_CREATED, updatedAt:serverTimestamp(),
  ...overrides,
});
const waterRecord = (uid='alice', rid='wr1', overrides={}) => ({
  id:rid, uid, ml:250,
  recordedAt:serverTimestamp(), createdAt:FIXED_CREATED, updatedAt:serverTimestamp(),
  ...overrides,
});

test('owner creates, reads and deletes own food_records; others cannot',async()=>{
  await createUser();
  const rid = 'fr1';
  // Propietario crea
  await assertSucceeds(setDoc(doc(db('alice'),`users/alice/food_records/${rid}`), foodRecord()));
  // Propietario lee
  await assertSucceeds(getDoc(doc(db('alice'),`users/alice/food_records/${rid}`)));
  await assertSucceeds(getDocs(collection(db('alice'),'users/alice/food_records')));
  // Otro usuario no puede leer ni escribir
  await assertFails(getDoc(doc(db('bob'),`users/alice/food_records/${rid}`)));
  await assertFails(setDoc(doc(db('bob'),`users/alice/food_records/${rid}`), foodRecord('bob',rid)));
  // No autenticado tampoco
  await assertFails(getDoc(doc(db(null),`users/alice/food_records/${rid}`)));
  // Propietario elimina
  await assertSucceeds(deleteDoc(doc(db('alice'),`users/alice/food_records/${rid}`)));
});

test('food_record update: propietario puede actualizar qty y meal; no puede cambiar id ni createdAt',async()=>{
  await createUser();
  const rid = 'fr2';
  await assertSucceeds(setDoc(doc(db('alice'),`users/alice/food_records/${rid}`), foodRecord('alice',rid)));
  // Actualización válida: cambia qty
  await assertSucceeds(setDoc(doc(db('alice'),`users/alice/food_records/${rid}`),
    foodRecord('alice',rid,{qty:200,updatedAt:serverTimestamp()})));
  // No puede cambiar el id del registro
  await assertFails(setDoc(doc(db('alice'),`users/alice/food_records/${rid}`),
    foodRecord('alice',rid,{id:'other-id'})));
  // Campo extra denegado
  await assertFails(setDoc(doc(db('alice'),`users/alice/food_records/${rid}`),
    foodRecord('alice',rid,{extra:'oops'})));
});

test('food_record validation rejects invalid data',async()=>{
  await createUser();
  // qty <= 0 denegado
  await assertFails(setDoc(doc(db('alice'),'users/alice/food_records/bad1'), foodRecord('alice','bad1',{qty:0})));
  // refQty <= 0 denegado
  await assertFails(setDoc(doc(db('alice'),'users/alice/food_records/bad2'), foodRecord('alice','bad2',{refQty:-1})));
  // uid distinto del autenticado
  await assertFails(setDoc(doc(db('alice'),'users/alice/food_records/bad3'), foodRecord('bob','bad3')));
  // id distinto del doc path
  await assertFails(setDoc(doc(db('alice'),'users/alice/food_records/bad4'), foodRecord('alice','wrong-id')));
  // meal fuera de rango
  await assertFails(setDoc(doc(db('alice'),'users/alice/food_records/bad5'), foodRecord('alice','bad5',{meal:10})));
});

test('owner creates, reads and deletes own water_records; others cannot',async()=>{
  await createUser();
  const rid = 'wr1';
  // Propietario crea
  await assertSucceeds(setDoc(doc(db('alice'),`users/alice/water_records/${rid}`), waterRecord()));
  // Propietario lee y lista
  await assertSucceeds(getDoc(doc(db('alice'),`users/alice/water_records/${rid}`)));
  await assertSucceeds(getDocs(collection(db('alice'),'users/alice/water_records')));
  // Otro usuario denegado
  await assertFails(getDoc(doc(db('bob'),`users/alice/water_records/${rid}`)));
  await assertFails(setDoc(doc(db('bob'),`users/alice/water_records/${rid}`), waterRecord('bob',rid)));
  // Propietario elimina (#257: corrección borrando el registro)
  await assertSucceeds(deleteDoc(doc(db('alice'),`users/alice/water_records/${rid}`)));
});

test('water_record update: propietario puede corregir ml; no puede cambiar id (#257)',async()=>{
  await createUser();
  const rid = 'wr2';
  await assertSucceeds(setDoc(doc(db('alice'),`users/alice/water_records/${rid}`), waterRecord('alice',rid)));
  // Corrección válida: actualizar ml
  await assertSucceeds(setDoc(doc(db('alice'),`users/alice/water_records/${rid}`),
    waterRecord('alice',rid,{ml:500,updatedAt:serverTimestamp()})));
  // id inmutable en update
  await assertFails(setDoc(doc(db('alice'),`users/alice/water_records/${rid}`),
    waterRecord('alice',rid,{id:'other-id'})));
});

test('water_record validation rejects invalid data',async()=>{
  await createUser();
  // ml <= 0 denegado
  await assertFails(setDoc(doc(db('alice'),'users/alice/water_records/bad1'), waterRecord('alice','bad1',{ml:0})));
  // uid ajeno
  await assertFails(setDoc(doc(db('alice'),'users/alice/water_records/bad2'), waterRecord('bob','bad2')));
  // id distinto del path
  await assertFails(setDoc(doc(db('alice'),'users/alice/water_records/bad3'), waterRecord('alice','wrong-id')));
  // campo extra
  await assertFails(setDoc(doc(db('alice'),'users/alice/water_records/bad4'), waterRecord('alice','bad4',{extra:'x'})));
});
